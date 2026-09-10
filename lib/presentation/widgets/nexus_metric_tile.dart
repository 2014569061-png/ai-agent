import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 统一的指标展示卡片 (NexusMetricTile)
/// 用于 Token、耗时、缓存命中率、重试次数、预计费用等指标的统一排版与可读性解释。
class NexusMetricTile extends StatelessWidget {
  const NexusMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.explanation,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final String? explanation;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  /// 快速格式化 Token 数量辅助方法 (e.g. 1.2k / 1.5M)
  static String formatTokens(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k';
    }
    return count.toString();
  }

  /// 快速格式化耗时辅助方法
  static String formatDuration(int? ms) {
    if (ms == null) return '暂无数据';
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final valueColor = color ?? textColor;

    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: hairline, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: color ?? textMuted),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (explanation != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: explanation!,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 12,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit != null && unit!.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return content;
  }
}
