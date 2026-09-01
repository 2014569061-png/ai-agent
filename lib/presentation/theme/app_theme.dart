import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const brand = Color(0xFF0A59F7);
  static const brandBright = Color(0xFF1677FF);
  static const background = Color(0xFFF3F5F9);
  static const darkBackground = Color(0xFF0D0F14);
  static const textPrimary = Color(0xFF1B2233);
  static const textSecondary = Color(0xFF627D98);

  /// 字体回退链：Noto Sans SC 是 web/index.html 里通过 Google Fonts 注入的
  /// CJK 字体；CanvasKit 会自动接管并在中文 glyph 缺失时回退。
  /// 末尾加系统字体做兜底，原生平台也能找到合适的中文字形。
  static const List<String> _cjkFallback = <String>[
    'Noto Sans SC',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Source Han Sans SC',
    'WenQuanYi Micro Hei',
    'sans-serif',
  ];

  static TextTheme _baseTextTheme(TextTheme base) => base.copyWith(
        bodyLarge: base.bodyLarge?.copyWith(fontFamilyFallback: _cjkFallback),
        bodyMedium: base.bodyMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        bodySmall: base.bodySmall?.copyWith(fontFamilyFallback: _cjkFallback),
        titleLarge: base.titleLarge?.copyWith(fontFamilyFallback: _cjkFallback),
        titleMedium: base.titleMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        titleSmall: base.titleSmall?.copyWith(fontFamilyFallback: _cjkFallback),
        labelLarge: base.labelLarge?.copyWith(fontFamilyFallback: _cjkFallback, height: 1.3),
        labelMedium: base.labelMedium?.copyWith(fontFamilyFallback: _cjkFallback, height: 1.3),
        labelSmall: base.labelSmall?.copyWith(fontFamilyFallback: _cjkFallback, height: 1.3),
        headlineLarge: base.headlineLarge?.copyWith(fontFamilyFallback: _cjkFallback),
        headlineMedium: base.headlineMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        headlineSmall: base.headlineSmall?.copyWith(fontFamilyFallback: _cjkFallback),
        displayLarge: base.displayLarge?.copyWith(fontFamilyFallback: _cjkFallback),
        displayMedium: base.displayMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        displaySmall: base.displaySmall?.copyWith(fontFamilyFallback: _cjkFallback),
      );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light).copyWith(
      primary: brand,
      secondary: brandBright,
      surface: Colors.white,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      fontFamilyFallback: _cjkFallback,
      textTheme: _baseTextTheme(ThemeData.light().textTheme),
      appBarTheme: const AppBarTheme(backgroundColor: background, foregroundColor: textPrimary, elevation: 0, centerTitle: false),
      cardTheme: CardThemeData(color: Colors.white.withValues(alpha: .82), elevation: 2, shadowColor: const Color(0x12172642), shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white.withValues(alpha: .82), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFD9E7F7))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: brand, width: 1.5))),
      // Chip 高度紧凑，labelStyle 需要明确 height 避免中文被截。
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEAF2FF),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(color: Color(0xFF174A7E), height: 1.35),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF174A7E), height: 1.35),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: brandBright, brightness: Brightness.dark).copyWith(primary: const Color(0xFF4C8DFF), secondary: const Color(0xFF73AAFF));
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      fontFamilyFallback: _cjkFallback,
      textTheme: _baseTextTheme(ThemeData.dark().textTheme),
      appBarTheme: const AppBarTheme(backgroundColor: darkBackground, foregroundColor: Color(0xFFEDF1F8), elevation: 0),
      cardTheme: CardThemeData(color: const Color(0xFF1E232F).withValues(alpha: .82), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF1E232F), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF4C8DFF), width: 1.5))),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1E232F),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(color: Color(0xFFEDF1F8), height: 1.35),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFEDF1F8), height: 1.35),
      ),
    );
  }
}