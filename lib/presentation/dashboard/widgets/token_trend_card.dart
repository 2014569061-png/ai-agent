import 'package:flutter/material.dart';

import '../../../application/dashboard_service.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_palette.dart';
import '../../widgets/section_card.dart';
import 'token_numbers.dart';

/// M2: Token 近 7 天用量趋势卡片（柱状图）。
///
/// 每根柱 = 当天 输入+输出 总量，柱顶标注精确数字（千分位），
/// 「今天」用品牌色高亮，其余用中性灰；柱底标注 MM-dd。
/// 用 CustomPaint 绘制，零额外依赖，无渐变无阴影。
class TokenTrendCard extends StatelessWidget {
  const TokenTrendCard({super.key, required this.days});

  final List<UsageDaily> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final faint = isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    final data = days.isNotEmpty
        ? days.map((d) => d.promptTokens + d.completionTokens).toList()
        : const <int>[];
    final maxValue = data.fold<int>(0, (a, b) => a > b ? a : b);
    final hasData = maxValue > 0;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(
                AppStrings.tokenTrend7Days,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (hasData) ...[
                Text(
                  '${AppStrings.trendTotal} ${formatCompact(data.fold<int>(0, (a, b) => a + b))}',
                  style: TextStyle(fontSize: 11, color: faint),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  AppStrings.noTokenData,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _TokenBarPainter(
                  values: data,
                  isDark: isDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: days.map((d) {
                return Expanded(
                  child: Text(
                    d.day,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: faint),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppPalette.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  AppStrings.todayLabel,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppPalette.darkSurfaceHover
                        : AppPalette.lightSurfaceHover,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  AppStrings.pastLabel,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Divider(height: 1, thickness: 1, color: hairline),
            const SizedBox(height: 8),
            Text(
              AppStrings.trendHint,
              style: TextStyle(fontSize: 10, color: faint),
            ),
          ],
        ],
      ),
    );
  }
}

/// 7 天柱状图绘制器：柱顶精确数字（今天品牌色，其余灰）、
/// 基线 hairline、今天柱用品牌色。
class _TokenBarPainter extends CustomPainter {
  const _TokenBarPainter({required this.values, required this.isDark});

  final List<int> values;
  final bool isDark;

  static const double _barGap = 10;
  static const double _topPad = 18; // 数字标签高度

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxValue = values.fold<int>(0, (a, b) => a > b ? a : b);
    if (maxValue <= 0) return;

    final hairlinePaint = Paint()
      ..color = isDark ? AppPalette.darkHairline : AppPalette.lightHairline
      ..strokeWidth = 1;

    // 基线
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      hairlinePaint,
    );

    final slot = size.width / values.length;
    final barWidth = slot - _barGap;
    final maxBarHeight = size.height - _topPad;
    final isToday = values.length - 1;

    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value <= 0) continue;

      final fraction = value / maxValue;
      final barHeight = (maxBarHeight * fraction).clamp(4.0, maxBarHeight);
      final left = i * slot + _barGap / 2;
      final top = size.height - barHeight;

      final today = i == isToday;
      final color = today
          ? AppPalette.brand
          : (isDark
              ? AppPalette.darkSurfaceHover
              : AppPalette.lightSurfaceHover);

      // 柱体（今天品牌色/其余中性灰，微圆角顶）
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rrect, Paint()..color = color);

      // 柱顶精确数字
      final label = formatExact(value);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: today
                ? AppPalette.brand
                : (isDark
                    ? AppPalette.darkTextMuted
                    : AppPalette.lightTextMuted),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelLeft = (left + barWidth / 2 - textPainter.width / 2)
          .clamp(0.0, size.width - textPainter.width);
      textPainter.paint(
        canvas,
        Offset(
          labelLeft,
          (top - 2 - textPainter.height)
              .clamp(2.0, size.height - textPainter.height),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_TokenBarPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.isDark != isDark;
}
