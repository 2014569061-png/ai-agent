import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const settings = InitializationSettings(android: android, iOS: darwin);
      await _plugin.initialize(settings);
      _initialized = true;
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
}
