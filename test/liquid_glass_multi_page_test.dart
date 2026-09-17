import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_catalog_drawer.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';
import 'package:mobile_agent/presentation/widgets/nexus_background.dart';
import 'package:mobile_agent/presentation/widgets/nexus_metric_tile.dart';
import 'package:mobile_agent/presentation/widgets/nexus_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppAppearanceController.load();
  });

  group('NexusBackground liquid glass behavior', () {
    testWidgets('renders gradient when glass intensity is liquid', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      await tester.pumpWidget(
        const MaterialApp(
          home: NexusBackground(
            child: Text('Content'),
          ),
        ),
      );

      final decoratedFinder = find.descendant(
        of: find.byType(NexusBackground),
        matching: find.byType(DecoratedBox),
      );
      expect(decoratedFinder, findsOneWidget);
      final decoratedBox = tester.widget<DecoratedBox>(decoratedFinder);
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.gradient, isNotNull);
    });

    testWidgets('renders flat ColoredBox when glass intensity is flat', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.flat);

      await tester.pumpWidget(
        const MaterialApp(
          home: NexusBackground(
            child: Text('Content'),
          ),
        ),
      );

      final coloredFinder = find.descendant(
        of: find.byType(NexusBackground),
        matching: find.byType(ColoredBox),
      );
      expect(coloredFinder, findsOneWidget);

      final decoratedFinder = find.descendant(
        of: find.byType(NexusBackground),
        matching: find.byType(DecoratedBox),
      );
      expect(decoratedFinder, findsNothing);
    });
  });

  group('NexusMetricTile liquid glass behavior', () {
    testWidgets('renders LiquidGlass tile when non-flat', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusMetricTile(
              label: 'Today Tokens',
              value: '12.5k',
            ),
          ),
        ),
      );

      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(find.text('Today Tokens'), findsOneWidget);
      expect(find.text('12.5k'), findsOneWidget);
    });

    testWidgets('renders standard flat container when flat', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.flat);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusMetricTile(
              label: 'Today Tokens',
              value: '12.5k',
            ),
          ),
        ),
      );

      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.text('Today Tokens'), findsOneWidget);
    });
  });

  group('NexusSheet liquid glass integration', () {
    testWidgets('opens sheet with LiquidGlass in liquid mode', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showNexusSheet(
                      context: context,
                      builder: (ctx) => const Text('Sheet Content'),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Sheet Content'), findsOneWidget);
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(LiquidGlass),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });
  });

  group('ChatCatalogDrawer liquid glass integration', () {
    testWidgets('renders LiquidGlass in liquid mode', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ChatCatalogDrawer(
              contextTokens: 0,
              currentWorkspacePath: null,
              activeModel: 'DeepSeek-V3',
              activeProviderName: 'DeepSeek',
              messages: const [],
              isRunning: false,
              planModeEnabled: false,
              approvalMode: ApprovalMode.autoSafe,
              onNewConversation: () {},
              onSelectConversation: (_) {},
              onWorkspaceTap: () {},
              onModelTap: () {},
              onMcpMenu: () {},
              onPromptLibrary: () {},
              onPlanModeToggle: () {},
            ),
            body: const Center(child: Text('Main Screen')),
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ChatCatalogDrawer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('does not render LiquidGlass in flat mode', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.flat);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ChatCatalogDrawer(
              contextTokens: 0,
              currentWorkspacePath: null,
              activeModel: 'DeepSeek-V3',
              activeProviderName: 'DeepSeek',
              messages: const [],
              isRunning: false,
              planModeEnabled: false,
              approvalMode: ApprovalMode.autoSafe,
              onNewConversation: () {},
              onSelectConversation: (_) {},
              onWorkspaceTap: () {},
              onModelTap: () {},
              onMcpMenu: () {},
              onPromptLibrary: () {},
              onPlanModeToggle: () {},
            ),
            body: const Center(child: Text('Main Screen')),
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ChatCatalogDrawer), findsOneWidget);
      expect(find.descendant(of: find.byType(ChatCatalogDrawer), matching: find.byType(LiquidGlass)), findsNothing);
    });
  });
}
