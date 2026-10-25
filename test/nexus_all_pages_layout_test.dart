import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_page_layout.dart';
import 'package:mobile_agent/presentation/widgets/nexus_background.dart';
import 'package:mobile_agent/presentation/chat/widgets/input_tool_grid_sheet.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/widgets/nexus_metric_tile.dart';
import 'package:mobile_agent/presentation/widgets/nexus_page_header.dart';
import 'package:mobile_agent/presentation/widgets/nexus_sheet.dart';
import 'package:mobile_agent/presentation/widgets/desktop_resource_view.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';
import 'package:mobile_agent/presentation/settings/language_page.dart';
import 'package:mobile_agent/presentation/feedback/feedback_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Register production font families before any paragraphs are cached.
    for (final config in [
      ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
      // Missing platform families otherwise resolve to the test-only Ahem font.
      ('PingFang SC', 'C:/Windows/Fonts/msyh.ttc'),
      ('Noto Sans SC', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
      ('Inter', 'assets/fonts/Inter-Regular.ttf'),
    ]) {
      final file = File(config.$2);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        await (FontLoader(config.$1)
              ..addFont(Future.value(bytes.buffer.asByteData())))
            .load();
      }
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Widget child,
          {bool desktop = false,
          double scale = 1,
          double keyboard = 0,
          bool dark = false}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: desktop
            ? DesktopTheme.apply(dark ? AppTheme.dark() : AppTheme.light())
            : MobileTheme.apply(dark ? AppTheme.dark() : AppTheme.light()),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboard),
                disableAnimations: true),
            child: child!),
        home: child,
      );

  test('every ordinary page explicitly participates in the adaptive layout',
      () {
    const specialized = {
      'chat/chat_page.dart',
      'settings/desktop_settings_page.dart',
      'onboarding/onboarding_page.dart',
      'plugins/skill_market_page.dart',
    };
    final root = Directory('lib/presentation');
    final pages = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('page.dart'))
        .toList();
    expect(pages.length, greaterThanOrEqualTo(46));
    for (final file in pages) {
      final relative =
          file.path.replaceAll('\\', '/').split('lib/presentation/').last;
      if (specialized.contains(relative)) continue;
      expect(file.readAsStringSync(), contains('NexusPageLayout('),
          reason: relative);
    }
  });

  testWidgets(
      'page layout keeps desktop and tablet measures without nesting scroll views',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await size(tester, const Size(1600, 900));
    for (final config in [
      (1600.0, true, 1240.0),
      (1024.0, false, 760.0),
      (390.0, false, 390.0)
    ]) {
      tester.view.physicalSize = Size(config.$1, 900);
      await tester.pumpWidget(host(
          Scaffold(
              body: NexusPageLayout(
                  child: ListView.builder(
                      key: const ValueKey('page-list'),
                      controller: controller,
                      itemCount: 100,
                      itemBuilder: (_, index) =>
                          SizedBox(height: 50, child: Text('记录 $index'))))),
          desktop: config.$2));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('page-list'))).width,
          closeTo(config.$3, 1));
      expect(find.byType(Scrollable), findsOneWidget);
      controller.jumpTo(250);
      await tester.pump();
      expect(controller.offset, 250);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large text settings preserve title and status without overflow',
      (tester) async {
    await size(tester, const Size(320, 640));
    await tester.pumpWidget(host(
        Scaffold(
            body: Column(children: [
          SettingsTile(
              title: '设备自动化与后台执行',
              subtitle: '权限状态与执行限制',
              trailingText: '需要授权后启用',
              icon: Icons.phone_android,
              onTap: () {}),
        ])),
        scale: 2));
    expect(tester.widget<Text>(find.text('设备自动化与后台执行')).maxLines, 2);
    expect(tester.getSize(find.byType(SettingsTile)).height,
        greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('page header honors explicit back action and large-text title',
      (tester) async {
    await size(tester, const Size(320, 640));
    var backs = 0;
    await tester.pumpWidget(host(
        Scaffold(
            appBar: NexusPageHeader(
                title: '设备能力与执行环境', subtitle: '完整状态说明', onBack: () => backs++),
            body: const SizedBox()),
        scale: 2));
    expect(find.text('完整状态说明'), findsNothing);
    expect(find.byTooltip('设备能力与执行环境 · 完整状态说明'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    expect(backs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'resource cards keep actions available in wide narrow and large-text layouts',
      (tester) async {
    await size(tester, const Size(1100, 800));
    var edits = 0;
    double? wideHeight;
    for (final config in [(1000.0, 1.0), (420.0, 1.0), (420.0, 2.0)]) {
      await tester.pumpWidget(host(
          Scaffold(
              body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                      width: config.$1,
                      child: DesktopResourceCard(
                        title: '示例资源',
                        icon: Icons.storage,
                        description: '清晰的资源说明',
                        metadata: const ['已配置', '需要连接测试'],
                        actions: [
                          OutlinedButton(
                              onPressed: () => edits++,
                              child: const Text('编辑配置'))
                        ],
                      )))),
          desktop: true,
          scale: config.$2));
      await tester.pumpAndSettle();
      final height = tester.getSize(find.byType(DesktopResourceCard)).height;
      if (config.$1 == 1000) wideHeight = height;
      if (config.$1 == 420 && config.$2 == 1) {
        expect(height, greaterThan(wideHeight!));
      }
      await tester.tap(find.text('编辑配置'));
      expect(tester.takeException(), isNull);
    }
    expect(edits, 3);
  });

  testWidgets(
      'sheet stays above the keyboard without clipping the safe top edge',
      (tester) async {
    await size(tester, const Size(390, 640));
    await tester.pumpWidget(host(
        Builder(
            builder: (context) => Scaffold(
                resizeToAvoidBottomInset: false,
                body: Center(
                    child: FilledButton(
                        onPressed: () => showNexusSheet<void>(
                            context: context,
                            builder: (_) => ListView(
                                key: const ValueKey('sheet-list'),
                                shrinkWrap: true,
                                children: List.generate(20,
                                    (i) => ListTile(title: Text('选项 $i'))))),
                        child: const Text('打开'))))),
        keyboard: 280));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('sheet-list')));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'metric grid adapts column count and allows intrinsic large-text height',
      (tester) async {
    await size(tester, const Size(1400, 900));
    for (final config in [(1200.0, 1.0, 4), (360.0, 1.0, 2), (288.0, 2.0, 1)]) {
      await tester.pumpWidget(host(
          Scaffold(
              body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                      width: config.$1,
                      child: NexusMetricGrid(
                          children: List.generate(
                              4,
                              (index) => NexusMetricTile(
                                  label: '输入 Token $index',
                                  value: '123.4k',
                                  unit: 'tok',
                                  icon: Icons.input_rounded,
                                  explanation: '指标含义说明')))))),
          scale: config.$2));
      await tester.pumpAndSettle();
      final tiles = find.byType(NexusMetricTile);
      final first = tester.getRect(tiles.at(0));
      final next = tester.getRect(tiles.at(config.$3 == 4 ? 1 : config.$3));
      if (config.$3 == 4) {
        expect(next.top, closeTo(first.top, 1));
      } else {
        expect(next.top, greaterThanOrEqualTo(first.bottom));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'tool sheet supports scrolling to actions on narrow large-text screens',
      (tester) async {
    await size(tester, const Size(320, 640));
    var approvals = 0;
    await tester.pumpWidget(host(
        Builder(
            builder: (context) => Scaffold(
                body: Center(
                    child: FilledButton(
                        onPressed: () => InputToolGridSheet.show(context,
                            onCommandMenu: () {},
                            onMcpMenu: () {},
                            onTerminalPreview: () {},
                            onEnvSetup: () {},
                            onOpenDashboard: () {},
                            planModeEnabled: false,
                            onPlanModeToggle: () {},
                            approvalMode: ApprovalMode.ask,
                            onApprovalModeTap: () => approvals++),
                        child: const Text('打开工具箱'))))),
        scale: 2,
        keyboard: 160));
    await tester.tap(find.text('打开工具箱'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('审批策略'), 120,
        scrollable: find.descendant(
            of: find.byType(InputToolGridSheet),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('审批策略'));
    await tester.pumpAndSettle();
    expect(approvals, 1);
    expect(find.byType(InputToolGridSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('both themes support readable multiline validation', () {
    for (final theme in [
      AppTheme.light(),
      AppTheme.dark(),
      DesktopTheme.apply(AppTheme.light())
    ]) {
      expect(theme.inputDecorationTheme.errorMaxLines, 3);
      expect(theme.inputDecorationTheme.helperMaxLines, 3);
    }
  });

  testWidgets('capture representative mobile secondary pages in both themes',
      (tester) async {
    await size(tester, const Size(390, 844));
    for (final dark in [false, true]) {
      for (final entry in <(String, Widget)>[
        ('language', const LanguagePage()),
        ('feedback', const FeedbackPage()),
      ]) {
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: host(NexusBackground(child: entry.$2), dark: dark)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              'artifacts/ui-all-pages/mobile-${entry.$1}-${dark ? 'dark' : 'light'}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
