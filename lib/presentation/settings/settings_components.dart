import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// 设置模块统一色彩入口。
/// 全部委托给 AppPalette / AppSemanticColors，不再自带一套 iOS 色板。
Color settingsBgColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
}

Color settingsCardColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppPalette.darkSurface : AppPalette.lightCanvas;
}

Color settingsDividerColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
}

Color settingsMutedColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
}

Color settingsFaintColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;
}

/// 图标色归一化。
///
/// 视觉规范禁止彩色图标：历史调用点大量传入 iOS 系统色
/// (#007AFF / #34C759 / #FF9500 / #AF52DE …)，会与品牌色 #4D6BFE 打架。
/// 这里统一收敛：
///   · 语义色（成功 / 警告 / 危险）映射到语义 token，保留其含义；
///   · 其余一切彩色一律降为中性灰 textMuted。
/// 注意：这是「止血」措施，调用点里的字面量色值仍应逐步清理。
Color normalizeIconTint(BuildContext context, Color? raw) {
  final semantic = AppTheme.semanticOf(context);
  if (raw == null) return semantic.textMuted;
  const iosGreen = Color(0xFF34C759);
  const iosOrange = Color(0xFFFF9500);
  const iosOrangeBright = Color(0xFFFF9F0A);
  const iosRed = Color(0xFFFF3B30);
  const iosPinkRed = Color(0xFFFF2D55);
  if (raw == iosGreen) return semantic.success;
  if (raw == iosOrange || raw == iosOrangeBright) return semantic.warning;
  if (raw == iosRed || raw == iosPinkRed) return semantic.danger;
  if (raw == semantic.success ||
      raw == semantic.warning ||
      raw == semantic.danger ||
      raw == semantic.brand) {
    return raw;
  }
  return semantic.textMuted;
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key, this.padding});
  final String title;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: settingsMutedColor(context),
        ),
      ),
    );
  }
}

class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.children,
    this.padding,
    this.margin,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: settingsCardColor(context),
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(
            color: settingsDividerColor(context),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// 设置分组内部的分隔线。
///
/// 默认 [indent] 为 48，精确对齐 [SettingsTile] 文本起始位置：
/// 16 (左侧内边距) + 20 (图标宽度) + 12 (图标与文本间距) = 48。
/// 使用 [ExcludeSemantics] 剔除无意义的视觉装饰线条，避免干扰读屏无障碍焦点序列。
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.indent = 48, this.endIndent = 0});
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        endIndent: endIndent,
        color: settingsDividerColor(context),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    this.icon,
    this.iconColor,
    @Deprecated('图标已统一为单色描边，不再使用独立字形色') this.iconGlyphColor = Colors.white,
    this.leading,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.subtitleColor,
    this.trailingText,
    this.trailingTextColor,
    this.trailingBadge,
    this.trailingWidget,
    this.showChevron = true,
    this.selected,
    this.onTap,
    this.contentPadding,
  });

  final IconData? icon;
  final Color? iconColor;
  final Color iconGlyphColor;
  final Widget? leading;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Color? subtitleColor;
  final String? trailingText;
  final Color? trailingTextColor;
  final Widget? trailingBadge;
  final Widget? trailingWidget;
  final bool showChevron;
  final bool? selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final semantic = AppTheme.semanticOf(context);

    // 规范：单色 20px 线性图标，不再使用 iOS 风格的彩色圆角方块。
    Widget? leadingWidget = leading;
    if (leadingWidget == null && icon != null) {
      leadingWidget = Icon(
        icon,
        size: 20,
        color: normalizeIconTint(context, iconColor),
      );
    }

    final hasChevron = showChevron &&
        onTap != null &&
        trailingWidget == null &&
        (selected == null);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: contentPadding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (leadingWidget != null) ...[
                leadingWidget,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        color: titleColor ?? semantic.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: subtitleColor ?? semantic.textMuted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingWidget != null) ...[
                trailingWidget!,
              ] else ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingBadge != null) trailingBadge!,
                    if (trailingText != null && trailingText!.isNotEmpty) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          trailingText!,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.55,
                            color: trailingTextColor ?? semantic.textFaint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (selected != null)
                      if (selected == true)
                        Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: semantic.brand,
                        )
                      else
                        const SizedBox(width: 20),
                    if (hasChevron)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: semantic.textFaint,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = AppPalette.brand,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor,
          activeThumbColor: Colors.white,
        ),
      ),
    );
  }
}
