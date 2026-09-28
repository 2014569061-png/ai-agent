// L4：抽屉跟手（橡皮筋、速度吸附、内容下拉接管）+ 对话框自点击处长出。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/tap_origin.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_sheet.dart';

Widget _host(Widget child, {MotionLevel level = MotionLevel.full}) =>
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, c) => MotionTierScope(
        controller: MotionTierController(initial: MotionTier.high),
        child: NexusMotionScope(level: level, child: c!),
      ),
      home: Scaffold(body: child),
    );

const _body = Key('sheet_body');

Widget _sheetHost({WidgetBuilder? builder}) => _host(Builder(
      builder: (ctx) => Center(
        child: TextButton(
          onPressed: () => showNexusSheet<void>(
            context: ctx,
            builder: builder ??
                (_) => const SizedBox(
                      key: _body,
                      height: 200,
                      child: Text('sheet body'),
                    ),
          ),
          child: const Text('open'),
        ),
      ),
    ));

Future<double> _openSheet(WidgetTester tester, {WidgetBuilder? builder}) async {
  await tester.pumpWidget(_sheetHost(builder: builder));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.getTopLeft(find.byKey(_body)).dy;
}

/// 从拖拽条（内容上方约 8px）开始的慢速手势。
Future<TestGesture> _grabHandle(WidgetTester tester) async {
  final top = tester.getRect(find.byKey(_body)).topCenter;
  final gesture = await tester.startGesture(top - const Offset(0, 8));
  return gesture;
}

Future<void> _move(WidgetTester tester, TestGesture g, double dy,
    {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  tearDown(NexusTapOrigin.reset);

  group('NexusTapOrigin', () {
    test('只采信新鲜的按下位置', () {
      var now = Duration.zero;
      NexusTapOrigin.clock = () => now;
      NexusTapOrigin.record(const Offset(10, 20));
      expect(NexusTapOrigin.recent(), const Offset(10, 20));
      now += NexusTapOrigin.freshness + const Duration(milliseconds: 1);
      expect(NexusTapOrigin.recent(), isNull);
    });

    test('全局点换算为全屏 Alignment 并夹紧', () {
      const size = Size(400, 800);
      expect(NexusTapOrigin.alignmentIn(size, null), Alignment.center);
      expect(NexusTapOrigin.alignmentIn(size, const Offset(0, 800)),
          const Alignment(-1, 1));
      expect(NexusTapOrigin.alignmentIn(size, const Offset(200, 400)),
          Alignment.center);
      expect(NexusTapOrigin.alignmentIn(size, const Offset(-50, 900)),
          const Alignment(-1, 1));
    });
  });

  group('抽屉跟手', () {
    testWidgets('下拉跟手，未过阈值松手后弹簧回到原位', (tester) async {
      final rest = await _openSheet(tester);
      final g = await _grabHandle(tester);
      await _move(tester, g, 70);
      final dragged = tester.getTopLeft(find.byKey(_body)).dy;
      expect(dragged - rest, greaterThan(30));
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final returning = tester.getTopLeft(find.byKey(_body)).dy;
      expect(returning, lessThan(dragged));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, closeTo(rest, 0.5));
      expect(find.byKey(_body), findsOneWidget);
    });

    testWidgets('向上拖过静止位：橡皮筋阻尼，位移有上限', (tester) async {
      final rest = await _openSheet(tester);
      final g = await _grabHandle(tester);
      await _move(tester, g, -260, steps: 13);
      final up = rest - tester.getTopLeft(find.byKey(_body)).dy;
      expect(up, greaterThan(4));
      expect(up, lessThan(36));
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, closeTo(rest, 0.5));
    });

    testWidgets('下拉超过阈值松手即关闭', (tester) async {
      await _openSheet(tester);
      final g = await _grabHandle(tester);
      await _move(tester, g, 180, steps: 12);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsNothing);
    });

    testWidgets('快速下甩即使位移很小也关闭', (tester) async {
      await _openSheet(tester);
      final top = tester.getRect(find.byKey(_body)).topCenter;
      await tester.flingFrom(
          top - const Offset(0, 8), const Offset(0, 60), 1600);
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsNothing);
    });

    testWidgets('内容滚到顶后继续下拉，由抽屉接管跟手', (tester) async {
      const list = Key('sheet_list');
      final rest = await _openSheet(tester,
          builder: (_) => ListView(
                key: list,
                shrinkWrap: true,
                children: [
                  const SizedBox(key: _body, height: 1),
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 40, child: Text('row $i')),
                ],
              ));
      final g = await tester.startGesture(tester.getCenter(find.text('row 2')));
      await _move(tester, g, 90);
      expect(tester.getTopLeft(find.byKey(_body)).dy - rest, greaterThan(20));
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, closeTo(rest, 0.5));
    });
  });

  group('对话框自点击处长出', () {
    Widget dialogHost() => _host(Builder(
          builder: (ctx) => Align(
            alignment: Alignment.bottomLeft,
            child: TextButton(
              onPressed: () => showNexusDialog<void>(
                context: ctx,
                builder: (_) => const AlertDialog(content: Text('hello')),
              ),
              child: const Text('open'),
            ),
          ),
        ));

    ScaleTransition nearestScale(WidgetTester tester) =>
        tester.widget<ScaleTransition>(find
            .ancestor(
                of: find.text('hello'), matching: find.byType(ScaleTransition))
            .first);

    testWidgets('从左下角的按钮处放大长出并落定到 1', (tester) async {
      NexusTapOrigin.ensureInstalled();
      await tester.pumpWidget(dialogHost());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final early = nearestScale(tester);
      expect(early.alignment.x, lessThan(-0.5));
      expect(early.alignment.y, greaterThan(0.5));
      expect(early.scale.value, lessThan(0.95));
      await tester.pumpAndSettle();
      expect(nearestScale(tester).scale.value, closeTo(1, 1e-6));
    });

    testWidgets('没有新鲜的点击位置时居中放大', (tester) async {
      NexusTapOrigin.ensureInstalled();
      await tester.pumpWidget(dialogHost());
      var now = Duration.zero;
      NexusTapOrigin.clock = () => now;
      await tester.tap(find.text('open'));
      // tap 已记录；把时钟拨过有效期再触发弹窗构建前的读取不可行，
      // 因此改为：先关掉，再用过期时钟重开。
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('hello'))).pop();
      await tester.pumpAndSettle();
      now += const Duration(seconds: 5);
      final ctx = tester.element(find.text('open'));
      unawaited(showNexusDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(content: Text('hello')),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(nearestScale(tester).alignment, Alignment.center);
      await tester.pumpAndSettle();
    });

    testWidgets('reduced 下无缩放直接出现', (tester) async {
      await tester.pumpWidget(_host(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showNexusDialog<void>(
              context: ctx,
              builder: (_) => const AlertDialog(content: Text('hello')),
            ),
            child: const Text('open'),
          ),
        ),
        level: MotionLevel.reduced,
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
          find.ancestor(
              of: find.text('hello'), matching: find.byType(ScaleTransition)),
          findsNothing);
      await tester.pumpAndSettle();
    });
  });
}
