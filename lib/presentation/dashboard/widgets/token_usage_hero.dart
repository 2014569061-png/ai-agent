import '../../theme/mobile_theme.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/providers.dart' show databaseProvider;

import '../../../application/cost_budget_service.dart';
import '../../../application/dashboard_service.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/section_card.dart';
import '../../widgets/nexus_sheet.dart';
import '../../chat/widgets/context_budget_bar.dart';
import 'token_numbers.dart';
import '../cost_ledger_page.dart';

/// 今日 Token 用量与座舱遥测 Hero（对标效果图 2）
///
/// 包含：渐变环形资产水位计 (Telemetry Gauge)、今日花费、活跃 Agent 实时指标与 Token 精确分项。
class TokenUsageHero extends StatelessWidget {
  const TokenUsageHero(
      {super.key, required this.days, this.costBudget, this.onBudgetChanged});

  final List<UsageDaily> days;
  final CostBudgetEvaluation? costBudget;
  final VoidCallback? onBudgetChanged;

  Future<void> _configureBudget(BuildContext context) async {
    final policy = await const CostBudgetService().loadPolicy();
    if (!context.mounted) return;
    final daily = TextEditingController(
        text: (policy.dailyLimitCents / 100).toStringAsFixed(2));
    final monthly = TextEditingController(
        text: (policy.monthlyLimitCents / 100).toStringAsFixed(2));
    var hardStop = policy.hardStopEnabled;
    String? error;
    try {
      await showNexusDialog<void>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                    title: const Text('费用预算（人民币）'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: daily,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '每日上限（元）')),
                      TextField(
                          controller: monthly,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '每月上限（元）')),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('达到预算时停止请求'),
                          value: hardStop,
                          onChanged: (value) => update(() => hardStop = value)),
                      const Text(
                          '按服务商设置中填写的每百万 Token 单价估算，不是服务商账单。预算占用包含已结算估算与待核对预留；失败、取消或缺少用量的已发送请求不会自动释放预留。开启硬停后，缺少单价或无法可靠估价的请求会停止发送。'),
                      if (error != null)
                        Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () async {
                            try {
                              int cents(String text) {
                                final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
                                    .firstMatch(text.trim());
                                if (match == null) {
                                  throw const FormatException('请输入最多两位小数的金额');
                                }
                                return int.parse(match[1]!) * 100 +
                                    int.parse(
                                        (match[2] ?? '').padRight(2, '0'));
                              }

                              await const CostBudgetService().savePolicy(
                                  dailyLimitCents: cents(daily.text),
                                  monthlyLimitCents: cents(monthly.text),
                                  hardStopEnabled: hardStop);
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              onBudgetChanged?.call();
                            } catch (failure) {
                              if (dialogContext.mounted) {
                                update(() => error = failure is FormatException
                                    ? failure.message
                                    : '预算保存失败，请重试');
                              }
                            }
                          },
                          child: const Text('保存')),
                    ],
                  )));
    } finally {
      daily.dispose();
      monthly.dispose();
    }
  }

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
    final costBudgetEval = costBudget;
    // Budget decisions and the displayed settled estimate use the same ledger.
    // Historical run_records are a fallback only, never added a second time.
    final todayCostCents =
        costBudgetEval?.dailySettledCents ?? (hasData ? today.costCents : 0);
    final costYuan = costBudgetEval != null
        ? (costBudgetEval.unpricedPendingRequests > 0
            ? null
            : (todayCostCents / 100).toStringAsFixed(2))
        : (today?.costKnown == false ? null : formatCostYuan(todayCostCents));
    // U5：缓存命中率已在 KPI 网格展示（同一口径），这里改为每次调用平均
    // Token，避免同屏重复；无调用时显示占位而不是 0。
    final avgPerCall = calls > 0 ? (total / calls).round() : null;
    final weeklyPeak = days.fold<int>(0, (peak, day) {
      final value = day.promptTokens + day.completionTokens;
      return value > peak ? value : peak;
    });
    final progress =
        weeklyPeak <= 0 ? 0.0 : (total / weeklyPeak).clamp(0.0, 1.0);
    final liveColor = isDark ? AppPalette.darkSuccess : AppPalette.lightSuccess;
    final liveSoft =
        isDark ? AppPalette.darkSuccessSoft : AppPalette.lightSuccessSoft;

    return SectionCard(
      glass: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：今日 Token + 实时徽标（U2：与全中文界面一致，徽标去描边只留浅底）
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(
                '实时用量',
                style: TextStyle(
                  fontSize: AppTokens.fontSizeBodySmall,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: liveSoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
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
                      '实时',
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeMetricSmall,
                        fontWeight: FontWeight.w600,
                        color: liveColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 核心环形座舱资产水位仪表 (对标效果图 2)
          //
          // 环内四行文字随系统字号放大，而系统放大倍数会被应用内「字体大小」
          // 偏好再乘一次（`app_presentation_preferences.dart`），所以环直径必须
          // 跟着放大：固定 130dp 在「窄屏 + 大字号」下会让内容高出环体，实测
          // 出现 `BOTTOM OVERFLOWED BY 51 PIXELS` 并让 `¥` 胶囊压住峰值文字
          // （2026-10-17 模拟器复核，证据
          // local/temp/mobile-acceptance-2026-10-17/section3-5/screenshots/zoom-ring-font20.png）。
          // 上限与可用宽度取小，避免放大后横向溢出父卡片。
          LayoutBuilder(
            builder: (context, constraints) {
              const double base = 130;
              final double scale =
                  MediaQuery.textScalerOf(context).scale(14) / 14;
              final double size = math.min(
                constraints.maxWidth,
                (base * scale).clamp(base, base * 2.2),
              );
              return Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _TelemetryGaugePainter(
                      brand: MobileTheme.brand(context),
                      progress: progress,
                      isDark: isDark,
                      trackColor: isDark
                          ? AppPalette.darkSurfaceHover
                          : AppPalette.lightHairline,
                    ),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(size * 0.08),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Token 消耗',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeMetricSmall,
                                fontWeight: FontWeight.w500,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              formatExact(total),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeHeading,
                                height: 1.1,
                                fontWeight: FontWeight.bold,
                                color: text,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '/ 7日峰值 ${formatCompact(weeklyPeak)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeBadge,
                                color: faint,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
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
                                costYuan != null ? '¥$costYuan' : '费用未知',
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
              );
            },
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
                  label: '每次调用平均',
                  value: avgPerCall != null ? formatExact(avgPerCall) : '--',
                  icon: Icons.equalizer_rounded,
                  iconColor: isDark
                      ? AppPalette.darkBrandHover
                      : MobileTheme.brand(context),
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
                color: MobileTheme.brand(context),
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
                color: isDark
                    ? MobileTheme.brand(context)
                    : MobileTheme.brand(context),
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
                style: TextStyle(
                    fontSize: AppTokens.fontSizeCaption, color: muted),
              ),
              const Spacer(),
              if (costYuan != null)
                Text(
                  '结算估算 ¥$costYuan',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeCaption,
                    fontWeight: FontWeight.w500,
                    color: text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                (costBudgetEval?.allowed ?? true)
                    ? Icons.shield_outlined
                    : Icons.gpp_maybe_outlined,
                size: 13,
                color: muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  costBudgetEval == null
                      ? '费用预算状态尚未加载'
                      : '${costBudgetEval.hardStopEnabled ? "费用硬停" : "费用预警"}：今日 ¥${(costBudgetEval.dailySpentCents / 100).toStringAsFixed(2)} / ¥${(costBudgetEval.dailyLimitCents / 100).toStringAsFixed(2)} · 本月 ¥${(costBudgetEval.monthlySpentCents / 100).toStringAsFixed(2)} / ¥${(costBudgetEval.monthlyLimitCents / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    color: muted,
                  ),
                ),
              ),
              IconButton(
                  key: const ValueKey('dashboard-cost-budget-settings'),
                  tooltip: '费用预算设置（占用含待核对预留）',
                  onPressed: () => _configureBudget(context),
                  icon: const Icon(Icons.tune_rounded, size: 18)),
            ],
          ),
          TextButton.icon(
            key: const ValueKey('dashboard-cost-ledger'),
            onPressed: () async {
              final database = ProviderScope.containerOf(context, listen: false)
                  .read(databaseProvider.future);
              await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => CostLedgerPage(database: () => database)));
              onBudgetChanged?.call();
            },
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('逐请求费用明细与对账'),
          ),
          if (costBudgetEval != null)
            Text(
              '今日已结算估算 ¥${(costBudgetEval.dailySettledCents / 100).toStringAsFixed(2)}；待核对预留 ¥${(costBudgetEval.dailyReservedCents / 100).toStringAsFixed(2)}。本月待核对预留 ¥${(costBudgetEval.monthlyReservedCents / 100).toStringAsFixed(2)}。未定价待确认 ${costBudgetEval.unpricedPendingRequests} 笔。以上不是服务商账单。',
              style:
                  TextStyle(fontSize: AppTokens.fontSizeFootnote, color: muted),
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

    // U3：原先嵌套 clear 玻璃——浅色下完全透明、深色下只有描边，两套样式；
    // 且玻璃里再套玻璃违背「材质不嵌套」。改为文字色低透明度浅底、无描边。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: text.withValues(alpha: isDark ? 0.06 : 0.045),
        borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
      ),
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
    required this.brand,
  });

  final double progress;
  final bool isDark;
  final Color trackColor;
  final Color brand;

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
          isDark ? AppPalette.darkBrandHover : brand,
          isDark ? brand : AppPalette.lightBrandHover,
          isDark ? AppPalette.darkBrandActive : AppPalette.lightBrandActive,
          isDark ? AppPalette.darkBrandHover : brand,
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
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.brand != brand;
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
          // 大字号下标签会挤爆这一行（实测 2.3× 时横向溢出 57px），标签可收缩
          // 省略、数值单行不换行。
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: AppTokens.fontSizeFootnote, color: muted),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote,
                fontWeight: FontWeight.w500,
                color: text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
