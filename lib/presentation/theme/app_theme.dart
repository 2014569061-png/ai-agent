import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppTheme {
  static const brand = Color(0xFF0A59F7);
  static const brandBright = Color(0xFF1677FF);

  /// 品牌渐变对（蓝→紫）：录音胶囊、空态艺术、品牌光晕共用；用户气泡的带透明版在 AppSemanticColors。
  static const brandGradientStart = Color(0xFF4C8DFF);
  static const brandGradientEnd = Color(0xFF9333EA);

  /// 玻璃表面弱化文字（mutedOnGlass）的顶层 const 版本，供 const 表达式直接引用。
  static const mutedOnGlassLight = Color(0xFF627D98);
  static const mutedOnGlassDark = Color(0xFF8A94A6);
  static const background = Color(0xFFF6F8FB);
  static const darkBackground = Color(0xFF080D17);
  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
  static const danger = Color(0xFFE5484D);
  static const warning = Color(0xFFF5A623);
  static const success = Color(0xFF2BA471);

  static const radiusSmall = 14.0;
  static const radiusCapsule = 24.0;
  static const radiusCard = 20.0;
  static const radiusModal = 20.0;

  static const lightFloating = Color(0xEFFFFFFF);
  static const darkFloating = Color(0xE61E2635);
  static const lightElevated = Color(0xFFFDFEFF);
  static const darkElevated = Color(0xFF202838);
  static const lightBorder = Color(0xFFDCE5F2);
  static const darkBorder = Color(0xFF354155);
  static const lightGlow = Color(0x241A6BFF);
  static const darkGlow = Color(0x423E86FF);

  static List<BoxShadow> floatingShadow(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? .28 : .08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: isDark ? darkGlow : lightGlow,
          blurRadius: 18,
          spreadRadius: -4,
          offset: const Offset(0, 3),
        ),
      ];

  /// 明暗两套语义色 token。初现时在底部只建一档；后续真正落地时按需补齐。
  static const lightSemantic = AppSemanticColors.light;
  static const darkSemantic = AppSemanticColors.dark;

  static AppSemanticColors semanticOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSemantic
          : lightSemantic;

  static List<String> get _cjkFallback => const [
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
        titleMedium:
            base.titleMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        titleSmall: base.titleSmall?.copyWith(fontFamilyFallback: _cjkFallback),
        labelLarge: base.labelLarge
            ?.copyWith(fontFamilyFallback: _cjkFallback, height: 1.3),
        labelMedium: base.labelMedium
            ?.copyWith(fontFamilyFallback: _cjkFallback, height: 1.3),
        labelSmall: base.labelSmall
            ?.copyWith(fontFamilyFallback: _cjkFallback, height: 1.3),
        headlineLarge:
            base.headlineLarge?.copyWith(fontFamilyFallback: _cjkFallback),
        headlineMedium:
            base.headlineMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        headlineSmall:
            base.headlineSmall?.copyWith(fontFamilyFallback: _cjkFallback),
        displayLarge:
            base.displayLarge?.copyWith(fontFamilyFallback: _cjkFallback),
        displayMedium:
            base.displayMedium?.copyWith(fontFamilyFallback: _cjkFallback),
        displaySmall:
            base.displaySmall?.copyWith(fontFamilyFallback: _cjkFallback),
      );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: isDark ? brandBright : brand,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF72A5FF) : brand,
      secondary: isDark ? const Color(0xFF8EB8FF) : brandBright,
      surface: isDark ? darkBackground : Colors.white,
    );
    final surface = isDark ? darkElevated : lightElevated;
    final floating = isDark ? darkFloating : lightFloating;
    final border = isDark ? darkBorder : lightBorder;
    final foreground = isDark ? const Color(0xFFEDF1F8) : textPrimary;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusCard),
      side: BorderSide(color: border),
    );
    final capsule = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusCapsule),
      side: BorderSide(color: border),
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? darkBackground : background,
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      fontFamilyFallback: _cjkFallback,
      textTheme: _baseTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: shape,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: floating,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusCapsule),
            borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusCapsule),
            borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusCapsule),
            borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? const Color(0xFF26334A) : const Color(0xFFEAF2FF),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
            color: isDark ? foreground : const Color(0xFF174A7E), height: 1.35),
      ),
      // 弹层表面统一由 showImmersiveDialog / showImmersiveSheet 的 ImmersiveSurface 提供，
      // dialogTheme 只保留文字样式，背景保持透明避免出现不透明兜底面。
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        titleTextStyle: TextStyle(
            color: foreground, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: foreground),
        shape: capsule,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              shape: capsule,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 22))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              shape: capsule,
              minimumSize: const Size(0, 46),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              shape: capsule,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 22))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              shape: capsule,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18))),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.primary,
        textColor: foreground,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCapsule),
        ),
        elevation: 6,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor:
            isDark ? const Color(0x334C8DFF) : const Color(0x1F0A59F7),
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600, color: foreground)),
      ),
    );
  }
}

/// 沉浸光感的明暗语义色 token 集合。
/// 各字段与 [AppTheme] 的明暗静态常量对齐，页面/组件一律通过语义名引用，
/// 避免散落的硬编码颜色（背景、浮层、抬升面、模态、边框、文字、聊天双方气泡与状态色）。
class AppSemanticColors {
  const AppSemanticColors({
    required this.canvas,
    required this.surface,
    required this.floatingSurface,
    required this.elevatedSurface,
    required this.modalSurface,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.chatUser,
    required this.chatAssistant,
    required this.danger,
    required this.warning,
    required this.success,
    required this.focusGlow,
    required this.glowBright,
    required this.brandAccent,
    required this.userBubbleStart,
    required this.userBubbleEnd,
    required this.userBubbleGlow,
    required this.onGlass,
    required this.mutedOnGlass,
  });

  final Color canvas;
  final Color surface;
  final Color floatingSurface;
  final Color elevatedSurface;
  final Color modalSurface;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color chatUser;
  final Color chatAssistant;
  final Color danger;
  final Color warning;
  final Color success;
  final Color focusGlow;
  final Color glowBright;

  /// 品牌强调蓝（计划卡片、抽屉图标、选中态描边）。
  final Color brandAccent;

  /// 用户气泡彩色玻璃：渐变起止（自带透明度，叠在 BackdropFilter 上）。
  final Color userBubbleStart;
  final Color userBubbleEnd;

  /// 用户气泡光晕（浅色主题下透明，即无光晕）。
  final Color userBubbleGlow;

  /// 彩色玻璃表面上的正文颜色。
  final Color onGlass;

  /// 玻璃表面上的弱化文字/署名（比 textMuted 更贴玻璃材质的一档）。
  final Color mutedOnGlass;

  static const light = AppSemanticColors(
    canvas: AppTheme.background,
    surface: AppTheme.lightElevated,
    floatingSurface: AppTheme.lightFloating,
    elevatedSurface: AppTheme.lightElevated,
    modalSurface: Color(0xFFFDFEFF),
    border: AppTheme.lightBorder,
    textPrimary: AppTheme.textPrimary,
    textMuted: AppTheme.textSecondary,
    chatUser: Color(0xFF0A59F7),
    chatAssistant: Color(0xFFEFF4FB),
    danger: AppTheme.danger,
    warning: AppTheme.warning,
    success: AppTheme.success,
    focusGlow: AppTheme.lightGlow,
    glowBright: Color(0x331A6BFF),
    brandAccent: AppTheme.brandBright,
    userBubbleStart: Color(0x9EFFFFFF),
    userBubbleEnd: Color(0x80C7D7FE),
    userBubbleGlow: Color(0x00000000),
    onGlass: AppTheme.textPrimary,
    mutedOnGlass: AppTheme.mutedOnGlassLight,
  );

  static const dark = AppSemanticColors(
    canvas: AppTheme.darkBackground,
    surface: AppTheme.darkElevated,
    floatingSurface: AppTheme.darkFloating,
    elevatedSurface: AppTheme.darkElevated,
    modalSurface: Color(0xFF202838),
    border: AppTheme.darkBorder,
    textPrimary: Color(0xFFEDF1F8),
    textMuted: Color(0xFF94A3B8),
    chatUser: Color(0xFF72A5FF),
    chatAssistant: Color(0xFF263448),
    danger: AppTheme.danger,
    warning: AppTheme.warning,
    success: AppTheme.success,
    focusGlow: AppTheme.darkGlow,
    glowBright: Color(0x663E86FF),
    brandAccent: Color(0xFF4C8DFF),
    userBubbleStart: Color(0x8C4C8DFF),
    userBubbleEnd: Color(0x8C9333EA),
    userBubbleGlow: Color(0x4D9333EA),
    onGlass: Colors.white,
    mutedOnGlass: AppTheme.mutedOnGlassDark,
  );
}
