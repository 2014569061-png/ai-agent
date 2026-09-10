import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

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
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final (label, icon, color) = switch (status) {
      NexusStatusType.draft => (
          '待确认',
          Icons.pending_outlined,
          AppPalette.brand,
        ),
      NexusStatusType.running => (
          '执行中',
          Icons.play_circle_outline_rounded,
          AppPalette.brand,
        ),
      NexusStatusType.paused => (
          '已暂停',
          Icons.pause_circle_outline_rounded,
          textMuted,
        ),
      NexusStatusType.waitingApproval => (
          '等待审批',
          Icons.pending_actions_rounded,
          AppPalette.warning,
        ),
      NexusStatusType.completed => (
          '已完成',
          Icons.check_circle_rounded,
          AppPalette.success,
        ),
      NexusStatusType.failed => (
          '执行失败',
          Icons.error_outline_rounded,
          AppPalette.danger,
        ),
      NexusStatusType.cancelled => (
          '已取消',
          Icons.cancel_outlined,
          textMuted,
        ),
      NexusStatusType.offline => (
          '离线',
          Icons.cloud_off_rounded,
          textMuted,
        ),
      NexusStatusType.synced => (
          '已同步',
          Icons.cloud_done_rounded,
          AppPalette.success,
        ),
    };

    final displayText = customLabel ?? label;
    final fontSize = isCompact ? 11.0 : 12.0;
    final iconSize = isCompact ? 12.0 : 14.0;
    final hPadding = isCompact ? 8.0 : 10.0;
    final vPadding = isCompact ? 2.0 : 4.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.30 : 0.20),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showIcon) ...[
            if (status == NexusStatusType.running)
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
          Text(
            displayText,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
