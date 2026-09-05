import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 电池优化豁免：定时任务/后台 Agent 在激进省电 ROM（华为/小米等）上
/// 依赖系统电池白名单才能按时触发，由用户在设置页手动引导开启。
class BatteryOptimization {
  static const _channel = MethodChannel('nexus/system');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// 是否已在电池优化白名单中。非 Android 平台或通道不可用时视为已豁免，
  /// 避免在桌面/Web 上误报"未开启"。
  static Future<bool> isIgnoring() async {
    if (!supported) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// 拉起系统"忽略电池优化"授权弹窗；ROM 不支持时退回电池优化设置列表。
  static Future<bool> requestIgnore() async {
    if (!supported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
