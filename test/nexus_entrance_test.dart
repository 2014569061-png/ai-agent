// M2 首屏入场编排：NexusEntrance 的时序、去重与分档。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/nexus_entrance.dart';
import 'package:mobile_agent/presentation/motion/nexus_motion.dart';

Widget _host(Widget child, {MotionLevel level = MotionLevel.full}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: NexusMotionScope(
      level: level,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

double _opacityOf(WidgetTester tester, Key key) {
  final opacity = tester.widget<Opacity>(
    find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)).first,
  );
  return opacity.opacity;
}

double _dy(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key)).dy;

void main() {
  setUp(NexusEntrance.debugReset);

  testWidgets('按槽位错开：槽位 1 在 40ms 内保持起点，结束后完全到位', (tester) async {
    const a = Key('a');
    const b = Key('b');
    await tester.pumpWidget(_host(const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NexusEntrance(
          offset: Offset(0, 12),
          child: SizedBox(key: a, width: 10, height: 10),
        ),
        NexusEntrance(
          slot: 1,
          child: SizedBox(key: b, width: 10, height: 10),
        ),
      ],
    )));
    await tester.pump(); // 首帧开始计时
    await tester.pump(const Duration(milliseconds: 30));

    expect(_opacityOf(tester, b), 0, reason: '槽位 1 在 40ms 错开窗口内不应开始');
    expect(_opacityOf(tester, a), greaterThan(0));
    expect(_dy(tester, a), greaterThan(0), reason: '槽位 0 仍在位移途中');

    await tester.pump(NexusMotion.entrance + NexusMotion.entranceStagger);
    expect(_opacityOf(tester, a), 1);
    expect(_opacityOf(tester, b), 1);
    expect(_dy(tester, a), 0);
    expect(SchedulerBinding.instance.transientCallbackCount, 0,
        reason: '播放结束后不得残留 ticker');
  });

  testWidgets('fade: false 时子树外不包 Opacity（玻璃不进透明度缓冲区）', (tester) async {
    const k = Key('glass');
    await tester.pumpWidget(_host(const NexusEntrance(
      offset: Offset(0, -8),
      fade: false,
      child: SizedBox(key: k, width: 10, height: 10),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.ancestor(of: find.byKey(k), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(_dy(tester, k), lessThan(0));
    await tester.pumpAndSettle();
    expect(_dy(tester, k), 0);
  });

  testWidgets('onceId：同一进程只播一次，重新挂载直接到位', (tester) async {
    const k = Key('bar');
    Widget bar() => _host(const NexusEntrance(
          offset: Offset(0, -8),
          fade: false,
          onceId: 'bar',
          child: SizedBox(key: k, width: 10, height: 10),
        ));
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(bar());
    expect(_dy(tester, k), 0);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('重建不重播，且子树状态保留（结构稳定）', (tester) async {
    final controller = TextEditingController(text: 'draft');
    addTearDown(controller.dispose);
    Widget build(double width) => MaterialApp(
          home: Scaffold(
            body: NexusEntrance(
              offset: const Offset(0, 12),
              child: SizedBox(
                  width: width, child: TextField(controller: controller)),
            ),
          ),
        );
    await tester.pumpWidget(build(200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final state = tester.state(find.byType(EditableText));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(220));
    await tester.pump();
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('enabled: false 时直接显示', (tester) async {
    const k = Key('off');
    await tester.pumpWidget(_host(const NexusEntrance(
      enabled: false,
      offset: Offset(0, 12),
      child: SizedBox(key: k, width: 10, height: 10),
    )));
    expect(_dy(tester, k), 0);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('减少动态效果：只淡入 120ms，不位移；fade: false 的元素不动', (tester) async {
    const a = Key('a');
    const b = Key('b');
    await tester.pumpWidget(_host(
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NexusEntrance(
            slot: 3,
            offset: Offset(0, 12),
            child: SizedBox(key: a, width: 10, height: 10),
          ),
          NexusEntrance(
            offset: Offset(0, 12),
            fade: false,
            child: SizedBox(key: b, width: 10, height: 10),
          ),
        ],
      ),
      level: MotionLevel.reduced,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_dy(tester, a), 0, reason: 'reduced 不做位移');
    expect(_opacityOf(tester, a), inExclusiveRange(0.0, 1.0),
        reason: 'reduced 不做错开，立即开始淡入');
    expect(_dy(tester, b), 10);
    await tester.pump(NexusMotion.reducedEntrance);
    expect(_opacityOf(tester, a), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('淡入起点仍保留读屏语义', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const NexusEntrance(
      slot: 1,
      child: Text('今天想构建什么？'),
    )));
    await tester.pump();
    expect(find.bySemanticsLabel('今天想构建什么？'), findsOneWidget);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('关闭动效：直接显示，不创建 ticker', (tester) async {
    const k = Key('k');
    await tester.pumpWidget(_host(
      const NexusEntrance(
        scaleFrom: 0.96,
        child: SizedBox(key: k, width: 10, height: 10),
      ),
      level: MotionLevel.off,
    ));
    expect(
      find.ancestor(of: find.byKey(k), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  test('编排总时长不超过 380ms（顶栏 0 / 主视觉 1 / 卡片 2 / 输入框 3）', () {
    final total = NexusMotion.entranceStagger * 3 + NexusMotion.entrance;
    expect(total, lessThanOrEqualTo(const Duration(milliseconds: 380)));
  });
}
