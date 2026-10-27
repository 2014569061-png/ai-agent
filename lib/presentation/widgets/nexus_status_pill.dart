import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';

import '../theme/app_status_colors.dart';
import '../theme/app_tokens.dart';
import '../motion/motion_preferences.dart';

/// 统一的状态类型枚举，用于保证全应用状态在视觉、文案与图标上的一致性。
enum NexusStatusType {
  draft,
  running,
  paused,
  waitingApproval,
  completed,
  failed,
  cancelled,
  offline,
  synced,
}

/// 全局统一的状态徽标组件 (Status Pill)
class NexusStatusPill extends StatelessWidget {
  const NexusStatusPill({
    super.key,
    required this.status,
    this.customLabel,
    this.isCompact = false,
    this.showIcon = true,
  });

  /// 也可以通过直接传字符串构造
  factory NexusStatusPill.fromString(
    String? statusStr, {
    Key? key,
    String? customLabel,
    bool isCompact = false,
    bool showIcon = true,
  }) {
    final type = switch (statusStr?.toLowerCase().trim()) {
      'draft' || 'pending' => NexusStatusType.draft,
      'running' || 'executing' => NexusStatusType.running,
      'paused' => NexusStatusType.paused,
      'waiting_approval' ||
      'awaiting_approval' ||
      'approval' =>
        NexusStatusType.waitingApproval,
      'completed' || 'success' || 'done' => NexusStatusType.completed,
      'failed' || 'error' => NexusStatusType.failed,
      'cancelled' || 'canceled' => NexusStatusType.cancelled,
      'offline' => NexusStatusType.offline,
      'synced' => NexusStatusType.synced,
      _ => NexusStatusType.draft,
    };
    return NexusStatusPill(
      key: key,
      status: type,
      customLabel: customLabel,
      isCompact: isCompact,
      showIcon: showIcon,
    );
  }

  final NexusStatusType status;
  final String? customLabel;
  final bool isCompact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final (label, icon, tone) = switch (status) {
      NexusStatusType.draft => (
          '待确认',
          Icons.pending_outlined,
          AppStatusTone.brand,
        ),
      NexusStatusType.running => (
          '执行中',
          Icons.play_circle_outline_rounded,
          AppStatusTone.brand,
        ),
      NexusStatusType.paused => (
          '已暂停',
          Icons.pause_circle_outline_rounded,
          AppStatusTone.neutral,
        ),
      NexusStatusType.waitingApproval => (
          '等待审批',
          Icons.pending_actions_rounded,
          AppStatusTone.warning,
        ),
      NexusStatusType.completed => (
          '已完成',
          Icons.check_circle_rounded,
          AppStatusTone.success,
        ),
      NexusStatusType.failed => (
          '执行失败',
          Icons.error_outline_rounded,
          AppStatusTone.danger,
        ),
      NexusStatusType.cancelled => (
          '已取消',
          Icons.cancel_outlined,
          AppStatusTone.neutral,
        ),
      NexusStatusType.offline => (
          '离线',
          Icons.cloud_off_rounded,
          AppStatusTone.neutral,
        ),
      NexusStatusType.synced => (
          '已同步',
          Icons.cloud_done_rounded,
          AppStatusTone.success,
        ),
    };

    final color = AppStatusColors.resolve(context, tone).foreground;
    final displayText = customLabel ?? label;
    final iconSize = isCompact ? 12.0 : 13.5;
    final reduceMotion = MotionPreferences.shouldReduceMotion(context);

    return NexusStatusPillChrome(
      tone: tone,
      isCompact: isCompact,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showIcon) ...[
            if (status == NexusStatusType.running && !reduceMotion)
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 4.0),
          ],
          NexusStatusPillLabel(
            text: displayText,
            color: color,
            isCompact: isCompact,
            maxWidth: isCompact ? 96 : 156,
          ),
        ],
      ),
    );
  }
}

/// 徽标外壳：唯一一处决定内边距、圆角、描边与高对比度规则的实现。
/// 状态枚举形态（[NexusStatusPill]）与自由标签形态（[NexusStatusPillShell]）
/// 都走这里，避免两套徽标各自漂移。
class NexusStatusPillChrome extends StatelessWidget {
  const NexusStatusPillChrome({
    super.key,
    required this.tone,
    required this.isCompact,
    required this.child,
  });

  final AppStatusTone tone;
  final bool isCompact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppStatusColors.resolve(context, tone);
    final color = colors.foreground;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 7.0 : 9.0,
        vertical: isCompact ? 2.0 : 3.5,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
        border: Border.all(
          color: highContrast
              ? color
              : color.withValues(alpha: isDark ? 0.34 : 0.22),
          width: 1.0,
        ),
      ),
      child: child,
    );
  }
}

/// 徽标文字：统一字号、字重与等宽数字，避免各处自行写 TextStyle。
class NexusStatusPillLabel extends StatelessWidget {
  const NexusStatusPillLabel({
    super.key,
    required this.text,
    required this.color,
    required this.isCompact,
    this.maxWidth = 156,
  });

  final String text;
  final Color color;
  final bool isCompact;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize:
              isCompact ? AppTokens.fontSizeBadge : AppTokens.fontSizeFootnote,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 只有标签与语义色调、没有状态枚举的徽标形态（服务连接、来源标记等）。
/// 与 [NexusStatusPill] 共用同一套外壳与文字规格。
class NexusStatusPillShell extends StatelessWidget {
  const NexusStatusPillShell({
    super.key,
    required this.label,
    this.tone = AppStatusTone.neutral,
    this.icon,
    this.showDot = false,
    this.isCompact = true,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;
  final bool showDot;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final color = AppStatusColors.resolve(context, tone).foreground;
    final iconSize = isCompact ? 12.0 : 13.5;

    return NexusStatusPillChrome(
      tone: tone,
      isCompact: isCompact,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5.0),
          ] else if (icon != null) ...[
            Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 4.0),
          ],
          NexusStatusPillLabel(
            text: label,
            color: color,
            isCompact: isCompact,
            maxWidth: isCompact ? 140 : 200,
          ),
        ],
      ),
    );
  }
}
