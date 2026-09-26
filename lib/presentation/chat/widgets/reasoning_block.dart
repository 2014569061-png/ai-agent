import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../domain/models.dart';
import '../../markdown/math_block.dart';
import '../../motion/motion_preferences.dart';
import '../../motion/nexus_haptics.dart';
import '../../motion/nexus_motion.dart';
import '../../widgets/nexus_disclosure.dart';
import '../../widgets/shimmer_text.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// 思考过程与运行进度折叠块。
///
/// 运行中优先展示可验证的阶段摘要（已收到请求、工具调用、当前阶段和
/// 已等待时长），而不是让用户面对一个不会变化的「正在思考…」。原始推理
/// 内容仍然保持可折叠，避免把内部思维链误当成可靠的进度指标。
class ReasoningCompactBlock extends StatefulWidget {
  const ReasoningCompactBlock({
    super.key,
    required this.reasoning,
    this.duration,
    this.streaming = false,
    this.hasStartedAnswer = false,
    this.progress,
    this.onStop,
  });

  final String reasoning;

  /// 思考耗时；为空时只显示「已思考」。
  final Duration? duration;

  /// 正在思考（尚未产出正文）。
  final bool streaming;

  /// 正文已开始输出时，收敛详细时间线，让回答优先占据阅读空间。
  final bool hasStartedAnswer;

  /// 当前运行的用户级进度摘要。
  final ChatRunProgress? progress;

  /// 中断当前生成。输入区已有停止能力，这里作为就近的显式兜底入口。
  final VoidCallback? onStop;

  @override
  State<ReasoningCompactBlock> createState() => _ReasoningCompactBlockState();
}

class _ReasoningCompactBlockState extends State<ReasoningCompactBlock> {
  bool _expanded = false;
  Duration _displayElapsed = Duration.zero;
  Duration _idleElapsed = Duration.zero;
  DateTime? _trackedStartedAt;
  DateTime? _trackedActivityAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncProgressCounters(resetElapsed: true);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ReasoningCompactBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProgressCounters(
      resetElapsed: oldWidget.progress?.startedAt != widget.progress?.startedAt,
    );
    if (oldWidget.streaming != widget.streaming ||
        oldWidget.progress?.startedAt != widget.progress?.startedAt) {
      _syncTicker();
    }
  }

  void _syncProgressCounters({bool resetElapsed = false}) {
    final progress = widget.progress;
    if (resetElapsed || progress?.startedAt != _trackedStartedAt) {
      _displayElapsed = Duration.zero;
      _trackedStartedAt = progress?.startedAt;
    }
    if (progress?.lastActivityAt != _trackedActivityAt) {
      _idleElapsed = Duration.zero;
      _trackedActivityAt = progress?.lastActivityAt;
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.streaming) return;
    // 只刷新当前进度卡，不让 ChatPage 每秒重建；真实业务事件仍由执行层
    // 更新，计时器只负责告诉用户“已经等了多久”。本地累加秒数也让时间
    // 展示不依赖平台墙上时钟，测试和设备休眠恢复都更稳定。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncProgressCounters();
      setState(() {
        _displayElapsed += const Duration(seconds: 1);
        _idleElapsed += const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggleReasoning() {
    NexusHaptics.selection(context);
    setState(() => _expanded = !_expanded);
  }

  String get _label {
    final d = widget.duration;
    if (!widget.streaming) {
      if (d == null) return '已思考';
      final seconds = d.inSeconds < 1 ? 1 : d.inSeconds;
      if (seconds < 60) return '已思考 $seconds 秒';
      return '已思考 ${seconds ~/ 60} 分 ${seconds % 60} 秒';
    }

    // 保留无进度数据时的兼容文案，也让旧消息和单独使用该组件的场景
    // 不会突然出现空标题。
    final raw = widget.progress?.label.trim();
    final base = raw == null || raw.isEmpty ? '正在思考…' : raw;
    if (_isStalled) return '响应较慢，仍在继续…';
    return base;
  }

  bool get _isStalled {
    final progress = widget.progress;
    if (!widget.streaming || progress == null) return false;
    // 等待用户确认或主动暂停不是“模型卡住”，不能用慢响应文案覆盖
    // 用户真正需要处理的动作。
    const modelWorkingStages = {
      ChatRunStage.preparing,
      ChatRunStage.analyzing,
      ChatRunStage.waitingModel,
      ChatRunStage.reasoning,
      ChatRunStage.executingTool,
      ChatRunStage.generating,
    };
    return modelWorkingStages.contains(progress.stage) &&
        _idleElapsed >= const Duration(seconds: 8);
  }

  Duration? get _liveElapsed =>
      widget.progress == null ? null : _displayElapsed;

  String _formatDuration(Duration? duration) {
    if (duration == null) return widget.streaming ? '计算中...' : '00:00:01';
    final totalSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hours = minutes ~/ 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _waitLabel() {
    final elapsed = _liveElapsed;
    if (elapsed == null) return '';
    final seconds = elapsed.inSeconds;
    return '已等待 ${seconds < 1 ? 1 : seconds} 秒';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final hasReasoning = widget.reasoning.trim().isNotEmpty;
    final thinking = widget.streaming;
    final condensedProgress =
        thinking && widget.progress != null && widget.hasStartedAnswer;

    return Container(
      margin: EdgeInsets.symmetric(vertical: condensedProgress ? 3 : 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: '处理进度：$_label',
            child: InkWell(
              // S6：整行可点展开/收起思考过程，不再单独放「思考过程」按钮。
              onTap: hasReasoning ? _toggleReasoning : null,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 320;
                    final showProgressTag = thinking && widget.progress != null;
                    return Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 15,
                          color: AppPalette.brandTextFor(isDark),
                        ),
                        const SizedBox(width: 6),
                        if (thinking)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: AppPalette.brandTextFor(isDark),
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (showProgressTag) ...[
                          Text(
                            '进度',
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeSubcaption,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.brandTextFor(isDark),
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeSubcaption,
                              color: textMuted,
                            ),
                          ),
                        ],
                        Expanded(
                          // M9：思考中标题流光；响应变慢时停止，避免「假装在忙」。
                          child: ShimmerText(
                            enabled: thinking && !_isStalled,
                            child: Text(
                              _label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeSubcaption,
                                fontWeight: FontWeight.w500,
                                color: textMuted,
                              ),
                            ),
                          ),
                        ),
                        // 完成态的耗时已写在标题里；只有运行中且有真实进度时显示计时。
                        if (!compact && showProgressTag) ...[
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(_liveElapsed),
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: AppTokens.fontFamilyMono,
                              fontSize: AppTokens.fontSizeMetricSmall,
                              color: textMuted,
                            ),
                          ),
                        ],
                        if (widget.onStop != null && thinking)
                          Semantics(
                            button: true,
                            label: '停止生成',
                            child: IconButton(
                              onPressed: widget.onStop,
                              tooltip: '停止生成',
                              icon: const Icon(Icons.stop_rounded),
                              color: isDark
                                  ? AppPalette.darkDanger
                                  : AppPalette.lightDanger,
                              iconSize: 16,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        if (hasReasoning) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: _expanded ? '收起思考过程' : '展开思考过程',
                            child: AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: NexusMotion.durationFast(context),
                              curve: NexusMotion.curveStandard,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 18,
                                color: textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          _buildTimelineSlot(
            context,
            thinking && widget.progress != null && !condensedProgress
                ? _buildProgressTimeline(context, cardBorder, textMuted)
                : const SizedBox(width: double.infinity),
          ),
          NexusExpandSection(
            expanded: _expanded,
            duration: NexusMotion.durationBase(context),
            reverseDuration: NexusMotion.durationFast(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 1, color: cardBorder),
                  const SizedBox(height: 8),
                  _buildReasoningContent(context, theme, textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 答案开始后时间线收起：用 AnimatedSize 平滑过渡，避免下方正文跳动。
  /// reduced / off 下不包 AnimatedSize（零时长的 AnimatedSize 会在布局中
  /// 重新标脏自身），直接切换。
  Widget _buildTimelineSlot(BuildContext context, Widget child) {
    if (MotionPreferences.shouldReduceMotion(context)) return child;
    return AnimatedSize(
      duration: NexusMotion.base,
      curve: NexusMotion.curveStandard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  Widget _buildProgressTimeline(
      BuildContext context, Color divider, Color textMuted) {
    final progress = widget.progress!;
    final stage = progress.stage;
    final rows = <_ProgressRow>[
      _ProgressRow(
        label: '已收到请求',
        state: stage == ChatRunStage.received
            ? _ProgressRowState.current
            : _ProgressRowState.done,
      ),
    ];

    if (progress.completedTools > 0) {
      rows.add(_ProgressRow(
        label: '已完成 ${progress.completedTools} 项工具调用',
        state: _ProgressRowState.done,
      ));
    }

    final currentLabel = progress.label.trim();
    if (currentLabel.isNotEmpty &&
        !(stage == ChatRunStage.received && currentLabel == '已收到请求')) {
      rows.add(_ProgressRow(
        label: currentLabel,
        state: _ProgressRowState.current,
      ));
    }

    if (stage != ChatRunStage.generating && stage != ChatRunStage.paused) {
      rows.add(const _ProgressRow(
        label: '生成最终回复',
        state: _ProgressRowState.pending,
      ));
    }

    final generated = progress.generatedCharacters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(31, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: divider),
          const SizedBox(height: 6),
          for (final row in rows) _buildProgressRow(row, textMuted),
          if (generated > 0)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                '已生成 $generated 字',
                style: TextStyle(
                  fontSize: AppTokens.fontSizeMetricSmall,
                  color: textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (_isStalled)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 3),
              child: Text(
                '${_waitLabel()} · 处理时间较长，仍在继续',
                style: TextStyle(
                  fontSize: AppTokens.fontSizeMetricSmall,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppPalette.darkWarning
                      : AppPalette.lightWarning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(_ProgressRow row, Color textMuted) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (row.state) {
      _ProgressRowState.done =>
        isDark ? AppPalette.darkSuccess : AppPalette.lightSuccess,
      _ProgressRowState.current =>
        isDark ? const Color(0xFF93C5FD) : AppPalette.brandAction,
      _ProgressRowState.pending => textMuted,
    };
    final icon = switch (row.state) {
      _ProgressRowState.done => Icons.check_circle_rounded,
      _ProgressRowState.current => Icons.radio_button_checked_rounded,
      _ProgressRowState.pending => Icons.radio_button_unchecked_rounded,
    };
    final isCurrent = row.state == _ProgressRowState.current;
    final reduceMotion = MotionPreferences.shouldReduceMotion(context);
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : NexusMotion.fast,
      curve: NexusMotion.curveStandard,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: isDark ? 0.10 : 0.07) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : NexusMotion.fast,
            switchInCurve: NexusMotion.curveEnter,
            switchOutCurve: NexusMotion.curveExit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              icon,
              key: ValueKey(row.state),
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: reduceMotion ? Duration.zero : NexusMotion.fast,
              curve: NexusMotion.curveStandard,
              style: TextStyle(
                fontSize: AppTokens.fontSizeSubcaption,
                color: color,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningContent(
      BuildContext context, ThemeData theme, Color textMuted) {
    final isDark = theme.brightness == Brightness.dark;
    final textStyle = TextStyle(
      fontSize: AppTokens.fontSizeMeta,
      fontWeight: FontWeight.w400,
      color: textMuted,
      height: 1.5,
      fontFamily: AppTokens.fontFamilyMono,
    );
    final content = widget.streaming
        ? SelectableText(widget.reasoning, style: textStyle)
        : MathMarkdown(
            data: widget.reasoning,
            selectable: true,
            textColor: textMuted,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: textStyle,
              blockSpacing: 6,
              code: textStyle.copyWith(
                fontSize: AppTokens.fontSizeSubcaption,
                fontFamily: AppTokens.fontFamilyMono,
              ),
            ),
          );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark
                ? AppPalette.darkBrandText.withValues(alpha: 0.35)
                : AppPalette.brandAction.withValues(alpha: 0.25),
            width: 2.0,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
      child: content,
    );
  }
}

enum _ProgressRowState { done, current, pending }

class _ProgressRow {
  const _ProgressRow({required this.label, required this.state});

  final String label;
  final _ProgressRowState state;
}
