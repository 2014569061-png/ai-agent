import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/approval_action_codec.dart';

/// 本地通知服务（E3）：Agent 完成 / 需审批 / 定时任务完成时弹通知，点击回会话。
/// 与 C2（后台任务完成）与 C5（定时任务）共用同一实例，避免重复初始化。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 任务类通知渠道 id（C2/E3/C5 共用）。
  static const String taskChannelId = 'nexus_tasks';

  /// 审批通知渠道 id：单独一条渠道，让用户能在系统设置里单独静音「审批」
  /// 而不影响任务完成通知。
  static const String approvalChannelId = 'nexus_approvals';

  /// [onBackgroundResponse] 必须是顶层函数（或静态方法）。插件在
  /// `initialize` 时只记录它的 callback handle，用户点击通知动作时会在
  /// **独立 isolate** 里按 handle 调用它，因此那里不能依赖主 isolate 的内存状态。
  Future<void> init({
    void Function(NotificationResponse)? onResponse,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse,
  }) async {
    if (kIsWeb || _initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const settings = InitializationSettings(android: android, iOS: darwin);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: onResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
      );
      _initialized = true;
      // Android 13+ otherwise silently drops task notifications.
      await requestPermission();
    } catch (_) {
      // 通知初始化失败不影响主流程（静默降级）。
    }
  }

  /// Android 13+ 需要运行时申请 POST_NOTIFICATIONS。
  Future<void> requestPermission() async {
    if (kIsWeb) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // 权限申请失败静默降级，UI 可引导用户到系统设置。
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb || !_initialized) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          taskChannelId,
          'NEXUS 任务',
          channelDescription: '后台任务、定时任务与审批提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(id, title, body, details, payload: payload);
    } catch (_) {
      // 弹通知失败不阻断任务。
    }
  }

  /// 弹出「可在锁屏/通知栏直接裁决」的审批通知。
  ///
  /// `showsUserInterface: false` 是关键：动作不会拉起界面，而是交给
  /// [handleApprovalNotificationAction]（独立 isolate）处理，因此用户不必解锁、
  /// 也不必打开 App。代价是**不能依赖任何内存状态**，决定只能通过数据库回传。
  ///
  /// 诚实的边界：动作按钮在多数机型的锁屏上可点，但「锁屏是否显示通知内容」由
  /// 用户的系统设置决定——被隐藏正文时按钮是否仍在，各厂商实现不一致。因此这条
  /// 通道是**尽力而为的加速器**，前台弹窗仍是兜底路径。
  Future<void> showApprovalRequest({
    required int id,
    required String title,
    required String body,
    required String requestId,
  }) async {
    if (kIsWeb || !_initialized) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          approvalChannelId,
          'NEXUS 审批',
          channelDescription: '工具审批请求：可在锁屏或通知栏直接批准或拒绝',
          importance: Importance.max,
          priority: Priority.max,
          // public：允许在锁屏上显示正文。敏感工具的通知正文已在调用方脱敏，
          // 不依赖这一项来保护隐私。
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.reminder,
          // 刻意不设 ongoing：用户随时可以手动划掉，避免进程异常时留下一条
          // 无法消除的通知。正常路径由调用方在拿到结果后 cancel。
          autoCancel: true,
          actions: [
            AndroidNotificationAction(
              encodeApprovalActionId(requestId, approve: true),
              '批准',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              encodeApprovalActionId(requestId, approve: false),
              '拒绝',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      );
      await _plugin.show(id, title, body, details, payload: 'approval:$requestId');
    } catch (_) {
      // 通知失败不阻断审批：前台弹窗路径仍在。
    }
  }

  Future<void> cancel(int id) async {
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {
      // 取消失败无害，通知会随用户操作或被系统回收。
    }
  }
}
