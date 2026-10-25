import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    final surface = dark ? AppPalette.darkSurface : AppPalette.lightCanvas;
    test('text roles reach AA without changing primary dark=$dark', () {
      final expected = AppPalette.brandTextFor(dark);
      expect(theme.colorScheme.primary, AppPalette.brand);
      expect(theme.tabBarTheme.labelColor, expected);
      for (final style in [
        theme.textButtonTheme.style!,
        theme.outlinedButtonTheme.style!
      ]) {
        final color = style.foregroundColor!.resolve({})!;
        expect(color, expected);
        expect(contrast(color, surface), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(theme.tabBarTheme.labelColor!, surface),
          greaterThanOrEqualTo(4.5));
    });
    test('filled action pairs remain original dark=$dark', () {
      for (final style in [
        theme.filledButtonTheme.style!,
        theme.elevatedButtonTheme.style!
      ]) {
        final bg = style.backgroundColor!.resolve({})!,
            fg = style.foregroundColor!.resolve({})!;
        expect(bg, AppPalette.brand);
        expect(fg, Colors.white);
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
      }
    });
    test('desktop tab override remains independent dark=$dark', () {
      final desktop = DesktopTheme.apply(theme);
      expect(desktop.tabBarTheme.labelColor,
          (dark ? DesktopTheme.dark : DesktopTheme.light).accent);
    });
    testWidgets('rendered selected tab uses text token dark=$dark',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
                appBar: AppBar(
                    bottom: const TabBar(
                        tabs: [Tab(text: '选中'), Tab(text: '其他')]))),
          )));
      await tester.pumpAndSettle();
      final color =
          DefaultTextStyle.of(tester.element(find.text('选中'))).style.color;
      expect(color, AppPalette.brandTextFor(dark));
      expect(tester.takeException(), isNull);
    });
  }
}
