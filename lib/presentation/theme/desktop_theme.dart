import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// NEXUS 桌面设计系统：中性工作区、独立内容面板与蓝色操作强调。
/// 与移动端外观隔离，保留高对比度和减少动态效果支持。
@immutable
class DesktopTheme extends ThemeExtension<DesktopTheme> {
  const DesktopTheme({
    required this.canvas,
    required this.sidebar,
    required this.panel,
    required this.hover,
    required this.selected,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
  });

  final Color canvas,
      sidebar,
      panel,
      hover,
      selected,
      border,
      text,
      muted,
      accent;
  static const radius = 10.0;
  static const panelRadius = 14.0;
  static const dialogRadius = 16.0;
  static const baseSize = 14.0;
  static const statusSuccess = Color(0xFF10B981);
  static const statusWarning = Color(0xFFF59E0B);
  static const microSize = 10.5;
  static const compactSize = 11.5;
  static const labelSize = 13.0;
  static const toolbarSize = 13.5;
  static const heroSize = 27.0;
  static const smallSize = 12.0;
  static const subtitleSize = 16.0;
  static const titleSize = 18.0;

  static DesktopTheme? maybeOf(BuildContext context) =>
      Theme.of(context).extension<DesktopTheme>() == null ? null : of(context);

  /// 依据系统或上下文环境判定桌面主题（自适应高对比度模式）
  static DesktopTheme of(BuildContext context) {
    final isHighContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext = Theme.of(context).extension<DesktopTheme>();
    if (isHighContrast) {
      return isDark ? highContrastDark : highContrastLight;
    }
    return ext ?? (isDark ? dark : light);
  }

  /// 检测当前上下文是否开启减少动态效果 (Reduce Motion)
  static bool reduceMotion(BuildContext context) {
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
  }

  /// 依据减少动态效果自适应动效时长
  static Duration motionDuration(BuildContext context, Duration duration) =>
      reduceMotion(context) ? Duration.zero : duration;

  static TextStyle monospaceStyle(
    BuildContext context, {
    double size = baseSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
  }) {
    final colors = maybeOf(context) ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
    return TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const [
        'Menlo',
        'Monaco',
        'Courier New',
        'Microsoft YaHei',
        'monospace'
      ],
      fontSize: size,
      fontWeight: fontWeight,
      color: color ?? colors.text,
      height: 1.4,
    );
  }

  static const light = DesktopTheme(
    canvas: Color(0xFFF5F7FB),
    sidebar: Color(0xFFEDF1F8),
    panel: Color(0xFFFFFFFF),
    hover: Color(0xFFE8EDF6),
    selected: Color(0xFFE3EBFF),
    border: Color(0xFFD9E1EE),
    text: Color(0xFF17243B),
    muted: Color(0xFF596A83),
    accent: Color(0xFF315DEB),
  );
  static const dark = DesktopTheme(
    canvas: Color(0xFF0D1422),
    sidebar: Color(0xFF111B2C),
    panel: Color(0xFF172338),
    hover: Color(0xFF20304A),
    selected: Color(0xFF243B65),
    border: Color(0xFF30415C),
    text: Color(0xFFEDF2FC),
    muted: Color(0xFFA4B4CE),
    accent: Color(0xFF91B2FF),
  );

  static const highContrastLight = DesktopTheme(
    canvas: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF1F5F9),
    panel: Color(0xFFFFFFFF),
    hover: Color(0xFFE2E8F0),
    selected: Color(0xFFBAE6FD),
    border: Color(0xFF000000),
    text: Color(0xFF000000),
    muted: Color(0xFF1E293B),
    accent: Color(0xFF1D4ED8),
  );
  static const highContrastDark = DesktopTheme(
    canvas: Color(0xFF000000),
    sidebar: Color(0xFF09090B),
    panel: Color(0xFF121214),
    hover: Color(0xFF27272A),
    selected: Color(0xFF3F3F46),
    border: Color(0xFFFFFFFF),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFFE4E4E7),
    accent: Color(0xFF60A5FA),
  );

  static ThemeData apply(ThemeData base, {bool? highContrast}) {
    final useHighContrast = highContrast ?? false;
    final isDark = base.brightness == Brightness.dark;
    final colors = useHighContrast
        ? (isDark ? highContrastDark : highContrastLight)
        : (isDark ? dark : light);
    TextStyle style(double size, {bool muted = false, bool title = false}) =>
        TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const [
              'Microsoft YaHei',
              'PingFang SC',
              'Noto Sans SC',
              'sans-serif'
            ],
            fontSize: size,
            height: 1.4,
            fontWeight: title ? FontWeight.w600 : FontWeight.w400,
            color: muted ? colors.muted : colors.text);
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(34, 34)),
      padding:
          const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      shape: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: colors.accent, width: 2.0),
          );
        }
        return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius));
      }),
      textStyle: WidgetStatePropertyAll(style(baseSize)),
      elevation: const WidgetStatePropertyAll(0),
    );
    return base.copyWith(
      // Desktop pointer controls should not reserve mobile-sized tap padding.
      // Text still scales naturally; no fixed input heights are introduced.
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      focusColor: colors.accent.withValues(alpha: 0.16),
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      hoverColor: colors.hover,
      highlightColor: colors.selected,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.accent.withValues(alpha: .22),
        selectionHandleColor: colors.accent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        textColor: colors.text,
        selectedColor: colors.accent,
        selectedTileColor: colors.selected,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.accent,
        unselectedLabelColor: colors.muted,
        indicatorColor: colors.accent,
        dividerColor: colors.border,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: style(13, title: true),
        unselectedLabelStyle: style(13),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: style(13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius),
          side: BorderSide(color: colors.border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.panel,
        selectedColor: colors.selected,
        secondarySelectedColor: colors.selected,
        labelStyle: style(smallSize),
        secondaryLabelStyle: style(smallSize).copyWith(color: colors.accent),
        side: BorderSide(color: colors.border),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.text,
        contentTextStyle: style(13).copyWith(color: colors.panel),
        actionTextColor:
            isDark ? const Color(0xFF2449B8) : const Color(0xFFBED0FF),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dividerColor: colors.border,
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return colors.muted;
          return colors.border;
        }),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: style(smallSize),
        waitDuration: AppTokens.durationExpand,
      ),
      colorScheme: base.colorScheme.copyWith(
        surface: colors.panel,
        surfaceContainer: colors.panel,
        surfaceContainerLow: colors.panel,
        surfaceContainerHighest: colors.hover,
        onSurface: colors.text,
        onSurfaceVariant: colors.muted,
        primary: colors.accent,
        onPrimary:
            base.brightness == Brightness.dark ? dark.sidebar : Colors.white,
        primaryContainer: colors.selected,
        onPrimaryContainer: colors.text,
        secondaryContainer: colors.hover,
        onSecondaryContainer: colors.text,
        outline: colors.muted,
        outlineVariant: colors.border,
        surfaceTint: Colors.transparent,
      ),
      textTheme: TextTheme(
        displayLarge: style(24, title: true),
        displayMedium: style(22, title: true),
        displaySmall: style(20, title: true),
        headlineLarge: style(20, title: true),
        headlineMedium: style(21, title: true).copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        headlineSmall: style(titleSize, title: true),
        titleLarge: style(subtitleSize, title: true),
        titleMedium: style(13.5, title: true),
        titleSmall: style(baseSize, title: true),
        bodyLarge: style(baseSize),
        bodyMedium: style(baseSize),
        bodySmall: style(smallSize, muted: true),
        labelLarge: style(baseSize),
        labelMedium: style(smallSize),
        labelSmall: style(10, muted: true),
      ),
      iconTheme: IconThemeData(color: colors.muted, size: 16),
      appBarTheme: AppBarTheme(
          backgroundColor: colors.panel,
          foregroundColor: colors.text,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 48,
          titleTextStyle: style(baseSize, title: true)),
      cardTheme: CardThemeData(
          color: colors.panel,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(panelRadius),
              side: BorderSide(color: colors.border))),
      dialogTheme: DialogThemeData(
          backgroundColor: colors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogRadius),
              side: BorderSide(color: colors.border))),
      filledButtonTheme: FilledButtonThemeData(
          style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? colors.hover
                : colors.accent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? colors.muted
                : (isDark ? const Color(0xFF101C35) : Colors.white)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: button.copyWith(
              side: WidgetStatePropertyAll(BorderSide(color: colors.border)))),
      textButtonTheme: TextButtonThemeData(
          style: button.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? colors.muted
                : colors.accent),
      )),
      iconButtonTheme: IconButtonThemeData(
          style: button.copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.all(6)))),
      inputDecorationTheme: InputDecorationTheme(
        errorMaxLines: 3,
        helperMaxLines: 3,
        filled: true,
        fillColor: colors.panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: colors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: colors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: colors.accent, width: 1.5)),
      ),
      extensions: [
        ...base.extensions.values.where((item) => item is! DesktopTheme),
        colors
      ],
    );
  }

  @override
  DesktopTheme copyWith(
          {Color? canvas,
          Color? sidebar,
          Color? panel,
          Color? hover,
          Color? selected,
          Color? border,
          Color? text,
          Color? muted,
          Color? accent}) =>
      DesktopTheme(
          canvas: canvas ?? this.canvas,
          sidebar: sidebar ?? this.sidebar,
          panel: panel ?? this.panel,
          hover: hover ?? this.hover,
          selected: selected ?? this.selected,
          border: border ?? this.border,
          text: text ?? this.text,
          muted: muted ?? this.muted,
          accent: accent ?? this.accent);

  @override
  DesktopTheme lerp(DesktopTheme? other, double t) {
    if (other == null) return this;
    return DesktopTheme(
        canvas: Color.lerp(canvas, other.canvas, t)!,
        sidebar: Color.lerp(sidebar, other.sidebar, t)!,
        panel: Color.lerp(panel, other.panel, t)!,
        hover: Color.lerp(hover, other.hover, t)!,
        selected: Color.lerp(selected, other.selected, t)!,
        border: Color.lerp(border, other.border, t)!,
        text: Color.lerp(text, other.text, t)!,
        muted: Color.lerp(muted, other.muted, t)!,
        accent: Color.lerp(accent, other.accent, t)!);
  }
}
