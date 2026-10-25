import 'run_approval_scope.dart';
import 'approval_decision_scope.dart';
import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/approval_action_codec.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../infrastructure/observability/sentry_service.dart';

/// 锁屏 / 通知栏审批通道。
///
/// **要解决的问题不是"少点一下"，而是一个死锁**：应用不在前台（锁屏、切到别的
/// 应用）时审批弹窗用户根本看不见，于是需要审批的工具会一直等下去，整个运行卡住。
/// 请求落库并通知用户；通知只能拒绝，批准必须回到前台查看和验证身份。
///
/// 安全上不比原来宽松：超时视为**拒绝**，未收到任何决定时调用方保守拒绝。
abstract interface class ApprovalNotifications {
  Future<void> show(
      {required int id, required String body, required String requestId});
  Future<void> cancel(int id);
}

class SystemApprovalNotifications implements ApprovalNotifications {
  const SystemApprovalNotifications();
  @override
  Future<void> show(
      {required int id,
      required String body,
      required String requestId}) async {
    await NotificationService.instance.init();
    await NotificationService.instance.showApprovalRequest(
        id: id, title: '需要你的批准', body: body, requestId: requestId);
  }

  @override
  Future<void> cancel(int id) => NotificationService.instance.cancel(id);
}

class ApprovalBridge {
  const ApprovalBridge(
      {this.pollInterval = const Duration(milliseconds: 400),
      this.notifications = const SystemApprovalNotifications()});
  final ApprovalNotifications notifications;

  /// 前台轮询间隔。跨进程没有可靠的事件通知，只能轮询；400ms 在「人点按钮」的
  /// 时间尺度上已经足够快，又不会把数据库读得太频繁。
  final Duration pollInterval;

  /// 登记一次审批请求并等待裁决。
  ///
  /// 返回 true=批准、false=拒绝、null=超时或用户未处理（调用方应保守拒绝）。
  Future<bool?> requestDecision({
    required String toolName,
    required String summary,
    required String risk,
    Duration timeout = const Duration(minutes: 5),
    AppDatabase? database,
    ApprovalDecisionScope? approvalScope,
  }) async {
    final db = database ?? await DatabaseProvider.instance.database;
    final scope = approvalScope ?? RunApprovalScope.current;
    if (scope != null && !await scope.isCurrent()) return false;
    final requestId = scope?.requestId ?? UniqueId.generate('appr');
    final notificationId = requestId.hashCode & 0x7fffffff;

    if (scope == null) {
      await db.insertPendingApproval(
        requestId: requestId,
        toolName: toolName,
        summary: summary,
        risk: risk,
        ttl: timeout + const Duration(minutes: 1),
      );
    }
    var timedOut = false;
    try {
      await notifications.show(
        id: notificationId,
        body: summary,
        requestId: requestId,
      );

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (scope != null && !await scope.isCurrent()) return false;
        final decision = await db.findPendingApprovalDecision(requestId);
        if (decision != null) return decision == approvalApproveAction;
        await Future.any<void>([
          Future<void>.delayed(pollInterval),
          if (scope != null) scope.invalidated
        ]);
      }
      timedOut = true;
      return null;
    } finally {
      // 无论走到哪条出口都收起通知并清掉握手行：留下的通知会指向一个已经
      // 无人等待的请求，用户之后再点就毫无效果，比不显示更糟。
      await notifications.cancel(notificationId);
      try {
        if (timedOut) {
          await db.decidePendingApproval(requestId, approvalExpiredAction);
        } else if (scope == null) {
          await db.deletePendingApproval(requestId);
        }
      } catch (error, stackTrace) {
        // 可忽略：握手行清理失败不影响本次裁决结果（返回值已确定）。
        // 残留行由下方 prunePendingApprovals 的 TTL 兜底回收，不会累积。
        // 仍上报以统计清理失败率——如果它持续升高，说明库写路径有问题。
        unawaited(SentryService.reportException(error, stackTrace));
      }
      unawaited(db.prunePendingApprovals().catchError((_) => 0));
    }
  }
}

/// 通知动作的**后台入口**。
///
/// 用户点「拒绝」时插件会在独立 isolate 中按 callback handle 调用它，
/// 因此这里必须自己注册插件、自己打开数据库，不能依赖主 isolate 的任何状态。
/// （与 `scheduledTaskCallbackDispatcher` 是同一套约束。）
@pragma('vm:entry-point')
Future<void> handleApprovalNotificationAction(
    NotificationResponse response) async {
  // Enforce below the notification UI, including callbacks from old APKs.
  final request = parseBackgroundApprovalActionId(response.actionId);
  if (request == null) return;

  DartPluginRegistrant.ensureInitialized();
  AppDatabase? db;
  try {
    db = await openAppDatabase();
    final applied = await db.decidePendingApproval(
      request.requestId,
      approvalDenyAction,
    );
    if (!applied) {
      // 已经有决定了（前台弹窗或用户连点两次），保留第一条即可，不是错误。
      debugPrint('审批请求 ${request.requestId} 已有决定，忽略后到的动作');
    }
  } catch (error, stack) {
    // 影响用户：锁屏审批写入失败会让用户在通知栏的裁决**静默丢失**，
    // 前台会一直等到 TTL 超时并保守拒绝。必须留下可诊断的记录。
    // 只记录 error type 与 requestId：summary 可能含用户内容，不能进日志。
    unawaited(SentryService.reportException(error, stack));
    debugPrint(
      '锁屏审批写入失败: phase=notification-decision '
      'errorType=${error.runtimeType} requestId=${request.requestId}',
    );
  } finally {
    try {
      await db?.close();
    } catch (error, stackTrace) {
      // 可忽略：后台 isolate 结束前关闭失败会被系统回收，不影响裁决结果。
      unawaited(SentryService.reportException(error, stackTrace));
    }
  }
}
