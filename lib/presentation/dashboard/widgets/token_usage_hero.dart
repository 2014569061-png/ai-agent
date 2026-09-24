import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../application/dashboard_service.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_appearance_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/section_card.dart';
import '../../chat/widgets/context_budget_bar.dart';
import 'token_numbers.dart';

/// 今日 Token 用量与座舱遥测 Hero（对标效果图 2）
///
/// 包含：渐变环形资产水位计 (Telemetry Gauge)、今日花费、活跃 Agent 实时指标与 Token 精确分项。
class TokenUsageHero extends StatelessWidget {
  const TokenUsageHero({super.key, required this.days});

  final List<UsageDaily> days;

  /// 从 7 天桶里取「今天」的用量明细；无今日数据时视为空（页面不崩）。
  UsageDaily? get _today => days.where((d) => d.isToday).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final faint = isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;

    final today = _today;
    final hasData =
        today != null && today.promptTokens + today.completionTokens > 0;

    final prompt = hasData ? today.promptTokens : 0;
    final cached = hasData ? today.cachedTokens.clamp(0, prompt).toInt() : 0;
    final completion = hasData ? today.completionTokens : 0;
    final freshInput = (prompt - cached).clamp(0, prompt).toInt();
    final total = prompt + completion;
    final calls = hasData ? today.calls : 0;
    final costYuan = formatCostYuan(hasData ? today.costCents : 0);
    // Historical daily rows cannot distinguish a cache miss from a provider
    // that omitted cache statistics. Do not render unknown data as 0%.
    final cacheRate =
        hasData && prompt > 0 && cached > 0 ? cached / prompt : null;
    final weeklyPeak = days.fold<int>(0, (peak, day) {
      final value = day.promptTokens + day.completionTokens;
      return value > peak ? value : peak;
    });
    final progress =
        weeklyPeak <= 0 ? 0.0 : (total / weeklyPeak).clamp(0.0, 1.0);
    final liveColor = isDark ? AppPalette.darkSuccess : AppPalette.lightSuccess;
    final liveSoft = isDark ? AppPalette.darkSuccessSoft : AppPalette.lightSuccessSoft;

    return SectionCard(
      glass: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：今日 Token + LIVE 遥测徽标 (对标效果图 2)
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(
                'Console & Telemetry',
                style: TextStyle(
                  fontSize: AppTokens.fontSizeBodySmall,
                  fontWeight: FontWeight.w600,
                  color: muted,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: liveSoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  border: Border.all(
                    color: liveColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: liveColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeMetricSmall,
                        fontWeight: FontWeight.bold,
                        color: liveColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 核心环形座舱资产水位仪表 (对标效果图 2)
          Center(
            child: SizedBox(
              width: 130,
              height: 130,
              child: CustomPaint(
                painter: _TelemetryGaugePainter(
                  progress: progress,
                  isDark: isDark,
                  trackColor: isDark
                      ? AppPalette.darkSurfaceHover
                      : AppPalette.lightHairline,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Token 消耗',
                        style: TextStyle(
                          fontSize: AppTokens.fontSizeMetricSmall,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        formatExact(total),
                        style: TextStyle(
                          fontSize: AppTokens.fontSizeHeading,
                          height: 1.1,
                          fontWeight: FontWeight.bold,
                          color: text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '/ 7日峰值 ${formatCompact(weeklyPeak)}',
                        style: TextStyle(
                          fontSize: AppTokens.fontSizeBadge,
                          color: faint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppPalette.darkBrandSoft
                              : AppPalette.lightBrandSoft,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          costYuan != null ? '¥$costYuan' : '¥0.00',
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeMetricSmall,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppPalette.darkText
                                : AppPalette.brandOnSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 两个实时遥测卡片网格 (对标效果图 2)
          Row(
            children: [
              Expanded(
                child: _TelemetryStatCard(
                  label: '活跃 Agent',
                  value: calls > 0 ? '$calls 任务' : '就绪',
                  icon: Icons.sensors_rounded,
                  iconColor: liveColor,
                  trailing: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: liveColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TelemetryStatCard(
                  label: '缓存命中率',
                  value: cacheRate != null ? formatPercent(cacheRate) : '--',
                  icon: Icons.bolt_rounded,
                  iconColor: isDark
                      ? AppPalette.darkBrandHover
                      : AppPalette.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 分段比例条：输入(未缓存) / 缓存 / 输出
          ContextBudgetBar(
            key: const ValueKey('dashboard-token-budget'),
            segments: [
              ContextBudgetSegment(
                tokens: freshInput,
                color: isDark
                    ? AppPalette.darkTextFaint
                    : AppPalette.lightTextMuted,
              ),
              ContextBudgetSegment(
                tokens: cached,
                color: isDark
                    ? AppPalette.darkBrandSoft
                    : AppPalette.lightBrandSoft,
              ),
              ContextBudgetSegment(
                tokens: completion,
                color: AppPalette.brand,
              ),
            ],
            limit: total,
            height: 8,
          ),
          const SizedBox(height: 10),

          // 分项精确数字（图例）
          Row(
            children: [
              _SegmentLegend(
                color: isDark
                    ? AppPalette.darkTextFaint
                    : AppPalette.lightTextMuted,
                label: AppStrings.promptTokens,
                value: formatExact(freshInput),
              ),
              const SizedBox(width: 16),
              _SegmentLegend(
                color: isDark ? AppPalette.brand : AppPalette.brand,
                label: AppStrings.outputTokens,
                value: formatExact(completion),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _SegmentLegend(
                color: isDark
                    ? AppPalette.darkBrandSoft
                    : AppPalette.lightBrandSoft,
                label: AppStrings.cachedTokens,
                value: formatExact(cached),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 底部分隔 + 调用次数 / 费用
          Divider(
              height: 1,
              thickness: 1,
              color:
                  isDark ? AppPalette.darkHairline : AppPalette.lightHairline),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.call_made_rounded, size: 14, color: muted),
              const SizedBox(width: 6),
              Text(
                '${AppStrings.callsLabel} $calls',
                style: TextStyle(fontSize: AppTokens.fontSizeCaption, color: muted),
              ),
              const Spacer(),
              if (costYuan != null)
                Text(
                  '${AppStrings.costLabel} ¥$costYuan',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeCaption,
                    fontWeight: FontWeight.w500,
                    color: text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hero 内部的次级指标使用 clear glass，避免在主玻璃面板中嵌套不透明色块。
class _TelemetryStatCard extends StatelessWidget {
  const _TelemetryStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return GlassSurface(
      role: GlassRole.control,
      variant: GlassVariant.clear,
      intensity: AppAppearanceController.resolvedGlassIntensity,
      borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeMetricSmall,
                    color: muted,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTokens.fontSizeCaption,
              fontWeight: FontWeight.w600,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}

/// 渐变能量环画笔（对标效果图 2）
class _TelemetryGaugePainter extends CustomPainter {
  _TelemetryGaugePainter({
    required this.progress,
    required this.isDark,
    required this.trackColor,
  });

  final double progress;
  final bool isDark;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 16) / 2;
    const strokeWidth = 9.0;

    // 底环轨道
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // 渐变进度圆弧
    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress.clamp(0.03, 1.0);
      final gradient = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [
          isDark ? AppPalette.darkBrandHover : AppPalette.brand,
          isDark ? AppPalette.brandAction : AppPalette.lightBrandHover,
          isDark ? AppPalette.darkBrandActive : AppPalette.lightBrandActive,
          isDark ? AppPalette.darkBrandHover : AppPalette.brand,
        ],
      );

      final progressPaint = Paint()
        ..shader = gradient
            .createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-math.pi / 2);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        0,
        sweepAngle,
        false,
        progressPaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TelemetryGaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}

/// 图例项：色点 + 标签 + 精确数字。
class _SegmentLegend extends StatelessWidget {
  const _SegmentLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Expanded(
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: AppTokens.fontSizeFootnote, color: muted),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTokens.fontSizeFootnote,
              fontWeight: FontWeight.w500,
              color: text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
