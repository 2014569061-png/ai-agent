import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import '../motion/motion_preferences.dart';
import '../motion/motion_lifecycle.dart';
import '../motion/motion_tier.dart';
import '../motion/nexus_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';

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
    with TickerProviderStateMixin, MotionLifecycle<NexusExecutionStatus> {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  /// M9：运行结束（running / preparing → succeeded）时光环收拢 180ms。
  late final AnimationController _finishController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(begin: 0.68, end: 1.0).animate(
      CurvedAnimation(
          parent: _pulseController, curve: NexusMotion.curveBreathing),
    );
    _finishController = AnimationController(
      vsync: this,
      duration: NexusMotion.glowRingCollapse,
    );
  }

  /// 外发光环是否可用：装饰动效在运行（full 档、前台、可见），且档位允许光感。
  bool get _glowRingAllowed =>
      DesktopTheme.maybeOf(context) != null &&
      decorativeMotionActive &&
      MotionBudget.of(context, listen: false).shimmer;

  @override
  void didUpdateWidget(covariant NexusExecutionStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldPulse(oldWidget.state) &&
        widget.state == NexusExecutionState.succeeded &&
        _glowRingAllowed) {
      _finishController.forward(from: 0);
    } else if (widget.state != NexusExecutionState.succeeded &&
        _finishController.isAnimating) {
      _finishController.stop();
      _finishController.value = 0;
    }
    onMotionActivityChanged();
  }

  @override
  void onMotionActivityChanged() {
    if (decorativeMotionActive && _shouldPulse(widget.state)) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
    }
    if (!decorativeMotionActive && _finishController.isAnimating) {
      _finishController.stop();
      _finishController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _finishController.dispose();
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
          AppPalette.brandTextFor(isDark),
          isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
        ),
      NexusExecutionState.running => (
          Icons.sync_rounded,
          AppPalette.brandTextFor(isDark),
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

    Widget iconWidget = Icon(
      icon,
      key: ValueKey(widget.state),
      size: widget.compact ? 14 : 16,
      color: fg,
    );
    if (!reduceMotion) {
      iconWidget = AnimatedSwitcher(
        duration: NexusMotion.fast,
        switchInCurve: NexusMotion.curveEnter,
        switchOutCurve: NexusMotion.curveExit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: iconWidget,
      );
    }
    if (_shouldPulse(widget.state) && decorativeMotionActive) {
      iconWidget = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Opacity(
          opacity: _pulseAnimation.value,
          child: child,
        ),
        child: iconWidget,
      );
    }
    // M9 外发光环：运行中与呼吸同相（α 0→0.25、外扩 0→6dp），完成时收拢。
    // 始终包一层 CustomPaint（painter 可为空），保持结构稳定；画在图标
    // 背后且允许溢出图标边界，不影响布局。
    final ringAllowed = DesktopTheme.maybeOf(context) != null &&
        decorativeMotionActive &&
        MotionBudget.of(context).shimmer;
    final ringMode = !ringAllowed
        ? null
        : _shouldPulse(widget.state)
            ? ExecutionGlowRingMode.breathing
            : (widget.state == NexusExecutionState.succeeded &&
                    _finishController.isAnimating)
                ? ExecutionGlowRingMode.collapsing
                : null;
    iconWidget = CustomPaint(
      painter: ringMode == null
          ? null
          : ExecutionGlowRingPainter(
              pulse: _pulseController,
              finish: _finishController,
              color: fg,
              mode: ringMode,
            ),
      child: iconWidget,
    );

    if (widget.compact) {
      return Semantics(
        label: '状态：${widget.label}',
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : NexusMotion.fast,
          curve: NexusMotion.curveStandard,
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
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : NexusMotion.base,
        curve: NexusMotion.curveStandard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(MobileTheme.cardRadius(context)),
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
                  _ActionTextButton(
                      label: '查看详情', onTap: widget.onViewDetails!),
              ],
            ),
            if (widget.detail != null && widget.detail!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.detail!,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  color: isDark
                      ? AppPalette.darkTextMuted
                      : AppPalette.lightTextMuted,
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
                        foregroundColor: isDark
                            ? AppPalette.darkTextMuted
                            : AppPalette.lightTextMuted,
                        side: BorderSide(
                          color: isDark
                              ? AppPalette.darkHairline
                              : AppPalette.lightHairline,
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
                        backgroundColor: MobileTheme.brand(context),
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

enum ExecutionGlowRingMode { breathing, collapsing }

/// 执行状态图标的外发光环（径向渐变，无 blur 滤镜）。
class ExecutionGlowRingPainter extends CustomPainter {
  ExecutionGlowRingPainter({
    required this.pulse,
    required this.finish,
    required this.color,
    required this.mode,
  }) : super(repaint: Listenable.merge([pulse, finish]));

  final Animation<double> pulse;
  final Animation<double> finish;
  final Color color;
  final ExecutionGlowRingMode mode;

  static const double maxAlpha = 0.25;

  /// 当前强度 0→1：呼吸时跟随脉冲（同相），收拢时从 1 线性降到 0。
  double get intensity => switch (mode) {
        ExecutionGlowRingMode.breathing =>
          NexusMotion.curveBreathing.transform(pulse.value.clamp(0.0, 1.0)),
        ExecutionGlowRingMode.collapsing =>
          1 - NexusMotion.curveExit.transform(finish.value.clamp(0.0, 1.0)),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final k = intensity;
    if (k <= 0.001 || size.isEmpty) return;
    final inner = size.shortestSide / 2;
    final radius = inner + NexusMotion.glowRingSpread * k;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: maxAlpha * k),
          color.withValues(alpha: 0),
        ],
        stops: [inner / radius * 0.8, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(ExecutionGlowRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.mode != mode ||
      oldDelegate.pulse != pulse ||
      oldDelegate.finish != finish;
}

class _ActionTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionTextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTokens.fontSizeFootnote,
            fontWeight: FontWeight.w500,
            color: AppPalette.brandText(context),
          ),
        ),
      ),
    );
  }
}
