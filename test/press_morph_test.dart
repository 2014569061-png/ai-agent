// L1 触感：按压压缩回弹（PressSquash / PressScale / 全局按钮样式）与图标形变。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/morph_icon.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/press_squash.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

Widget _app(Widget child, {MotionLevel level = MotionLevel.full}) =>
    MaterialApp(
      theme: AppTheme.light(),
      home: NexusMotionScope(
        level: level,
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _scaleIn(WidgetTester tester, Finder host) {
  final t = tester.widget<Transform>(
      find.descendant(of: host, matching: find.byType(Transform)).first);
  return t.transform.entry(0, 0);
}

void main() {
  const box = SizedBox(width: 120, height: 48, child: Text('Tap'));

  testWidgets('PressSquash：按下压缩，松手越过 1.0 回弹后落定，点击照常触发', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(PressSquash(
      scale: NexusPressScale.card,
      child: InkWell(onTap: () => taps++, child: box),
    )));
    final host = find.byType(PressSquash);
    expect(_scaleIn(tester, host), 1);

    final gesture = await tester.startGesture(tester.getCenter(host));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_scaleIn(tester, host), closeTo(NexusPressScale.card, 0.003));

    await gesture.up();
    var peak = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      peak = math.max(peak, _scaleIn(tester, host));
    }
    expect(peak, greaterThan(1.001));
    await tester.pumpAndSettle();
    expect(_scaleIn(tester, host), closeTo(1, 0.001));
    expect(taps, 1);
  });

  testWidgets('PressSquash：手指移动超过 touch slop（开始滚动）即取消压缩', (tester) async {
    await tester.pumpWidget(_app(const PressSquash(child: box)));
    final host = find.byType(PressSquash);
    final gesture = await tester.startGesture(tester.getCenter(host));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_scaleIn(tester, host), lessThan(1));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(_scaleIn(tester, host), closeTo(1, 0.001));
    await gesture.up();
  });

  testWidgets('PressSquash：reduced / disabled 下不缩放', (tester) async {
    for (final w in [
      _app(const PressSquash(child: box), level: MotionLevel.reduced),
      _app(const PressSquash(enabled: false, child: box)),
    ]) {
      await tester.pumpWidget(w);
      final host = find.byType(PressSquash);
      final gesture = await tester.startGesture(tester.getCenter(host));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scaleIn(tester, host), 1);
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('主题按钮：FilledButton / IconButton 按下时前景压缩', (tester) async {
    for (final button in <Widget>[
      FilledButton(onPressed: () {}, child: const Text('Go')),
      IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
    ]) {
      await tester.pumpWidget(_app(button));
      final host = find.byType(PressScale);
      expect(host, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(host));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<PressScale>(host).pressed, isTrue);
      expect(_scaleIn(tester, host), lessThan(0.97));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleIn(tester, host), closeTo(1, 0.001));
    }
  });

  test('NexusPressStyle.apply 保留调用方自定义的 foregroundBuilder', () {
    Widget custom(BuildContext c, Set<WidgetState> s, Widget? child) => child!;
    final own = ButtonStyle(foregroundBuilder: custom);
    expect(NexusPressStyle.apply(own).foregroundBuilder, same(custom));
    expect(NexusPressStyle.apply(const ButtonStyle()).foregroundBuilder,
        isNotNull);
  });

  testWidgets('MorphIcon：切换时新旧图标叠放过渡，落定后只剩新图标', (tester) async {
    Widget build(bool done) =>
        _app(MorphIcon(done ? Icons.check_rounded : Icons.copy_rounded));
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('MorphIcon：off 下直接切换', (tester) async {
    Widget build(bool done) =>
        _app(MorphIcon(done ? Icons.check_rounded : Icons.copy_rounded),
            level: MotionLevel.off);
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pump();
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testWidgets('SpringTurns：翻转到半圈，过程中带回弹', (tester) async {
    Widget build(double turns) =>
        _app(SpringTurns(turns: turns, child: const Icon(Icons.expand_more)));
    double angle() {
      final t = tester.widget<Transform>(find
          .ancestor(
              of: find.byIcon(Icons.expand_more),
              matching: find.byType(Transform))
          .first);
      return math.atan2(t.transform.entry(1, 0), t.transform.entry(0, 0));
    }

    await tester.pumpWidget(build(0));
    await tester.pumpWidget(build(0.25));
    var peak = 0.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      peak = math.max(peak, angle());
    }
    expect(peak, greaterThan(math.pi / 2 + 0.02));
    await tester.pumpAndSettle();
    expect(angle(), closeTo(math.pi / 2, 0.01));
  });
}
