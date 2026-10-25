import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_theme.dart';

enum AppStatusTone { neutral, brand, success, warning, danger }

/// Foreground/fill pairs for small status text, independent of parent glass.
/// This does not replace brand action backgrounds or business-state mappings.
@immutable
class AppStatusColors {
  const AppStatusColors({required this.foreground, required this.background});

  final Color foreground;
  final Color background;

  static AppStatusColors resolve(BuildContext context, AppStatusTone tone) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final phone = Theme.of(context).extension<AppSemanticTheme>() != null;
    final scheme = Theme.of(context).colorScheme;
    final (foreground, background) = switch (tone) {
      AppStatusTone.neutral => (
          phone
              ? scheme.onSurfaceVariant
              : (dark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted),
          dark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover,
        ),
      AppStatusTone.brand => (
          phone ? scheme.primary : AppPalette.brandTextFor(dark),
          phone
              ? scheme.primaryContainer
              : (dark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft),
        ),
      AppStatusTone.success => (
          dark ? AppPalette.darkSuccess : AppPalette.lightSuccess,
          dark ? AppPalette.darkSuccessSoft : AppPalette.lightSuccessSoft,
        ),
      AppStatusTone.warning => (
          dark ? AppPalette.darkWarning : AppPalette.lightWarning,
          dark ? AppPalette.darkWarningSoft : AppPalette.lightWarningSoft,
        ),
      AppStatusTone.danger => (
          // The unchanged darkDanger/darkDangerSoft pair is only 4.25:1.
          dark
              ? Color.lerp(AppPalette.darkDanger, Colors.white, .1)!
              : AppPalette.lightDanger,
          dark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft,
        ),
    };
    return AppStatusColors(
      foreground: highContrast
          ? (dark ? AppPalette.darkText : AppPalette.lightText)
          : foreground,
      background: background,
    );
  }
}
