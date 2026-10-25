import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_tokens.dart';
import 'package:mobile_agent/presentation/theme/desktop_focus_ring.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

void main() {
  group('DesktopTheme High Contrast & Accessibility', () {
    test('highContrastLight 提供极端清晰对比度', () {
      final hc = DesktopTheme.highContrastLight;
      expect(hc.text, const Color(0xFF000000));
      expect(hc.border, const Color(0xFF000000));
      expect(hc.canvas, const Color(0xFFFFFFFF));
    });

    test('highContrastDark 提供极端清晰反色对比度', () {
      final hc = DesktopTheme.highContrastDark;
      expect(hc.text, const Color(0xFFFFFFFF));
      expect(hc.border, const Color(0xFFFFFFFF));
      expect(hc.canvas, const Color(0xFF000000));
    });

    testWidgets('DesktopTheme.of 依据 MediaQuery.highContrast 自动切换',
        (tester) async {
      late DesktopTheme capturedNormal;
      late DesktopTheme capturedHC;

      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopTheme.apply(ThemeData.light()),
          home: Builder(builder: (context) {
            capturedNormal = DesktopTheme.of(context);
            return const SizedBox();
          }),
        ),
      );

      expect(capturedNormal.text, DesktopTheme.light.text);

      // 高对比度 MediaQuery
      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopTheme.apply(ThemeData.light()),
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: Builder(builder: (context) {
              capturedHC = DesktopTheme.of(context);
              return const SizedBox();
            }),
          ),
        ),
      );

      expect(capturedHC.text, DesktopTheme.highContrastLight.text);
      expect(capturedHC.border, const Color(0xFF000000));
    });
  });

  group('Motion Lively Reduce Motion Policy', () {
    testWidgets('系统开启减弱动效时 motionDuration 降级为 Duration.zero', (tester) async {
      late Duration normalDuration;
      late Duration reducedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            normalDuration = DesktopTheme.motionDuration(
                context, AppTokens.durationPage);
            return const SizedBox();
          }),
        ),
      );

      expect(normalDuration, AppTokens.durationPage);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(builder: (context) {
              reducedDuration = DesktopTheme.motionDuration(
                  context, AppTokens.durationPage);
              return const SizedBox();
            }),
          ),
        ),
      );

      expect(reducedDuration, Duration.zero);
    });
  });

  group('DesktopFocusRing Focus Visible WCAG 2.1', () {
    testWidgets('控件获焦时渲染 2px 高对比外圈轮廓线', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopTheme.apply(ThemeData.light()),
          home: Scaffold(
            body: Center(
              child: DesktopFocusRing(
                focusNode: focusNode,
                child: const Text('Focus Target'),
              ),
            ),
          ),
        ),
      );

      // 初始未聚焦，边框透明
      final initialBox = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      final initialDec = initialBox.decoration as BoxDecoration;
      expect((initialDec.border as Border).top.color, Colors.transparent);

      // 获取焦点
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      // 聚焦后渲染 accent 边框
      final focusedBox = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      final focusedDec = focusedBox.decoration as BoxDecoration;
      final borderSide = (focusedDec.border as Border).top;
      expect(borderSide.color, DesktopTheme.light.accent);
      expect(borderSide.width, 2.0);
    });

    testWidgets('支持键盘点击与语义标签', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopTheme.apply(ThemeData.light()),
          home: Scaffold(
            body: Center(
              child: DesktopFocusRing(
                semanticLabel: '会话操作按钮',
                onTap: () => tapped = true,
                child: const Text('Action'),
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('会话操作按钮'), findsOneWidget);
      await tester.tap(find.text('Action'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
