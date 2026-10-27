import 'package:flutter/material.dart';
import 'desktop_theme.dart';
import 'app_theme.dart';
import 'app_palette.dart';

/// Phone-only styling. Desktop keeps its own theme and layout.
abstract final class MobileTheme {
  static const blue = Color(0xFF0A59F7);
  static const ink = Color(0xFF182230);
  static const muted = Color(0xFF667085);
  static const paleBlue = Color(0xFFEAF2FF);
  static const hairline = Color(0xFFE8EFF8);
  static const canvas = Color(0xFFF7F9FC);
  static const pageInset = 20.0;
  static const contentRadius = 24.0;
  static const fieldRadius = 18.0;
  static const sheetRadius = 28.0;

  /// 内嵌小块（提示条、聊天气泡、状态块、预览块）的统一圆角。
  /// 数值与 [controlRadius] 的手机档一致，但语义独立：调整控件圆角
  /// 不应连带改变这些块，反之亦然。此前页面里这些块写过 12/14/15/16/18/20
  /// 六种字面量，统一收敛到这里。
  static const insetRadius = 16.0;

  /// Compatibility for pages which still set an explicit brand foreground.
  static Color brand(BuildContext context) =>
      DesktopTheme.maybeOf(context) != null
          ? AppPalette.brand
          : Theme.of(context).colorScheme.primary;

  static double controlRadius(BuildContext context) =>
      DesktopTheme.maybeOf(context) == null ? 16 : 8;
  static double cardRadius(BuildContext context) =>
      DesktopTheme.maybeOf(context) == null ? 24 : 12;
  static double modalRadius(BuildContext context) =>
      DesktopTheme.maybeOf(context) == null ? 28 : 16;
  static Color pageBackground(BuildContext context) =>
      DesktopTheme.maybeOf(context)?.canvas ?? Colors.transparent;
  static Color surface(BuildContext context) =>
      DesktopTheme.maybeOf(context)?.panel ??
      Theme.of(context).colorScheme.surface;

  static ThemeData apply(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF91B8FF) : blue;
    final text = dark ? const Color(0xFFECF1F8) : ink;
    final secondary = dark ? const Color(0xFFA7B2C2) : muted;
    final surface = dark ? const Color(0xFF1A2230) : Colors.white;
    final line = dark ? const Color(0xFF303A4A) : hairline;
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: dark ? const Color(0xFF10254C) : Colors.white,
      secondary: accent,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      primaryContainer: dark ? const Color(0xFF1F3557) : paleBlue,
      onPrimaryContainer: accent,
      outlineVariant: line,
    );
    final typography = base.textTheme.apply(
      fontFamily: 'sans-serif',
      bodyColor: text,
      displayColor: text,
    );
    return base.copyWith(
      extensions: [
        ...base.extensions.values.where((value) => value is! AppSemanticTheme),
        AppSemanticTheme(AppSemanticColors(
          canvas: dark ? const Color(0xFF111722) : canvas,
          surface: surface,
          surfaceHover:
              dark ? const Color(0xFF202B3D) : const Color(0xFFF0F4FA),
          hairline: line,
          textPrimary: text,
          textMuted: secondary,
          textFaint: secondary,
          brand: accent,
          brandHover: accent,
          brandActive: accent,
          brandSoft: scheme.primaryContainer,
          brandFaint: scheme.primaryContainer.withValues(alpha: .5),
          danger:
              (dark ? AppTheme.darkSemantic : AppTheme.lightSemantic).danger,
          warning:
              (dark ? AppTheme.darkSemantic : AppTheme.lightSemantic).warning,
          success:
              (dark ? AppTheme.darkSemantic : AppTheme.lightSemantic).success,
          floatingSurface: surface,
          elevatedSurface: surface,
          modalSurface: surface,
          border: line,
          chatUser: scheme.primaryContainer,
          chatAssistant: surface,
          onGlass: text,
          mutedOnGlass: secondary,
          surfaceTint: Colors.transparent,
          brandAccent: accent,
          focusGlow: Colors.transparent,
          glowBright: Colors.transparent,
          userBubbleStart: scheme.primaryContainer,
          userBubbleEnd: scheme.primaryContainer,
          userBubbleGlow: Colors.transparent,
        )),
      ],
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: typography.copyWith(
        displayMedium: typography.displayMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          height: 1.4,
          letterSpacing: 0,
        ),
        titleLarge: typography.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: typography.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
        bodyMedium: typography.bodyMedium?.copyWith(fontSize: 15, height: 1.55),
      ),
      dividerColor: line,
      dividerTheme: DividerThemeData(color: line, thickness: .7, space: 1),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: dark ? const Color(0xFF202B3D) : const Color(0xFFF0F4FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: accent, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: surface.withValues(alpha: .92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: dark ? const Color(0xFF223B62) : paleBlue,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? accent : secondary,
              size: 25,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: 'sans-serif',
              fontSize: 12,
              height: 1.4,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w500
                  : FontWeight.w400,
              color: states.contains(WidgetState.selected) ? accent : secondary,
            )),
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: accent,
        unselectedLabelColor: secondary,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: dark ? const Color(0xFF223B62) : paleBlue,
          borderRadius: BorderRadius.circular(24),
        ),
        indicatorColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 15),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: text,
        iconColor: accent,
        minVerticalPadding: 14,
        titleTextStyle: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: text),
        subtitleTextStyle: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 14,
            height: 1.55,
            color: secondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled) ? line : accent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? secondary
                  : scheme.onPrimary),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontFamily: 'sans-serif',
              fontSize: 15,
              fontWeight: FontWeight.w500)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          side: WidgetStatePropertyAll(BorderSide(color: line)),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled) ? secondary : accent),
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontFamily: 'sans-serif',
              fontSize: 15,
              fontWeight: FontWeight.w500)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: base.elevatedButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontFamily: 'sans-serif',
              fontSize: 15,
              fontWeight: FontWeight.w500)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled) ? secondary : accent),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontFamily: 'sans-serif',
              fontSize: 15,
              fontWeight: FontWeight.w500)),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: text,
            height: 1.4),
        contentTextStyle: TextStyle(
            fontFamily: 'sans-serif', fontSize: 15, color: text, height: 1.6),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 2,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor:
            dark ? const Color(0xFF202B3D) : const Color(0xFFF0F4FA),
        selectedColor: scheme.primaryContainer,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle:
            TextStyle(fontFamily: 'sans-serif', fontSize: 14, color: text),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        focusElevation: 1,
        hoverElevation: 1,
        shape: const StadiumBorder(),
      ),
      expansionTileTheme: base.expansionTileTheme.copyWith(
        shape: const Border(),
        collapsedShape: const Border(),
        textColor: text,
        collapsedTextColor: text,
        iconColor: secondary,
        collapsedIconColor: secondary,
      ),
    );
  }
}

/// A quiet blue-white canvas shared by phone pages, including opaque routes.
class MobileCanvas extends StatelessWidget {
  const MobileCanvas({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF111722) : MobileTheme.canvas,
      child: child,
    );
  }
}
