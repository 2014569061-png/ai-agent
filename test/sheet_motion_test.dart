// L4：抽屉跟手（橡皮筋、速度吸附、内容下拉接管）+ 对话框自点击处长出。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/mobile_motion.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/tap_origin.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
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

Widget _sheetHost({
  WidgetBuilder? builder,
  bool barrierDismissible = true,
  MotionLevel level = MotionLevel.full,
}) =>
    _host(
        Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () => showNexusSheet<void>(
                context: ctx,
                barrierDismissible: barrierDismissible,
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
        ),
        level: level);

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

  testWidgets('手机面板移动时复用内容绘制，不重复重绘静态列表', (tester) async {
    var paints = 0;
    await tester.pumpWidget(_sheetHost(
      builder: (_) => CustomPaint(
        painter: _PaintCounter(() => paints++),
        child: const SizedBox(key: _body, height: 200),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final firstPaints = paints;
    final top = tester.getTopLeft(find.byKey(_body)).dy;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(firstPaints, greaterThan(0));
    expect(tester.getTopLeft(find.byKey(_body)).dy, lessThan(top));
    expect(paints, firstPaints);
    await tester.pumpAndSettle();
  });

  for (final dark in [false, true]) {
    testWidgets('手机${dark ? '深色' : '浅色'}面板不跟随全局玻璃设置创建背景滤镜', (tester) async {
      final previous = AppAppearanceController.glassIntensity.value;
      addTearDown(
          () => AppAppearanceController.glassIntensity.value = previous);
      AppAppearanceController.glassIntensity.value = .85;
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNexusSheet<void>(
                context: context,
                builder: (_) =>
                    const SizedBox(key: _body, height: 200, child: Text('面板')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      final material = tester
          .widgetList<Material>(
            find.ancestor(
                of: find.byKey(_body), matching: find.byType(Material)),
          )
          .firstWhere((widget) => widget.color?.a == 1);
      final context = tester.element(find.byKey(_body));
      expect(material.color, Theme.of(context).colorScheme.surface);
      expect(
          find.ancestor(
            of: find.byKey(_body),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets);
    });
  }

  testWidgets('弹层尚未进入完就关闭，首帧位置连续并可再次打开', (tester) async {
    await tester.pumpWidget(_sheetHost());
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final before = tester.getTopLeft(find.byKey(_body)).dy;
    Navigator.of(tester.element(find.byKey(_body))).pop();
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_body)).dy, closeTo(before, 0.5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(_body), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机减少动态效果时弹层直接出现与关闭', (tester) async {
    await tester.pumpWidget(_sheetHost(level: MotionLevel.reduced));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byKey(_body)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    Navigator.of(tester.element(find.byKey(_body))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(_body), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('手机弹层进入 240ms、退出 160ms，整个过程不越过落点', (tester) async {
    final rest = await _openSheet(tester);
    final route = ModalRoute.of(tester.element(find.byKey(_body)))!;
    expect(route.transitionDuration, MobileMotion.panelEnter);
    expect(route.reverseTransitionDuration, MobileMotion.panelExit);
    Navigator.of(tester.element(find.byKey(_body))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getTopLeft(find.byKey(_body)).dy,
          greaterThanOrEqualTo(rest - 0.5));
    }
    final closingRoute = ModalRoute.of(tester.element(find.byKey(_body)))!;
    Navigator.of(tester.element(find.byKey(_body))).pop();
    await tester.pump();
    await tester.pump(MobileMotion.panelExit);
    expect(closingRoute.animation!.value, closeTo(0, 0.001));
    await tester.pumpAndSettle();
    expect(find.byKey(_body), findsNothing);
  });

  testWidgets('要求显式确认的面板不能通过遮罩或下甩关闭', (tester) async {
    await tester.pumpWidget(_sheetHost(barrierDismissible: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(_body), findsOneWidget);
    final top = tester.getRect(find.byKey(_body)).topCenter;
    await tester.flingFrom(
        top - const Offset(0, 8), const Offset(0, 180), 1600);
    await tester.pumpAndSettle();
    expect(find.byKey(_body), findsOneWidget);
  });

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

class _PaintCounter extends CustomPainter {
  const _PaintCounter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => false;
}
