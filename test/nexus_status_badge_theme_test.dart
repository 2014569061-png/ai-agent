import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_badge.dart';

Future<Color?> _fg(
  WidgetTester tester,
  ThemeData theme,
  NexusBadgeTone tone,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: NexusStatusBadge(label: 'x', tone: tone),
      ),
    ),
  );
  return tester.widget<Text>(find.text('x')).style?.color;
}

void main() {
  testWidgets('semantic badge foreground follows the dark theme',
      (tester) async {
    final dark = AppTheme.dark();
    expect(await _fg(tester, dark, NexusBadgeTone.success),
        AppPalette.darkSuccess);
    expect(await _fg(tester, dark, NexusBadgeTone.warning),
        AppPalette.darkWarning);
    expect(
        await _fg(tester, dark, NexusBadgeTone.danger), AppPalette.darkDanger);
  });

  testWidgets('light theme keeps the light semantic foreground',
      (tester) async {
    final light = AppTheme.light();
    expect(await _fg(tester, light, NexusBadgeTone.success),
        AppPalette.lightSuccess);
    expect(await _fg(tester, light, NexusBadgeTone.warning),
        AppPalette.lightWarning);
    expect(await _fg(tester, light, NexusBadgeTone.danger),
        AppPalette.lightDanger);
  });
}
