import 'package:flutter/material.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_status_colors.dart';
import '../theme/desktop_theme.dart';
import 'section_card.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';
import '../motion/press_squash.dart';
import '../motion/micro_interactions.dart';

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
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final tone = switch (color) {
      AppPalette.success => AppStatusTone.success,
      AppPalette.warning => AppStatusTone.warning,
      AppPalette.danger => AppStatusTone.danger,
      _ => null,
    };
    final valueColor = tone == null
        ? (color ?? textColor)
        : AppStatusColors.resolve(context, tone).foreground;
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final isGlass = intensity != GlassIntensity.flat;
    final cardRadius = BorderRadius.circular(AppTokens.radiusCard);

    final cardBody = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13, color: color == null ? textMuted : valueColor),
                const SizedBox(width: 4),
              ],
              Flexible(
                  child: Text(
                label,
                style: TextStyle(
                  color: textMuted,
                  fontSize: AppTokens.fontSizeBadge,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.25,
                ),
              )),
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
          if (DesktopTheme.maybeOf(context) == null)
            Wrap(
              spacing: 3,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                RollingText(
                  value,
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBodyLarge,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit != null && unit!.isNotEmpty) ...[
                  Text(
                    unit!,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                RollingText(
                  value,
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBodyLarge,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit != null && unit!.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit!,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    if (DesktopTheme.maybeOf(context) == null) {
      return SectionCard(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: cardBody,
        ),
      );
    }
    if (isGlass) {
      return GlassSurface(
        role: GlassRole.content,
        // KPI tiles are short data surfaces; clear glass keeps the ambient
        // canvas visible instead of turning every tile into a white card.
        variant: GlassVariant.clear,
        intensity: intensity,
        borderRadius: cardRadius,
        onTap: onTap,
        interactive: onTap != null,
        child: cardBody,
      );
    }

    return PressSquash(
      enabled: onTap != null,
      scale: NexusPressScale.card,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: cardRadius,
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: cardRadius,
              border: Border.all(color: hairline, width: 1.0),
            ),
            child: cardBody,
          ),
        ),
      ),
    );
  }
}

/// Intrinsic-height metrics: no fixed aspect ratio that clips enlarged text.
class NexusMetricGrid extends StatelessWidget {
  const NexusMetricGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final minTileWidth =
            constraints.maxWidth >= 320 && scale <= 1.35 ? 140.0 : 160.0;
        final columns = ((constraints.maxWidth + 10) /
                (minTileWidth * scale.clamp(1, 2) + 10))
            .floor()
            .clamp(1, 4);
        final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final child in children) SizedBox(width: width, child: child),
        ]);
      });
}
