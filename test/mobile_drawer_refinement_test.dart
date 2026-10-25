import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_catalog_drawer.dart';
import 'package:mobile_agent/presentation/navigation/mobile_navigation_scope.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';

void main() {
  testWidgets(
      'actual mobile drawer keeps search and navigation usable with large text and keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bridge = MobileDrawerBridge();
    addTearDown(bridge.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: MobileTheme.apply(AppTheme.light()),
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 740),
            textScaler: TextScaler.linear(1.6),
            viewInsets: EdgeInsets.only(bottom: 260)),
        child: MobileNavigationScope(
          selectedIndex: 0,
          pendingCount: 2,
          drawerBridge: bridge,
          openDrawer: () {},
          selectDestination: (_) {},
          child: Scaffold(
              body: ChatCatalogDrawer(
            contextTokens: 0,
            currentWorkspacePath: null,
            activeModel: '',
            activeProviderName: '',
            messages: const [],
            isRunning: false,
            planModeEnabled: false,
            onNewConversation: () {},
            onSelectConversation: (_) {},
            onWorkspaceTap: () {},
            onModelTap: () {},
            onMcpMenu: () {},
            onPromptLibrary: () {},
            onPlanModeToggle: () {},
          )),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('搜索最近对话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('新建对话'), findsNothing);
    expect(find.text('助手与工具'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(find.byType(TextField), 'no matching conversation');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('收起搜索'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('新建对话'), findsOneWidget);
    expect(find.text('助手与工具'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索最近对话'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });
}
