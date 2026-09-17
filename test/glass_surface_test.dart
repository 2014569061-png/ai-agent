import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/glass_surface.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';

void main() {
  setUp(() {
    AppAppearanceController.glassIntensity.value = 0.85;
  });

  testWidgets('semantic glass surface renders and responds to interaction',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: GlassSurface(
            role: GlassRole.control,
            variant: GlassVariant.prominent,
            interactive: true,
            onTap: () => tapped = true,
            child: const SizedBox(
              width: 180,
              height: 56,
              child: Text('Run'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(LiquidGlass), findsOneWidget);
    await tester.tap(find.text('Run'));
    expect(tapped, isTrue);
  });

  testWidgets('pressing a glass surface does not rebuild its backdrop filter',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: GlassSurface(
            interactive: true,
            onTap: () {},
            child: const SizedBox(
              width: 180,
              height: 56,
              child: Text('Press me'),
            ),
          ),
        ),
      ),
    );

    final before = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
    await tester.press(find.text('Press me'));
    await tester.pump();
    final during = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
    await tester.pump(const Duration(milliseconds: 140));
    final after = tester.widget<LiquidGlass>(find.byType(LiquidGlass));

    expect(identical(before, during), isTrue);
    expect(identical(before, after), isTrue);
    expect(
      find.ancestor(
        of: find.byType(LiquidGlass),
        matching: find.byType(AnimatedScale),
      ),
      findsNothing,
    );
  });

  testWidgets('semantic glass surface honors reduced motion', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: GlassSurface(
              interactive: true,
              onTap: () {},
              child: const SizedBox(width: 180, height: 56),
            ),
          ),
        ),
      ),
    );

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flat intensity uses an opaque fallback', (tester) async {
    AppAppearanceController.glassIntensity.value = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: GlassSurface(
            intensity: GlassIntensity.flat,
            child: SizedBox(width: 180, height: 56),
          ),
        ),
      ),
    );

    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(Container), findsWidgets);
  });
}
