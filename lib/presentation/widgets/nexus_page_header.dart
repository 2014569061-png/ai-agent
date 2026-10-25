import '../navigation/mobile_navigation_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import 'glass_surface.dart';

/// 统一的二级页面头部组件 (NexusPageHeader)
/// 统一样式：微晶磨砂圆形返回按钮、主标题、副标题/状态徽标、右侧操作区与底部指示器。
/// 在液态玻璃/磨砂模式下，自动承托全幅通透液态玻璃底衬，滚动时无缝模糊穿过的内容。
class NexusPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const NexusPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.statusPill,
    this.leading,
    this.actions,
    this.bottom,
    this.onBack,
    this.useGlass = true,
    this.onTitleTap,
    this.largeTitle = false,
  });

  final String title;
  final String? subtitle;
  final Widget? statusPill;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final VoidCallback? onBack;
  final bool useGlass;
  final bool largeTitle;

  /// 标题右侧的隐藏点按槽位。用于「连点 N 次解锁」这类不应可见的入口，
  /// 传 null 时完全不占位、不参与命中测试。
  final VoidCallback? onTitleTap;

  @override
  Size get preferredSize => Size.fromHeight(
        (largeTitle ? 72 : kToolbarHeight) +
            (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop == null) {
      final hasMenu = !canPop &&
          onBack == null &&
          MobileNavigationScope.maybeOf(context) != null;
      return AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: largeTitle ? 72 : kToolbarHeight,
        titleSpacing: canPop || onBack != null || hasMenu ? 0 : 20,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: leading ??
            (canPop || onBack != null
                ? IconButton(
                    tooltip: '返回',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    style: const ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 21))
                : hasMenu
                    ? const MobileNavigationMenuButton()
                    : null),
        title: Tooltip(
          message: subtitle == null ? title : '$title · $subtitle',
          triggerMode: TooltipTriggerMode.tap,
          child: GestureDetector(
            onTap: onTitleTap,
            child: Semantics(
                header: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: largeTitle ? 28 : 21,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface)),
                          if (subtitle != null &&
                              !largeTitle &&
                              MediaQuery.textScalerOf(context).scale(13) <= 18)
                            Text(subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (statusPill != null) ...[
                      const SizedBox(width: 8),
                      statusPill!,
                    ],
                  ],
                )),
          ),
        ),
        actions: actions,
        bottom: bottom,
      );
    }
    return _legacyHeader(context);
  }

  Widget _legacyHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final desktop = DesktopTheme.maybeOf(context);
    final isGlassActive =
        desktop == null && useGlass && intensity != GlassIntensity.flat;

    Widget? glassBackground;
    if (desktop != null) {
      glassBackground = Container(
        decoration: BoxDecoration(
          color: desktop.panel,
          border: Border(
            bottom: BorderSide(
              color: desktop.border,
              width: 1.0,
            ),
          ),
        ),
      );
    } else if (isGlassActive) {
      glassBackground = Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
              width: 1.0,
            ),
          ),
        ),
        child: GlassSurface(
          role: GlassRole.navigation,
          variant: GlassVariant.regular,
          intensity: intensity,
          borderRadius: BorderRadius.zero,
          outlined: false,
          blurSigma: 24,
          refraction: 16,
          gloss: 0.40,
          tint: isDark
              ? AppPalette.darkSurface.withValues(alpha: 0.38)
              : AppPalette.lightCanvas.withValues(alpha: 0.42),
          boxShadow: const [],
          child: const SizedBox.expand(),
        ),
      );
    } else {
      glassBackground = Container(
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
          border: Border(
            bottom: BorderSide(
              color:
                  isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
              width: 1.0,
            ),
          ),
        ),
      );
    }

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: desktop?.panel ?? Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      flexibleSpace: glassBackground,
      leading: leading ??
          (canPop || onBack != null
              ? Center(
                  child: IconButton(
                    constraints: BoxConstraints.tightFor(
                      width: desktop != null ? 36 : 48,
                      height: desktop != null ? 36 : 48,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: '返回',
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                    icon: Container(
                      width: desktop != null ? 36 : 48,
                      height: desktop != null ? 36 : 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
                        color: desktop != null
                            ? desktop.hover
                            : (isDark
                                ? AppPalette.darkSurface
                                : AppPalette.lightSurface),
                        border: Border.all(
                          color: desktop != null
                              ? desktop.border
                              : (isDark
                                  ? AppPalette.darkHairline
                                  : AppPalette.lightHairline),
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 15,
                        color: desktop?.text ?? theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                )
              : null),
      title: Semantics(
          header: true,
          child: Tooltip(
              message: subtitle == null ? title : '$title · $subtitle',
              triggerMode: TooltipTriggerMode.tap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                fontSize: desktop != null
                                    ? AppTokens.fontSizeHeading
                                    : AppTokens.fontSizeTitle,
                              ) ??
                              const TextStyle(
                                  fontSize: AppTokens.fontSizeTitle,
                                  fontWeight: FontWeight.w600),
                        ),
                        if (subtitle != null &&
                            MediaQuery.textScalerOf(context).scale(13) <=
                                18) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: desktop != null
                                  ? AppTokens.fontSizeFootnote
                                  : AppTokens.fontSizeCaption,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 无可见入口的隐藏手势槽位（例如连点标题解锁实验开关）。
                  if (onTitleTap != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTitleTap,
                      child: const SizedBox(width: 32, height: 24),
                    ),
                  ],
                  if (statusPill != null) ...[
                    const SizedBox(width: 8),
                    statusPill!,
                  ],
                ],
              ))),
      actions: actions,
      bottom: bottom,
    );
  }
}
