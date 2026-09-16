import 'package:flutter/widgets.dart';

/// 动效与无障碍偏好管理
abstract final class MotionPreferences {
  /// 判断当前上下文是否开启了「减少动态效果」
  static bool shouldReduceMotion(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// 根据无障碍偏好调整动效时长：开启减少动态效果时返回 Duration.zero 或微秒级
  static Duration adjustDuration(
    BuildContext context,
    Duration duration, {
    Duration reducedDuration = Duration.zero,
  }) {
    if (shouldReduceMotion(context)) {
      return reducedDuration;
    }
    return duration;
  }
}
