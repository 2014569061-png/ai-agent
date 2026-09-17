import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';
import 'package:mobile_agent/presentation/widgets/liquid_segmented_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppAppearanceController.load();
  });

  group('LiquidSegmentedControl widget tests', () {
    testWidgets('renders all segments and highlights selected one in liquid mode',
        (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      String current = 'chat';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: LiquidSegmentedControl<String>(
                  segments: const [
                    LiquidSegment(value: 'chat', label: '聊天'),
                    LiquidSegment(value: 'agent', label: 'Agent'),
                    LiquidSegment(value: 'plan', label: '计划'),
                  ],
                  selected: current,
                  onSelected: (val) => current = val,
                ),
              ),
            ),
          ),
        ),
      );

      // Verify labels are rendered
      expect(find.text('聊天'), findsWidgets);
      expect(find.text('Agent'), findsWidgets);
      expect(find.text('计划'), findsWidgets);

      // In liquid mode, LiquidGlass thumb must be rendered
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('tapping segment triggers onSelected callback and animates',
        (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      String current = 'chat';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return LiquidSegmentedControl<String>(
                      segments: const [
                        LiquidSegment(value: 'chat', label: '聊天'),
                        LiquidSegment(value: 'agent', label: 'Agent'),
                        LiquidSegment(value: 'plan', label: '计划'),
                      ],
                      selected: current,
                      onSelected: (val) {
                        setState(() => current = val);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Tap on 'Agent'
      await tester.tap(find.text('Agent').first);
      // Pump during mid-animation (verifying stretch and transition)
      await tester.pump(const Duration(milliseconds: 100));
      expect(current, 'agent');

      // Finish animation
      await tester.pump(const Duration(milliseconds: 300));
      expect(current, 'agent');
    });

    testWidgets('selection animation keeps the glass thumb instance stable',
        (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.liquid);

      var current = 'chat';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LiquidSegmentedControl<String>(
                segments: const [
                  LiquidSegment(value: 'chat', label: '聊天'),
                  LiquidSegment(value: 'agent', label: 'Agent'),
                ],
                selected: current,
                onSelected: (value) => setState(() => current = value),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Agent'));
      await tester.pump();
      final animationStart = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
      await tester.pump(const Duration(milliseconds: 100));
      final animationMiddle = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
      await tester.pump(const Duration(milliseconds: 220));
      final animationEnd = tester.widget<LiquidGlass>(find.byType(LiquidGlass));

      expect(identical(animationStart, animationMiddle), isTrue);
      expect(identical(animationStart, animationEnd), isTrue);
    });

    testWidgets('degrades to flat container in flat mode', (tester) async {
      await AppAppearanceController.setGlassIntensityMode(GlassIntensity.flat);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: LiquidSegmentedControl<String>(
                  segments: const [
                    LiquidSegment(value: 'chat', label: '聊天'),
                    LiquidSegment(value: 'agent', label: 'Agent'),
                  ],
                  selected: 'chat',
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // In flat mode, LiquidGlass should not be used
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.text('聊天'), findsWidgets);
      expect(find.text('Agent'), findsWidgets);
    });
  });
}
