import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 后台任务前台服务（C2）：Agent 执行中切后台/锁屏时保持进程存活，通知栏展示「正在运行」。
///
/// 注意：flutter_foreground_task 需要一个独立 isolate 的 TaskHandler，本封装只负责
/// 保持服务存活 + 可取消，真正的 Agent 编排仍在主 isolate 的 ChatController 中运行。
/// 前台服务的核心价值是「防止进程被系统回收」，而非把编排逻辑搬进后台 isolate。
class ForegroundService {
  ForegroundService._();

  static final ForegroundService instance = ForegroundService._();

  static const _channelId = 'nexus_running';
  static const _channelName = 'NEXUS 正在运行';

  bool _initialized = false;

  /// 需要在 main() 里调用，初始化平台通道。
  static void initCommunicationPort() {
    if (!kIsWeb) FlutterForegroundTask.initCommunicationPort();
  }

  Future<void> _ensureInit() async {
    if (_initialized || kIsWeb) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: 'Agent 任务执行期间保持前台运行',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  /// 启动前台服务（幂等）。返回是否成功启动。
  Future<bool> start(
      {String title = 'NEXUS 正在运行', String text = 'Agent 任务执行中…'}) async {
    if (kIsWeb) return false;
    try {
      await _ensureInit();
      if (await FlutterForegroundTask.isRunningService) return true;
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        callback: startCallback,
      );
      return result is ServiceRequestSuccess;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // 停止失败不影响主流程。
    }
  }

  Future<bool> isRunning() async {
    if (kIsWeb) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }
}

/// 后台 isolate 入口：必须为顶层函数并保留 vm:entry-point 注解。
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

/// 仅保持服务存活的空 TaskHandler。真实编排在主 isolate，不需要在后台做任何事。
class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
