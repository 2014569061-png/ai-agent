import 'package:flutter/material.dart';
import '../motion/motion_preferences.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 全局统一执行状态枚举
enum NexusExecutionState {
  idle,
  preparing,
  running,
  waitingForUser,
  succeeded,
  failed,
  cancelled,
}

/// 执行状态展示控件（用于聊天执行、工具调用、任务进度、授权等）
class NexusExecutionStatus extends StatefulWidget {
  final NexusExecutionState state;
  final String label;
  final String? detail;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onViewDetails;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool compact;

  const NexusExecutionStatus({
    super.key,
    required this.state,
    required this.label,
    this.detail,
    this.onCancel,
    this.onRetry,
    this.onViewDetails,
    this.onApprove,
    this.onReject,
    this.compact = false,
  });

  @override
  State<NexusExecutionStatus> createState() => _NexusExecutionStatusState();
}

class _NexusExecutionStatusState extends State<NexusExecutionStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_shouldPulse(widget.state)) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant NexusExecutionStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldPulse(widget.state)) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool _shouldPulse(NexusExecutionState s) =>
      s == NexusExecutionState.running || s == NexusExecutionState.preparing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MotionPreferences.shouldReduceMotion(context);

    // 确定当前状态的图标、前景色、背景色
    final (IconData icon, Color fg, Color bg) = switch (widget.state) {
      NexusExecutionState.idle => (
          Icons.schedule_rounded,
          isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
          isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
        ),
      NexusExecutionState.preparing => (
          Icons.hourglass_top_rounded,
          AppPalette.brand,
          isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
        ),
      NexusExecutionState.running => (
          Icons.sync_rounded,
          AppPalette.brand,
          isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
        ),
      NexusExecutionState.waitingForUser => (
          Icons.pan_tool_rounded,
          AppPalette.warning,
          isDark ? AppPalette.darkWarningSoft : AppPalette.lightWarningSoft,
        ),
      NexusExecutionState.succeeded => (
          Icons.check_circle_rounded,
          AppPalette.success,
          isDark ? AppPalette.darkSuccessSoft : AppPalette.lightSuccessSoft,
        ),
      NexusExecutionState.failed => (
          Icons.error_outline_rounded,
          AppPalette.danger,
          isDark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft,
        ),
      NexusExecutionState.cancelled => (
          Icons.cancel_outlined,
          isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
          isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
        ),
    };

    Widget iconWidget = Icon(icon, size: widget.compact ? 14 : 16, color: fg);
    if (_shouldPulse(widget.state) && !reduceMotion) {
      iconWidget = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Opacity(
          opacity: _pulseAnimation.value,
          child: child,
        ),
        child: iconWidget,
      );
    }

    if (widget.compact) {
      return Semantics(
        label: '状态：${widget.label}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    fontWeight: FontWeight.w500,
                    color: fg,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: '状态：${widget.label}。${widget.detail ?? ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(
            color: fg.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                iconWidget,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                if (widget.onCancel != null)
                  _ActionTextButton(label: '取消', onTap: widget.onCancel!),
                if (widget.onRetry != null)
                  _ActionTextButton(label: '重试', onTap: widget.onRetry!),
                if (widget.onViewDetails != null)
                  _ActionTextButton(label: '查看详情', onTap: widget.onViewDetails!),
              ],
            ),
            if (widget.detail != null && widget.detail!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.detail!,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  color: isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
                  height: 1.4,
                ),
              ),
            ],
            if (widget.state == NexusExecutionState.waitingForUser &&
                (widget.onApprove != null || widget.onReject != null)) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onReject != null)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted,
                        side: BorderSide(
                          color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
                        ),
                      ),
                      onPressed: widget.onReject,
                      child: const Text('拒绝'),
                    ),
                  if (widget.onApprove != null) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppPalette.brand,
                      ),
                      onPressed: widget.onApprove,
                      child: const Text('授权继续'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionTextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: AppTokens.fontSizeFootnote,
            fontWeight: FontWeight.w500,
            color: AppPalette.brand,
          ),
        ),
      ),
    );
  }
}
