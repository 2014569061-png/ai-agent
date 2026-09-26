import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

Future<List<Color>> _tints(WidgetTester tester, ThemeData theme) async {
  late List<Color> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          result = [
            normalizeIconTint(context, AppPalette.success),
            normalizeIconTint(context, AppPalette.warning),
            normalizeIconTint(context, AppPalette.danger),
            normalizeIconTint(context, AppPalette.darkSuccess),
            normalizeIconTint(context, const Color(0xFFAF52DE)),
          ];
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('AppPalette semantic colours keep their meaning in dark theme',
      (tester) async {
    final dark = await _tints(tester, AppTheme.dark());
    expect(dark, [
      AppTheme.darkSemantic.success,
      AppTheme.darkSemantic.warning,
      AppTheme.darkSemantic.danger,
      AppTheme.darkSemantic.success,
      AppTheme.darkSemantic.textMuted,
    ]);
  });

  testWidgets('dark palette values map back to light tokens in light theme',
      (tester) async {
    final light = await _tints(tester, AppTheme.light());
    expect(light, [
      AppTheme.lightSemantic.success,
      AppTheme.lightSemantic.warning,
      AppTheme.lightSemantic.danger,
      AppTheme.lightSemantic.success,
      AppTheme.lightSemantic.textMuted,
    ]);
  });
}
