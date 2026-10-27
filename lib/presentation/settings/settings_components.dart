import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_theme.dart';
import '../widgets/section_card.dart';
import '../motion/press_squash.dart';
import '../widgets/nexus_switch.dart';
import '../theme/mobile_theme.dart';

/// 设置模块统一色彩入口。
/// 全部委托给 AppPalette / AppSemanticColors，不再自带一套 iOS 色板。
Color settingsBgColor(BuildContext context) {
  final desktop = DesktopTheme.maybeOf(context);
  if (desktop != null) return desktop.canvas;
  return Colors.transparent;
}

Color settingsCardColor(BuildContext context) {
  final desktop = DesktopTheme.maybeOf(context);
  if (desktop != null) return desktop.panel;
  return Theme.of(context).colorScheme.surface;
}

Color settingsDividerColor(BuildContext context) {
  final desktop = DesktopTheme.maybeOf(context);
  if (desktop != null) return desktop.border;
  return Theme.of(context).colorScheme.outlineVariant;
}

Color settingsMutedColor(BuildContext context) {
  final desktop = DesktopTheme.maybeOf(context);
  if (desktop != null) return desktop.muted;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

Color settingsFaintColor(BuildContext context) {
  final desktop = DesktopTheme.maybeOf(context);
  if (desktop != null) return desktop.muted;
  return Theme.of(context).colorScheme.onSurfaceVariant;
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
  if (raw == null) {
    return DesktopTheme.maybeOf(context)?.muted ?? semantic.textMuted;
  }
  if (DesktopTheme.maybeOf(context) == null &&
      (raw == AppPalette.brand || raw == AppPalette.darkBrandText)) {
    return Theme.of(context).colorScheme.primary;
  }
  const iosGreen = Color(0xFF34C759);
  const iosOrange = Color(0xFFFF9500);
  const iosOrangeBright = Color(0xFFFF9F0A);
  const iosRed = Color(0xFFFF3B30);
  const iosPinkRed = Color(0xFFFF2D55);
  if (raw == iosGreen) return semantic.success;
  if (raw == iosOrange || raw == iosOrangeBright) return semantic.warning;
  if (raw == iosRed || raw == iosPinkRed) return semantic.danger;
  // X1：调用点常直接传 AppPalette.success/warning/danger（= 浅色值），深色下
  // 它们不等于当前主题 token 而被降为灰色；两套语义色都映射到当前主题。
  if (raw == AppPalette.lightSuccess || raw == AppPalette.darkSuccess) {
    return semantic.success;
  }
  if (raw == AppPalette.lightWarning || raw == AppPalette.darkWarning) {
    return semantic.warning;
  }
  if (raw == AppPalette.lightDanger || raw == AppPalette.darkDanger) {
    return semantic.danger;
  }
  if (raw == semantic.success ||
      raw == semantic.warning ||
      raw == semantic.danger ||
      raw == semantic.brand) {
    return raw;
  }
  return DesktopTheme.maybeOf(context)?.muted ?? semantic.textMuted;
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key, this.padding});
  final String title;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) == null) {
      return Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Semantics(
            header: true,
            child: Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
      );
    }
    final dividerColor = settingsDividerColor(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: AppPalette.brand,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.35,
                  color: settingsMutedColor(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Divider(
                height: 1,
                thickness: 0.8,
                color: dividerColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Legacy radius retained for desktop callers; phone groups use SectionCard.
const kSettingsCardRadius = AppTokens.radiusCard;

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
    // 桌面与手机都交给 SectionCard：桌面分支此前把同一套 panel 底色、
    // panelRadius 圆角与 border 描边又抄了一遍，两处一旦改动就会分叉。
    return SectionCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 20),
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 设置分组内部的分隔线。
///
/// Phone defaults align with SettingsTile text: 16dp padding + 40dp icon +
/// 12dp gap. Explicit overrides and the desktop's 48dp inset are preserved.
/// 使用 [ExcludeSemantics] 剔除无意义的视觉装饰线条，避免干扰读屏无障碍焦点序列。
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.indent, this.endIndent});
  final double? indent;
  final double? endIndent;

  @override
  Widget build(BuildContext context) {
    final mobile = DesktopTheme.maybeOf(context) == null;
    return ExcludeSemantics(
      child: Divider(
        height: 1,
        thickness: mobile ? .7 : 1,
        indent: indent ?? (mobile ? 68 : 48),
        endIndent: endIndent ?? (mobile ? 16 : 0),
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
    this.subtitleMaxLines = 2,
    this.wrapText = false,
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

  /// 副标题最多行数；默认 2，承载多段状态信息的行可放宽。
  final int subtitleMaxLines;

  /// Critical permission descriptions can grow instead of being truncated.
  final bool wrapText;

  @override
  Widget build(BuildContext context) {
    final semantic = AppTheme.semanticOf(context);

    // 规范：单色 20px 线性图标，不再使用 iOS 风格的彩色圆角方块。
    Widget? leadingWidget = leading;
    if (leadingWidget == null && icon != null) {
      final resolvedTint = normalizeIconTint(context, iconColor);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (DesktopTheme.maybeOf(context) != null) {
        leadingWidget = Icon(
          icon,
          size: 18,
          color: resolvedTint,
        );
      } else {
        leadingWidget = Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: resolvedTint.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(MobileTheme.insetRadius),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: resolvedTint,
          ),
        );
      }
    }

    final hasChevron = showChevron &&
        onTap != null &&
        trailingWidget == null &&
        (selected == null);

    return PressSquash(
      enabled: onTap != null && DesktopTheme.maybeOf(context) == null,
      scale: NexusPressScale.row,
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          button: onTap != null,
          enabled: onTap != null,
          container: true,
          label: title,
          value: trailingText,
          hint: onTap == null ? null : '打开$title',
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(
                  minHeight: DesktopTheme.maybeOf(context) == null ? 58 : 44),
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
                            fontSize: DesktopTheme.maybeOf(context) == null
                                ? 16
                                : AppTokens.fontSizeBody,
                            fontWeight: DesktopTheme.maybeOf(context) == null
                                ? FontWeight.w500
                                : FontWeight.w400,
                            height: 1.4,
                            color: titleColor ??
                                DesktopTheme.maybeOf(context)?.text ??
                                semantic.textPrimary,
                          ),
                          maxLines: wrapText
                              ? null
                              : (MediaQuery.textScalerOf(context).scale(15) > 19
                                  ? 2
                                  : 1),
                          overflow: wrapText
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeCaption,
                              height: 1.55,
                              color: subtitleColor ??
                                  DesktopTheme.maybeOf(context)?.muted ??
                                  semantic.textMuted,
                            ),
                            maxLines: wrapText ? null : subtitleMaxLines,
                            overflow: wrapText
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
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
                        if (trailingText != null &&
                            trailingText!.isNotEmpty) ...[
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth:
                                    (MediaQuery.sizeOf(context).width * .28)
                                        .clamp(72.0, 180.0)),
                            child: Text(
                              trailingText!,
                              style: TextStyle(
                                fontSize: AppTokens.fontSizeCaption,
                                height: 1.55,
                                color: trailingTextColor ??
                                    DesktopTheme.maybeOf(context)?.muted ??
                                    semantic.textFaint,
                              ),
                              maxLines:
                                  MediaQuery.textScalerOf(context).scale(13) >
                                          18
                                      ? 2
                                      : 1,
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
    final control = NexusSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: activeColor,
        activeThumbColor: Colors.white);
    if (DesktopTheme.maybeOf(context) == null) return control;
    return SizedBox(
        height: 28, child: FittedBox(fit: BoxFit.contain, child: control));
  }
}
