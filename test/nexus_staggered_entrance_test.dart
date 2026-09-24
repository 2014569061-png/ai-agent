// M3 列表错开入场 + 非聊天列表弹性过界。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';
import 'package:mobile_agent/presentation/motion/nexus_staggered_entrance.dart';

Key _k(int i) => ValueKey('item$i');

Widget _list({
  int count = 12,
  MotionLevel level = MotionLevel.full,
  bool scope = true,
}) {
  final list = ListView.builder(
    physics: NexusMotion.listPhysics,
    itemCount: count,
    itemBuilder: NexusStaggeredItem.wrap(
      (context, index) => SizedBox(
        key: _k(index),
        height: 40,
        child: Text('item $index'),
      ),
    ),
  );
  return MaterialApp(
    builder: (context, child) => NexusMotionScope(level: level, child: child!),
    home: Scaffold(body: scope ? NexusStaggeredEntrance(child: list) : list),
  );
}

double _dy(WidgetTester tester, int i) =>
    tester.getTopLeft(find.byKey(_k(i))).dy - 40.0 * i;

void main() {
  testWidgets('按序错开：前面的项先动，结束后全部到位', (tester) async {
    await tester.pumpWidget(_list());
    await tester.pump(const Duration(milliseconds: 60));
    // item0 已开始（< 12），item3（90ms 起）仍在起点。
    expect(_dy(tester, 0), lessThan(NexusStaggeredItem.offsetY));
    expect(_dy(tester, 3), NexusStaggeredItem.offsetY);
    await tester.pump(NexusStaggeredEntrance.totalDuration);
    for (var i = 0; i < 8; i++) {
      expect(_dy(tester, i), 0);
    }
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('整个列表只有一个 ticker', (tester) async {
    await tester.pumpWidget(_list());
    await tester.pump(const Duration(milliseconds: 16));
    expect(SchedulerBinding.instance.transientCallbackCount, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('第 9 项起不参与入场', (tester) async {
    await tester.pumpWidget(_list());
    await tester.pump(const Duration(milliseconds: 16));
    expect(_dy(tester, 8), 0);
    expect(_dy(tester, 7), NexusStaggeredItem.offsetY);
    await tester.pumpAndSettle();
  });

  testWidgets('重建不重播；滚动中新建的项直接到位', (tester) async {
    await tester.pumpWidget(_list(count: 40));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_list(count: 41));
    await tester.pump();
    expect(_dy(tester, 0), 0);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('玻璃模式（默认）不包 Opacity', (tester) async {
    await tester.pumpWidget(_list());
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      find.ancestor(of: find.byKey(_k(0)), matching: find.byType(Opacity)),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('reduced / off / 无 Scope：直接显示且无 ticker', (tester) async {
    for (final w in [
      _list(level: MotionLevel.reduced),
      _list(level: MotionLevel.off),
      _list(scope: false),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(w);
      await tester.pump();
      expect(_dy(tester, 0), 0);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    }
  });

  testWidgets('弹性过界：拉过顶部后回弹到 0', (tester) async {
    await tester.pumpWidget(_list(count: 3));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, lessThan(0), reason: '内容不足一屏也能弹性下拉');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
  });

  testWidgets('弹性过界下 RefreshIndicator 仍能触发', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => refreshed++,
          child: NexusStaggeredEntrance(
            child: ListView(
              physics: NexusMotion.listPhysics,
              children: const [SizedBox(height: 40, child: Text('a'))],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.fling(find.text('a'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  test('总时长 = 7 × 30ms + 220ms = 430ms', () {
    expect(NexusStaggeredEntrance.totalDuration,
        const Duration(milliseconds: 430));
  });
}
