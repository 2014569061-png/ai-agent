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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    final colors = AppStatusColors.resolve(context, tone);
    final color = colors.foreground;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final displayText = customLabel ?? label;
    final pillFontSize =
        isCompact ? AppTokens.fontSizeBadge : AppTokens.fontSizeFootnote;
    final iconSize = isCompact ? 12.0 : 13.5;
    final hPadding = isCompact ? 7.0 : 9.0;
    final vPadding = isCompact ? 2.0 : 3.5;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showIcon) ...[
            if (status == NexusStatusType.running &&
                !MotionPreferences.shouldReduceMotion(context))
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
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isCompact ? 96 : 156),
            child: Text(
              displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: pillFontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: color,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
