import 'package:mobile_agent/presentation/widgets/nexus_page_header.dart';
import 'package:mobile_agent/presentation/navigation/mobile_navigation_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/navigation/mobile_shell.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';

void main() {
  test('phone platform remains mobile regardless of display size', () {
    expect(usesMobileShell(TargetPlatform.android), isTrue);
    expect(usesMobileShell(TargetPlatform.iOS), isTrue);
    expect(usesMobileShell(TargetPlatform.windows), isFalse);
  });
  Future<void> show(WidgetTester tester, List<int> built) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: MobileTheme.apply(ThemeData.light()),
            home: MobileShell(
              pageBuilders: List.generate(
                  4,
                  (index) => (context) {
                        built[index]++;
                        return Scaffold(
                            appBar: NexusPageHeader(title: 'root-$index'),
                            body: Column(children: [
                              Text('page-$index'),
                              TextField(key: ValueKey('draft-$index')),
                              TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => Scaffold(
                                              appBar: AppBar(
                                                  title: Text('detail-$index'),
                                                  actions: const [
                                                    MobileNavigationMenuButton()
                                                  ]),
                                              body:
                                                  const Text('detail body')))),
                                  child: Text('open-$index')),
                            ]));
                      }),
            ))));
    await tester.pumpAndSettle();
  }

  testWidgets('sidebar destinations are lazy and preserve drafts',
      (tester) async {
    final built = List.filled(4, 0);
    await show(tester, built);
    expect(built, [1, 0, 0, 0]);
    await tester.enterText(find.byKey(const ValueKey('draft-0')), '保留草稿');
    await select(tester, 1);
    await tester.pumpAndSettle();
    expect(find.text('page-1'), findsOneWidget);
    await select(tester, 0);
    await tester.pumpAndSettle();
    expect(find.text('保留草稿'), findsOneWidget);
    expect(built[0], 1);
  });
  testWidgets('sidebar retains child routes and system back pops them first',
      (tester) async {
    await show(tester, List.filled(4, 0));
    await select(tester, 2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-2'));
    await tester.pumpAndSettle();
    await select(tester, 0);
    await tester.pumpAndSettle();
    await select(tester, 2);
    await tester.pumpAndSettle();
    expect(find.text('detail-2'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('page-2'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('page-0'), findsOneWidget);
  });
  testWidgets('system back closes the drawer before leaving its destination',
      (tester) async {
    await show(tester, List.filled(4, 0));
    await select(tester, 1);
    await tester.tap(find.byTooltip('打开导航菜单'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MobilePrimaryNavigation), findsNothing);
    expect(find.text('page-1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('page-0'), findsOneWidget);
  });

  testWidgets('drawer can be opened from a detail by swiping from the edge',
      (tester) async {
    await show(tester, List.filled(4, 0));
    await select(tester, 2);
    await tester.tap(find.text('open-2'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1, 220), const Offset(310, 0));
    await tester.pumpAndSettle();
    expect(find.byType(MobilePrimaryNavigation), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-destination-0')));
    await tester.pumpAndSettle();
    expect(find.text('page-0'), findsOneWidget);
  });

  testWidgets('narrow screen and large text do not overflow navigation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester, List.filled(4, 0));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('打开导航菜单'));
    await tester.pumpAndSettle();
    expect(find.byType(MobilePrimaryNavigation), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> select(WidgetTester tester, int index) async {
  await tester.tap(find.byTooltip('打开导航菜单'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mobile-destination-$index')));
  await tester.pumpAndSettle();
}
