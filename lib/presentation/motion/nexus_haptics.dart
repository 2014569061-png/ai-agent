import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'motion_preferences.dart';

/// NEXUS 统一微触觉反馈服务 (Micro-haptics)
///
/// 规范与适用场景：
/// - [light]: 轻触感。Tab / 模式切换、展开/收起折叠卡片、点按输入框辅助磁贴
/// - [selection]: 选择点按。开关切换、单选框、执行批准确认
/// - [medium]: 阻尼中触感。长按呼出快捷菜单、底部抽屉拉起
/// - [warning]: 警告反馈。敏感操作拦截、删除危险确认
/// - [success]: 成功反馈。任务执行完成、消息成功投递
abstract final class NexusHaptics {
  static bool _shouldSkip(BuildContext? context) {
    if (context == null) return false;
    return MotionPreferences.animationsDisabled(context);
  }

  /// 轻量触觉反馈（最常用，用于微交互与瞬时响应）
  static void light([BuildContext? context]) {
    if (_shouldSkip(context)) return;
    HapticFeedback.lightImpact();
  }

  /// 选项变更触觉（用于 Switch、Checkbox、Radio 等状态变更）
  static void selection([BuildContext? context]) {
    if (_shouldSkip(context)) return;
    HapticFeedback.selectionClick();
  }

  /// 中等触觉反馈（用于长按、拖拽抽屉、模态弹窗呼出）
  static void medium([BuildContext? context]) {
    if (_shouldSkip(context)) return;
    HapticFeedback.mediumImpact();
  }

  /// 警告或危险触觉反馈
  static void warning([BuildContext? context]) {
    if (_shouldSkip(context)) return;
    HapticFeedback.heavyImpact();
  }

  /// 成功与完成确认反馈
  static void success([BuildContext? context]) {
    if (_shouldSkip(context)) return;
    HapticFeedback.mediumImpact();
  }
}
