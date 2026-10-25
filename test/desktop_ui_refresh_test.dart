import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/desktop_page_summary.dart';
import 'package:mobile_agent/presentation/settings/desktop_settings_page.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_empty_state.dart';

void main() {
  double contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  test('desktop palettes distinguish content surfaces and readable accents',
      () {
    for (final colors in [DesktopTheme.light, DesktopTheme.dark]) {
      expect(colors.panel, isNot(colors.canvas));
      expect(contrast(colors.text, colors.panel), greaterThanOrEqualTo(7));
      expect(contrast(colors.muted, colors.panel), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.accent, colors.panel), greaterThanOrEqualTo(4.5));
      expect(
          contrast(colors.accent, colors.selected), greaterThanOrEqualTo(4.5));
    }
  });

  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child, {bool dark = false}) => MaterialApp(
        theme: DesktopTheme.apply(dark ? ThemeData.dark() : ThemeData.light()),
        home: child,
      );

  testWidgets('summary wraps at narrow widths and large text without overflow',
      (tester) async {
    await size(tester, const Size(360, 640));
    await tester.pumpWidget(app(const MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: Scaffold(
          body: DesktopPageSummary(items: [
        (icon: Icons.inbox_outlined, label: '待处理', value: '18'),
        (icon: Icons.task_alt, label: '近期任务', value: '32'),
        (icon: Icons.bolt, label: '近期运行', value: '12'),
      ])),
    )));
    expect(find.text('18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary leaves mobile rendering untouched', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: DesktopPageSummary(
          items: [(icon: Icons.task_alt, label: '仅桌面', value: '7')]),
    )));
    expect(find.text('仅桌面'), findsNothing);
  });

  testWidgets(
      'wide settings switches real categories and searches empty results',
      (tester) async {
    await size(tester, const Size(1100, 800));
    await tester.pumpWidget(
        app(DesktopSettingsPage(onUpdate: () {}, onFontSize: () {})));
    await tester.tap(find.byKey(const ValueKey('desktop-settings-category-3')));
    await tester.pumpAndSettle();
    expect(find.text('字体大小'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在的分类');
    await tester.pump();
    expect(find.text('没有匹配的分类'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact dark settings supports category selection without sidebar overflow',
      (tester) async {
    await size(tester, const Size(620, 700));
    await tester.pumpWidget(app(
        DesktopSettingsPage(onUpdate: () {}, onFontSize: () {}),
        dark: true));
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据与更新').last);
    await tester.pumpAndSettle();
    expect(find.text('数据与备份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'welcome quick actions preserve setup gates and actual prompt callback',
      (tester) async {
    await size(tester, const Size(1000, 700));
    var configured = false;
    await tester.pumpWidget(app(Scaffold(
        body: ChatEmptyState(
      onConfigureModel: () => configured = true,
    ))));
    await tester.tap(find.text('修复报错'));
    expect(configured, isTrue);
    expect(find.text('时光检查点与沙盒保护已就绪'), findsNothing);
    QuickAction? selected;
    await tester.pumpWidget(app(Scaffold(
        body: ChatEmptyState(
      providerConfigured: true,
      hasWorkspace: true,
      onSuggestionTap: (value) => selected = value,
    ))));
    await tester.tap(find.text('审查改动'));
    expect(selected?.label, '审查改动');
    expect(selected?.prompt, contains('真实的错误'));
    expect(tester.takeException(), isNull);
  });
}
