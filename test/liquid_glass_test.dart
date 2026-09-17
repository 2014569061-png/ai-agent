import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_tokens.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';

/// 把玻璃面板放进一个可确定尺寸的容器，便于断言滤镜与圆角。
Future<void> pumpGlass(
  WidgetTester tester, {
  required Key key,
  GlassIntensity intensity = GlassIntensity.liquid,
  double blurSigma = 12,
  bool outlined = true,
  Color? tint,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 120,
            child: LiquidGlass(
              key: key,
              intensity: intensity,
              blurSigma: blurSigma,
              outlined: outlined,
              tint: tint,
              padding: const EdgeInsets.all(8),
              child: const Text('玻璃'),
            ),
          ),
        ),
      ),
    ),
  );
}

BoxDecoration decorationOf(WidgetTester tester, Key key) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)),
  );
  return box.decoration as BoxDecoration;
}

void main() {
  setUp(LiquidGlass.resetShaderCache);

  testWidgets('flat intensity renders without any backdrop filter',
      (tester) async {
    final key = const ValueKey('flat');
    await pumpGlass(tester, key: key, intensity: GlassIntensity.flat);

    expect(find.text('玻璃'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(key), matching: find.byType(BackdropFilter)),
      findsNothing,
    );
  });

  testWidgets('frosted intensity blurs the backdrop with the given sigma',
      (tester) async {
    final key = const ValueKey('frosted');
    await pumpGlass(
      tester,
      key: key,
      intensity: GlassIntensity.frosted,
      blurSigma: 7,
    );

    final backdrop = tester.widget<BackdropFilter>(
      find.descendant(of: find.byKey(key), matching: find.byType(BackdropFilter)),
    );
    expect(
      backdrop.filter,
      ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7, tileMode: ui.TileMode.clamp),
    );
  });

  testWidgets('liquid intensity degrades to blur when shaders are unavailable',
      (tester) async {
    // 前置条件：flutter_tester 走 Skia，ImageFilter.shader 不可用。
    // 若将来测试运行器启用 Impeller，这条断言会先失败，提示需要改测折射分支，
    // 而不是让本用例静默地什么都没验证。
    expect(ui.ImageFilter.isShaderFilterSupported, isFalse);

    final key = const ValueKey('liquid');
    await pumpGlass(
      tester,
      key: key,
      intensity: GlassIntensity.liquid,
      blurSigma: 9,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('玻璃'), findsOneWidget);

    final backdrop = tester.widget<BackdropFilter>(
      find.descendant(of: find.byKey(key), matching: find.byType(BackdropFilter)),
    );
    // 降级路径必须产出可用的高斯模糊，而不是空滤镜或抛异常。
    expect(
      backdrop.filter,
      ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9, tileMode: ui.TileMode.clamp),
    );
  });

  testWidgets('glass panel is clipped to the modal radius by default',
      (tester) async {
    final key = const ValueKey('radius');
    await pumpGlass(tester, key: key);

    final clip = tester.widget<ClipRRect>(
      find.descendant(of: find.byKey(key), matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, BorderRadius.circular(AppTokens.radiusModal));
  });

  testWidgets('flat intensity keeps the hairline border, glass uses a rim',
      (tester) async {
    final flatKey = const ValueKey('flat-border');
    await pumpGlass(tester, key: flatKey, intensity: GlassIntensity.flat);
    final flatBorder = decorationOf(tester, flatKey).border as Border;
    expect(flatBorder.top.color, isNot(const Color(0x66FFFFFF)));

    final glassKey = const ValueKey('glass-border');
    await pumpGlass(tester, key: glassKey, intensity: GlassIntensity.frosted);
    final glassBorder = decorationOf(tester, glassKey).border as Border;
    expect(glassBorder.top.color, const Color(0x66FFFFFF));
  });

  testWidgets('outlined false removes the border entirely', (tester) async {
    final key = const ValueKey('no-border');
    await pumpGlass(tester, key: key, outlined: false);

    expect(decorationOf(tester, key).border, isNull);
  });

  testWidgets('explicit tint overrides the default film colour',
      (tester) async {
    final key = const ValueKey('tint');
    await pumpGlass(tester, key: key, tint: const Color(0xFF123456));

    expect(decorationOf(tester, key).color, const Color(0xFF123456));
  });
}
