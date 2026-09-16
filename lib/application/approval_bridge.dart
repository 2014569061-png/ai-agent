import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/approval_action_codec.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/notifications/notification_service.dart';

/// 锁屏 / 通知栏审批通道。
///
/// **要解决的问题不是"少点一下"，而是一个死锁**：应用不在前台（锁屏、切到别的
/// 应用）时审批弹窗用户根本看不见，于是需要审批的工具会一直等下去，整个运行卡住。
/// 这里把请求落库 + 发一条带「批准/拒绝」动作的通知，用户不解锁就能裁决。
///
/// 安全上不比原来宽松：超时视为**拒绝**，未收到任何决定时调用方保守拒绝。
class ApprovalBridge {
  const ApprovalBridge({this.pollInterval = const Duration(milliseconds: 400)});

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
  }) async {
    final db = database ?? await DatabaseProvider.instance.database;
    final requestId = UniqueId.generate('appr');
    final notificationId = requestId.hashCode & 0x7fffffff;

    await db.insertPendingApproval(
      requestId: requestId,
      toolName: toolName,
      summary: summary,
      risk: risk,
      ttl: timeout + const Duration(minutes: 1),
    );
    await NotificationService.instance.init();
    await NotificationService.instance.showApprovalRequest(
      id: notificationId,
      title: '需要你的批准',
      body: summary,
      requestId: requestId,
    );

    final deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        final decision = await db.findPendingApprovalDecision(requestId);
        if (decision != null) return decision == approvalApproveAction;
        await Future<void>.delayed(pollInterval);
      }
      return null;
    } finally {
      // 无论走到哪条出口都收起通知并清掉握手行：留下的通知会指向一个已经
      // 无人等待的请求，用户之后再点就毫无效果，比不显示更糟。
      await NotificationService.instance.cancel(notificationId);
      try {
        await db.deletePendingApproval(requestId);
      } catch (_) {}
      unawaited(db.prunePendingApprovals().catchError((_) => 0));
    }
  }
}

/// 通知动作的**后台入口**。
///
/// 用户点「批准/拒绝」时插件会在独立 isolate 中按 callback handle 调用它，
/// 因此这里必须自己注册插件、自己打开数据库，不能依赖主 isolate 的任何状态。
/// （与 `scheduledTaskCallbackDispatcher` 是同一套约束。）
@pragma('vm:entry-point')
Future<void> handleApprovalNotificationAction(NotificationResponse response) async {
  final request = parseApprovalActionId(response.actionId);
  if (request == null) return;

  DartPluginRegistrant.ensureInitialized();
  AppDatabase? db;
  try {
    db = await openAppDatabase();
    final applied = await db.decidePendingApproval(
      request.requestId,
      request.approve ? approvalApproveAction : approvalDenyAction,
    );
    if (!applied) {
      // 已经有决定了（前台弹窗或用户连点两次），保留第一条即可，不是错误。
      debugPrint('审批请求 ${request.requestId} 已有决定，忽略后到的动作');
    }
  } catch (error, stack) {
    debugPrint('锁屏审批写入失败: $error\n$stack');
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}
