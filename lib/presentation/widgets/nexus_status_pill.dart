import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
/// 严格统一状态颜色、图标、文案与布局，支持小尺寸与常规尺寸。
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
      'waiting_approval' || 'awaiting_approval' || 'approval' =>
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (label, icon, color) = switch (status) {
      NexusStatusType.draft => (
          '待确认',
          Icons.pending_outlined,
          isDark ? const Color(0xFF90B4FE) : AppTheme.brandBright,
        ),
      NexusStatusType.running => (
          '执行中',
          Icons.play_circle_outline_rounded,
          AppTheme.warning,
        ),
      NexusStatusType.paused => (
          '已暂停',
          Icons.pause_circle_outline_rounded,
          isDark ? const Color(0xFF90B4FE) : AppTheme.brandBright,
        ),
      NexusStatusType.waitingApproval => (
          '等待审批',
          Icons.pending_actions_rounded,
          const Color(0xFFFF9500),
        ),
      NexusStatusType.completed => (
          '已完成',
          Icons.check_circle_rounded,
          AppTheme.success,
        ),
      NexusStatusType.failed => (
          '执行失败',
          Icons.error_outline_rounded,
          AppTheme.danger,
        ),
      NexusStatusType.cancelled => (
          '已取消',
          Icons.cancel_outlined,
          theme.colorScheme.outline,
        ),
      NexusStatusType.offline => (
          '离线',
          Icons.cloud_off_rounded,
          theme.colorScheme.outline,
        ),
      NexusStatusType.synced => (
          '已同步',
          Icons.cloud_done_rounded,
          AppTheme.success,
        ),
    };

    final displayText = customLabel ?? label;
    final fontSize = isCompact ? 10.5 : 12.0;
    final iconSize = isCompact ? 12.0 : 14.0;
    final hPadding = isCompact ? 7.0 : 9.0;
    final vPadding = isCompact ? 2.5 : 4.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 0.8,
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
            SizedBox(width: isCompact ? 3.5 : 5.0),
          ],
          Text(
            displayText,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
