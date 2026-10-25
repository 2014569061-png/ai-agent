import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../domain/reminder.dart';

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
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        windows: WindowsInitializationSettings(
          appName: 'NEXUS Agent',
          appUserModelId: 'com.nexusagent.app',
          guid: '0ec1a8f3-06b0-4a44-9bd9-5d1470dd9663',
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: onResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
      );
      _initialized = true;
    } catch (_) {
      // 通知初始化失败不影响主流程（静默降级）。
    }
  }

  /// 是否已经就通知权限问过用户。
  ///
  /// 权限只在首次真正发起任务时申请（见 [ensurePermissionOnce]），而不是在
  /// `init()` 里：启动首帧就弹系统弹窗时用户还不知道这个应用会通知什么，拒绝率
  /// 高且 Android 上拒绝两次后就不再弹窗，等于永久失去通知能力。
  bool _permissionRequested = false;

  /// 在「用户刚触发一个真实动作」时申请一次通知权限。
  ///
  /// Android 13+ 不授权会静默丢弃所有通知，所以必须有人主动申请；关键是时机——
  /// 用户发出第一个任务时正好有明确理由（"任务跑完要通知我"）。
  Future<void> ensurePermissionOnce() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    await requestPermission();
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

  /// 读取「应用是被点击某条通知拉起的」对应的 payload。
  ///
  /// 冷启动场景下 `onDidReceiveNotificationResponse` 不会触发（当时没有运行中的
  /// 引擎），只能靠这里取。返回 null 表示本次不是由通知点击启动。
  Future<String?> notificationLaunchPayload() async {
    if (kIsWeb || !_initialized) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (_) {
      // 取不到就当普通启动，不影响主流程。
      return null;
    }
  }

  Future<NotificationResponse?> notificationLaunchResponse() async {
    if (kIsWeb || !_initialized) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp == true
          ? details?.notificationResponse
          : null;
    } catch (_) {
      return null;
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
        windows: WindowsNotificationDetails(),
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {
      // 弹通知失败不阻断任务。
    }
  }

  /// 通知仅负责打开前台查看或拒绝，不授予执行权限。
  /// 后台入口也拒绝旧的 approve 动作，不能只靠隐藏按钮保护。
  /// 身份验证、计划版本与超时校验由前台审批和执行边界负责。
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
          channelDescription: '工具审批请求：打开应用查看或直接拒绝',
          importance: Importance.max,
          priority: Priority.max,
          // 即使调用方正文脱敏，也不主动在锁屏公开请求内容。
          visibility: NotificationVisibility.private,
          category: AndroidNotificationCategory.reminder,
          // 刻意不设 ongoing：用户随时可以手动划掉，避免进程异常时留下一条
          // 无法消除的通知。正常路径由调用方在拿到结果后 cancel。
          autoCancel: true,
          actions: [
            AndroidNotificationAction(
              'review:$requestId',
              '打开查看',
              showsUserInterface: true,
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
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: 'approval:$requestId',
      );
    } catch (_) {
      // 通知失败不阻断审批：前台弹窗路径仍在。
    }
  }

  Future<void> cancel(int id) async {
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {
      // 取消失败无害，通知会随用户操作或被系统回收。
    }
  }

  static int reminderNotificationId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x0fffffff;
    }
    return 0x40000000 | hash;
  }

  /// Read-only capability snapshot; never requests permissions or reschedules.
  Future<ExactAlarmCapability> reminderCapability() async {
    if (kIsWeb || !_initialized) return ExactAlarmCapability.denied;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null || await android.areNotificationsEnabled() != true) {
        return ExactAlarmCapability.denied;
      }
      return await android.canScheduleExactNotifications() == true
          ? ExactAlarmCapability.granted
          : ExactAlarmCapability.degradedInexact;
    } catch (_) {
      return ExactAlarmCapability.denied;
    }
  }

  Future<ExactAlarmCapability> scheduleReminder(ReminderItem reminder) async {
    if (kIsWeb || !_initialized) return ExactAlarmCapability.denied;
    await _plugin.cancel(id: reminderNotificationId(reminder.id));
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null || await android.areNotificationsEnabled() != true) {
      return ExactAlarmCapability.denied;
    }
    final exact = await android.canScheduleExactNotifications() == true;
    try {
      await _plugin.zonedSchedule(
        id: reminderNotificationId(reminder.id),
        title: reminder.title,
        body: reminder.notes.isEmpty ? '点击查看提醒，可稍后提醒或标记完成' : reminder.notes,
        scheduledDate: tz.TZDateTime.from(reminder.effectiveTriggerUtc, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'nexus_reminders',
            'NEXUS 提醒',
            channelDescription: '用户创建的独立提醒事项',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            actions: [
              AndroidNotificationAction('reminder.snooze', '稍后 10 分钟',
                  showsUserInterface: true),
              AndroidNotificationAction('reminder.complete', '完成',
                  showsUserInterface: true),
            ],
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'reminder:${reminder.id}@${reminder.version}',
      );
      return exact
          ? ExactAlarmCapability.granted
          : ExactAlarmCapability.degradedInexact;
    } catch (_) {
      return ExactAlarmCapability.denied;
    }
  }

  Future<void> cancelReminder(String id) async {
    if (kIsWeb ||
        !_initialized ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    await _plugin.cancel(id: reminderNotificationId(id));
  }

  Future<bool> isReminderScheduled(String id) async {
    if (kIsWeb ||
        !_initialized ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final notificationId = reminderNotificationId(id);
    return (await _plugin.pendingNotificationRequests()).any((r) =>
        r.id == notificationId &&
        (r.payload ?? '').startsWith('reminder:$id@'));
  }

  Future<void> reconcileReminderNotifications(
      Set<String> activePayloads) async {
    if (kIsWeb ||
        !_initialized ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if ((pending.payload ?? '').startsWith('reminder:') &&
          !activePayloads.contains(pending.payload)) {
        await _plugin.cancel(id: pending.id);
      }
    }
    for (final active in await _plugin.getActiveNotifications()) {
      final id = active.id;
      if (id != null && id >= 0x40000000 && id < 0x50000000) {
        await _plugin.cancel(id: id);
      }
    }
  }
}

class NotificationReminderDelivery implements ReminderDelivery {
  const NotificationReminderDelivery();
  @override
  Future<ExactAlarmCapability> schedule(ReminderItem reminder) =>
      NotificationService.instance.scheduleReminder(reminder);
  @override
  Future<void> cancel(String reminderId) =>
      NotificationService.instance.cancelReminder(reminderId);
}
