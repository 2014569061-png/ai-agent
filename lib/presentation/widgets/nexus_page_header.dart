import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
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
  });

  final String title;
  final String? subtitle;
  final Widget? statusPill;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final VoidCallback? onBack;
  final bool useGlass;

  /// 标题右侧的隐藏点按槽位。用于「连点 N 次解锁」这类不应可见的入口，
  /// 传 null 时完全不占位、不参与命中测试。
  final VoidCallback? onTitleTap;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final isGlassActive = useGlass && intensity != GlassIntensity.flat;

    Widget? glassBackground;
    if (isGlassActive) {
      glassBackground = Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? AppPalette.darkHairline
                  : AppPalette.lightHairline,
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
    }

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
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
          (canPop
              ? Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? AppPalette.darkSurfaceHover
                          : AppPalette.lightSurfaceHover,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurface,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: '返回',
                      onPressed: onBack ?? () => Navigator.maybePop(context),
                    ),
                  ),
                )
              : null),
      title: Row(
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
                    fontSize: 17,
                  ) ?? const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
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
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
