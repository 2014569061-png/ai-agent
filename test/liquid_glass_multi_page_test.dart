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
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppAppearanceController.load();
  });

  group('NexusBackground liquid glass behavior', () {
    testWidgets('keeps the solid mobile canvas even when glass is enabled',
        (tester) async {
      await AppAppearanceController.setGlassIntensityMode(
          GlassIntensity.liquid);

      await tester.pumpWidget(
        const MaterialApp(
          home: NexusBackground(
            child: Text('Content'),
          ),
        ),
      );

      final canvas = find.descendant(
          of: find.byType(MobileCanvas), matching: find.byType(Material));
      expect(tester.widget<Material>(canvas.first).color, MobileTheme.canvas);
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('keeps the quiet phone canvas when material effects are flat',
        (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.flat);

      await tester.pumpWidget(
        const MaterialApp(
          home: NexusBackground(
            child: Text('Content'),
          ),
        ),
      );

      final canvas = find.descendant(
          of: find.byType(MobileCanvas), matching: find.byType(Material));
      expect(tester.widget<Material>(canvas.first).color, MobileTheme.canvas);
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.text('Content'), findsOneWidget);
    });
  });

  group('NexusMetricTile liquid glass behavior', () {
    testWidgets('uses a readable solid data surface in liquid mode',
        (tester) async {
      await AppAppearanceController.setGlassIntensityMode(
          GlassIntensity.liquid);

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
    testWidgets('mobile sheet stays solid in liquid mode', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(
          GlassIntensity.liquid);

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
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Sheet Content'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ChatCatalogDrawer liquid glass integration', () {
    testWidgets('renders LiquidGlass in liquid mode', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(
          GlassIntensity.liquid);

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
      expect(
          find.descendant(
              of: find.byType(ChatCatalogDrawer),
              matching: find.byType(LiquidGlass)),
          findsNothing);
    });
  });
}
