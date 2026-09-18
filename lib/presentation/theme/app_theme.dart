import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_appearance_controller.dart';
import 'app_palette.dart';
import 'app_tokens.dart';
import '../widgets/liquid_glass.dart';

abstract final class AppTheme {
  // 品牌色与主要视觉色
  static const brand = AppPalette.brand;
  static const brandBright = AppPalette.brand;
  static const background = AppPalette.lightCanvas;
  static const darkBackground = AppPalette.darkCanvas;
  static const textPrimary = AppPalette.lightText;
  static const textSecondary = AppPalette.lightTextMuted;
  static const danger = AppPalette.lightDanger;
  static const warning = AppPalette.lightWarning;
  static const success = AppPalette.lightSuccess;
  static const darkDanger = AppPalette.darkDanger;
  static const darkWarning = AppPalette.darkWarning;
  static const darkSuccess = AppPalette.darkSuccess;

  // 基础圆角常量
  static const radiusSmall = AppTokens.radiusControl;
  static const radiusCapsule = AppTokens.radiusPill;
  static const radiusCard = AppTokens.radiusCard;
  static const radiusModal = AppTokens.radiusModal;

  // 表面色与边框色
  static const lightFloating = AppPalette.lightSurface;
  static const darkFloating = AppPalette.darkSurface;
  static const lightElevated = AppPalette.lightSurface;
  static const darkElevated = AppPalette.darkSurface;
  static const lightBorder = AppPalette.lightHairline;
  static const darkBorder = AppPalette.darkHairline;

  // 废弃字段兼容别名
  @Deprecated('视觉规范已改为单强调色')
  static const brandGradientStart = AppPalette.brand;
  @Deprecated('视觉规范已改为单强调色')
  static const brandGradientEnd = AppPalette.brand;
  @Deprecated('请改用 AppPalette.lightTextMuted')
  static const mutedOnGlassLight = AppPalette.lightTextMuted;
  @Deprecated('请改用 AppPalette.darkTextMuted')
  static const mutedOnGlassDark = AppPalette.darkTextMuted;
  @Deprecated('视觉规范已移除彩色光晕')
  static const lightGlow = Colors.transparent;
  @Deprecated('视觉规范已移除彩色光晕')
  static const darkGlow = Colors.transparent;

  // 阴影收敛为 2 级（卡片 1px，浮层 8px）
  static const cardShadow = [
    BoxShadow(
      color: Color.fromRGBO(16, 24, 40, 0.04),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static List<BoxShadow> floatingShadow([bool isDark = false]) => const [
        BoxShadow(
          color: Color.fromRGBO(16, 24, 40, 0.08),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];

  // 语义色集合
  static const lightSemantic = AppSemanticColors.light;
  static const darkSemantic = AppSemanticColors.dark;

  static AppSemanticColors semanticOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSemantic
          : lightSemantic;

  // 字体族串联：Latin 用随包分发的 Inter（400/500 已在 pubspec 声明），中文走
  // PingFang SC, Microsoft YaHei, Noto Sans SC。勿只声明不打包 —— 那会让字重合成
  // 中文使用系统字体栈，避免依赖额外字体资源。
  static List<String> get _fontFallback => const [
        'Inter',
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans SC',
        'sans-serif',
      ];

  // 字体采用双轨制（Display 轨 28-34 + Body 轨 11-17）
  static TextTheme _baseTextTheme(
    TextTheme base, {
    required Color primary,
    required Color muted,
    required Color faint,
  }) =>
      base.copyWith(
        // 显示轨（Display）：主标题 34 / 28，字距紧致 -0.025em
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: AppTokens.fontSizeDisplay1,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.025 * AppTokens.fontSizeDisplay1,
          height: 1.2,
          color: primary,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: AppTokens.fontSizeDisplay2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.025 * AppTokens.fontSizeDisplay2,
          height: 1.25,
          color: primary,
        ),
        displaySmall: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: AppTokens.fontSizeHeadline,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.015 * AppTokens.fontSizeHeadline,
          height: 1.3,
          color: primary,
        ),
        // 空态主文案：22 / 500 / 1.35
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 22,
          fontWeight: FontWeight.w500,
          height: 1.35,
          color: primary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 22,
          fontWeight: FontWeight.w500,
          height: 1.35,
          color: primary,
        ),
        // 页面标题、内容小标题：17 / 500 / 1.4
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: primary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: primary,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: primary,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: primary,
        ),
        // 正文：15 / 400 / 1.6
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: primary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: primary,
        ),
        // 次要信息：13 / 400 / 1.55
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.55,
          color: muted,
        ),
        // 标签 / 徽标：11 / 500 / 1.4 (可加 letterSpacing: 0.04)
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: primary,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
          letterSpacing: 0.04,
          color: faint,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: _fontFallback,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
          letterSpacing: 0.04,
          color: faint,
        ),
      );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final controlBorder =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;
    final text = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppPalette.brand : AppPalette.brandAction,
      onPrimary: Colors.white,
      secondary:
          isDark ? AppPalette.darkBrandHover : AppPalette.lightBrandHover,
      onSecondary: Colors.white,
      error: isDark ? AppPalette.darkDanger : AppPalette.lightDanger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest:
          isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
      onSurfaceVariant: textMuted,
      outline: hairline,
      outlineVariant: hairline,
    );

    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      side: BorderSide(color: hairline, width: 1.0),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      side: BorderSide(color: hairline, width: 1.0),
    );
    final pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      side: BorderSide(color: hairline, width: 1.0),
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: isFlat ? canvas : Colors.transparent,
      useMaterial3: true,
      fontFamily: 'Inter',
      fontFamilyFallback: _fontFallback,
      textTheme: _baseTextTheme(
        base.textTheme,
        primary: text,
        muted: textMuted,
        faint: textFaint,
      ),
      dividerColor: hairline,
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1.0,
        space: 1.0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppTokens.kTopBarHeight,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: canvas,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: cardShape,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isFlat
            ? canvas
            : (isDark
                ? AppPalette.darkSurface.withValues(alpha: 0.55)
                : AppPalette.lightSurface.withValues(alpha: 0.65)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(
            color: controlBorder,
            width: 1.0,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(
            color: controlBorder,
            width: 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppPalette.brand, width: 1.2),
        ),
        hintStyle: TextStyle(
          color: textFaint,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: canvas,
        side: BorderSide(color: hairline, width: 1.0),
        shape: pillShape,
        labelStyle: TextStyle(
          color: text,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusModal),
          side: BorderSide(color: hairline, width: 1.0),
        ),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isFlat
            ? canvas
            : (isDark
                ? const Color(0xFF141A29).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.92)),
        modalBackgroundColor: isFlat
            ? canvas
            : (isDark
                ? const Color(0xFF141A29).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.92)),
        modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusModal),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? surface : const Color(0xEB1A1A1A),
        contentTextStyle: TextStyle(
          color: isDark ? text : Colors.white,
          fontSize: 13,
          height: 1.55,
        ),
        shape: controlShape,
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? AppPalette.brand : AppPalette.brandAction,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark
              ? AppPalette.darkSurfaceHover
              : AppPalette.lightSurfaceHover,
          disabledForegroundColor:
              isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          minimumSize: const Size(0, AppTokens.kControlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? AppPalette.brand : AppPalette.brandAction,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark
              ? AppPalette.darkSurfaceHover
              : AppPalette.lightSurfaceHover,
          disabledForegroundColor:
              isDark ? AppPalette.darkTextFaint : AppPalette.lightTextMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          minimumSize: const Size(0, AppTokens.kControlHeight),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            side: BorderSide(color: hairline, width: 1.0),
          ),
          minimumSize: const Size(0, AppTokens.kControlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          minimumSize: const Size(0, AppTokens.kControlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: textMuted,
        textColor: text,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        elevation: 0,
        backgroundColor: AppPalette.brand,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor:
            isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w500, color: text, fontSize: 11),
        ),
      ),
    );
  }
}

/// 明暗两套语义色彩定义集合
class AppSemanticColors {
  const AppSemanticColors({
    required this.canvas,
    required this.surface,
    required this.surfaceHover,
    required this.hairline,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.brand,
    required this.brandHover,
    required this.brandActive,
    required this.brandSoft,
    required this.brandFaint,
    required this.danger,
    required this.warning,
    required this.success,
    // 兼容字段
    required this.floatingSurface,
    required this.elevatedSurface,
    required this.modalSurface,
    required this.border,
    required this.chatUser,
    required this.chatAssistant,
    required this.onGlass,
    required this.mutedOnGlass,
    required this.surfaceTint,
    required this.brandAccent,
    required this.focusGlow,
    required this.glowBright,
    required this.userBubbleStart,
    required this.userBubbleEnd,
    required this.userBubbleGlow,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceHover;
  final Color hairline;
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color brand;
  final Color brandHover;
  final Color brandActive;
  final Color brandSoft;
  final Color brandFaint;
  final Color danger;
  final Color warning;
  final Color success;

  // 兼容老调用字段
  final Color floatingSurface;
  final Color elevatedSurface;
  final Color modalSurface;
  final Color border;
  final Color chatUser;
  final Color chatAssistant;
  final Color onGlass;
  final Color mutedOnGlass;
  final Color surfaceTint;
  final Color brandAccent;
  @Deprecated('视觉规范已移除光晕')
  final Color focusGlow;
  @Deprecated('视觉规范已移除光晕')
  final Color glowBright;
  @Deprecated('视觉规范已改为 brandSoft')
  final Color userBubbleStart;
  @Deprecated('视觉规范已改为 brandSoft')
  final Color userBubbleEnd;
  @Deprecated('视觉规范已移除气泡光晕')
  final Color userBubbleGlow;

  Color get text => textPrimary;

  static const light = AppSemanticColors(
    canvas: AppPalette.lightCanvas,
    surface: AppPalette.lightSurface,
    surfaceHover: AppPalette.lightSurfaceHover,
    hairline: AppPalette.lightHairline,
    textPrimary: AppPalette.lightText,
    textMuted: AppPalette.lightTextMuted,
    textFaint: AppPalette.lightTextMuted,
    brand: AppPalette.brand,
    brandHover: AppPalette.lightBrandHover,
    brandActive: AppPalette.lightBrandActive,
    brandSoft: AppPalette.lightBrandSoft,
    brandFaint: AppPalette.lightBrandFaint,
    danger: AppPalette.lightDanger,
    warning: AppPalette.lightWarning,
    success: AppPalette.lightSuccess,
    floatingSurface: AppPalette.lightSurface,
    elevatedSurface: AppPalette.lightSurface,
    modalSurface: AppPalette.lightSurface,
    border: AppPalette.lightHairline,
    chatUser: AppPalette.lightBrandSoft,
    chatAssistant: AppPalette.lightSurface,
    onGlass: AppPalette.lightText,
    mutedOnGlass: AppPalette.lightTextMuted,
    surfaceTint: Colors.transparent,
    brandAccent: AppPalette.brand,
    focusGlow: Colors.transparent,
    glowBright: Colors.transparent,
    userBubbleStart: AppPalette.lightBrandSoft,
    userBubbleEnd: AppPalette.lightBrandSoft,
    userBubbleGlow: Colors.transparent,
  );

  static const dark = AppSemanticColors(
    canvas: AppPalette.darkCanvas,
    surface: AppPalette.darkSurface,
    surfaceHover: AppPalette.darkSurfaceHover,
    hairline: AppPalette.darkHairline,
    textPrimary: AppPalette.darkText,
    textMuted: AppPalette.darkTextMuted,
    textFaint: AppPalette.darkTextFaint,
    brand: AppPalette.brand,
    brandHover: AppPalette.darkBrandHover,
    brandActive: AppPalette.darkBrandActive,
    brandSoft: AppPalette.darkBrandSoft,
    brandFaint: AppPalette.darkBrandFaint,
    danger: AppPalette.darkDanger,
    warning: AppPalette.darkWarning,
    success: AppPalette.darkSuccess,
    floatingSurface: AppPalette.darkSurface,
    elevatedSurface: AppPalette.darkSurface,
    modalSurface: AppPalette.darkSurface,
    border: AppPalette.darkHairline,
    chatUser: AppPalette.darkBrandSoft,
    chatAssistant: AppPalette.darkSurface,
    onGlass: AppPalette.darkText,
    mutedOnGlass: AppPalette.darkTextMuted,
    surfaceTint: Colors.transparent,
    brandAccent: AppPalette.brand,
    focusGlow: Colors.transparent,
    glowBright: Colors.transparent,
    userBubbleStart: AppPalette.darkBrandSoft,
    userBubbleEnd: AppPalette.darkBrandSoft,
    userBubbleGlow: Colors.transparent,
  );
}
