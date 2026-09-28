// L5：详情页容器变换（从被点击的卡片展开）+ 返回手势线性跟手。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/nexus_page_route_factory.dart';
import 'package:mobile_agent/presentation/motion/tap_origin.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

late NexusPageRoute<void> _route;

Widget _app({MotionLevel level = MotionLevel.full}) => MaterialApp(
      theme: AppTheme.light(),
      builder: (context, c) => MotionTierScope(
        controller: MotionTierController(initial: MotionTier.high),
        child: NexusMotionScope(level: level, child: c!),
      ),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 5; i++)
                SizedBox(
                  height: 80,
                  child: GestureDetector(
                    onTap: () {
                      _route = NexusPageRoute<void>.detail(
                        builder: (_) =>
                            const Scaffold(body: Text('detail page')),
                      );
                      Navigator.of(ctx).push(_route);
                    },
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      color: const Color(0xFFDDE3FF),
                      child: Text('card $i'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

Finder get _window => find
    .ancestor(of: find.text('detail page'), matching: find.byType(ClipRRect))
    .first;

void main() {
  setUp(NexusTapOrigin.ensureInstalled);
  tearDown(NexusTapOrigin.reset);

  testWidgets('点击卡片：详情页从卡片矩形展开到全屏，下层不视差位移', (tester) async {
    await tester.pumpWidget(_app());
    final card = tester.getRect(find
        .ancestor(of: find.text('card 2'), matching: find.byType(Container))
        .first);
    final home0 = tester.getTopLeft(find.text('card 0'));
    await tester.tap(find.text('card 2'));
    final origin = _route.originRect!;
    expect(origin.height, lessThan(100));
    expect(origin.overlaps(card), isTrue);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = tester.getRect(_window);
    expect(mid.height, greaterThan(origin.height));
    expect(mid.height, lessThan(600));
    expect(mid.top, lessThan(origin.top));
    expect(tester.getTopLeft(find.text('card 0')).dx, closeTo(home0.dx, 0.5));

    await tester.pumpAndSettle();
    expect(tester.getRect(_window), const Rect.fromLTWH(0, 0, 800, 600));
    expect(find.text('detail page'), findsOneWidget);

    Navigator.of(tester.element(find.text('detail page'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(_window).height, lessThan(600));
    await tester.pumpAndSettle();
    expect(find.text('detail page'), findsNothing);
    expect(find.text('card 2'), findsOneWidget);
  });

  testWidgets('落定前后页面状态保留（结构不变，不重建）', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('card 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final before = tester.element(find.text('detail page'));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('detail page')), same(before));
  });

  testWidgets('没有新鲜点击时退回整屏左右位移', (tester) async {
    await tester.pumpWidget(_app());
    var now = Duration.zero;
    NexusTapOrigin.clock = () => now;
    NexusTapOrigin.record(const Offset(100, 100));
    now += const Duration(seconds: 5);
    final ctx = tester.element(find.text('card 0'));
    final route = NexusPageRoute<void>.detail(
      builder: (_) => const Scaffold(body: Text('detail page')),
    );
    expect(route.originRect, isNull);
    Navigator.of(ctx).push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
        find.ancestor(
            of: find.text('detail page'),
            matching: find.byType(SlideTransition)),
        findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('系统返回手势进行中页面按进度线性跟手，取消后回到原位', (tester) async {
    await tester.pumpWidget(_app());
    NexusTapOrigin.reset();
    final ctx = tester.element(find.text('card 0'));
    final route = NexusPageRoute<void>.detail(
      builder: (_) => const Scaffold(body: Text('detail page')),
    );
    Navigator.of(ctx).push(route);
    await tester.pumpAndSettle();

    route.handleStartBackGesture();
    route.handleUpdateBackGestureProgress(progress: 0.3);
    await tester.pump();
    final value = route.animation!.value;
    expect(value, lessThan(1));
    final dx = tester.getTopLeft(find.text('detail page')).dx;
    expect(dx, closeTo((1 - value) * 800, 1.5));

    route.handleCancelBackGesture();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('detail page')).dx, closeTo(0, 0.5));
  });

  testWidgets('reduced 下不做容器变换', (tester) async {
    await tester.pumpWidget(_app(level: MotionLevel.reduced));
    await tester.tap(find.text('card 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
        find.ancestor(
            of: find.text('detail page'),
            matching: find.byWidgetPredicate(
                (w) => w is ClipRRect && w.clipBehavior == Clip.antiAlias)),
        findsNothing);
    await tester.pumpAndSettle();
  });
}
