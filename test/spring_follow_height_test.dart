// L3：流式增高弹簧追随 + 展开区弹簧形变。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/motion/spring_follow_height.dart';
import 'package:mobile_agent/presentation/widgets/nexus_disclosure.dart';

Widget _host(Widget child, {MotionLevel level = MotionLevel.full}) =>
    MaterialApp(
      builder: (context, c) => MotionTierScope(
        controller: MotionTierController(initial: MotionTier.high),
        child: NexusMotionScope(level: level, child: c!),
      ),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
    );

const _box = Key('follow');

Widget _follow(double height, {bool enabled = true}) => SpringFollowHeight(
      key: _box,
      enabled: enabled,
      child: SizedBox(width: 200, height: height),
    );

double _h(WidgetTester tester) => tester.getSize(find.byKey(_box)).height;

void main() {
  testWidgets('内容增高时高度弹簧追随，而非一步跳到位', (tester) async {
    await tester.pumpWidget(_host(_follow(40)));
    expect(_h(tester), 40);
    await tester.pumpWidget(_host(_follow(200)));
    expect(_h(tester), 40, reason: '变化当帧仍保持旧高度，帧后起跳');
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = _h(tester);
    expect(mid, greaterThan(40));
    expect(mid, lessThan(200));
    await tester.pumpAndSettle();
    expect(_h(tester), 200);
  });

  testWidgets('动画途中再次增高：从当前高度继续，不回退不跳变', (tester) async {
    await tester.pumpWidget(_host(_follow(40)));
    await tester.pumpWidget(_host(_follow(200)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final before = _h(tester);
    await tester.pumpWidget(_host(_follow(320)));
    final same = _h(tester);
    expect(same, closeTo(before, 12));
    await tester.pump(const Duration(milliseconds: 16));
    final after = _h(tester);
    expect(after, greaterThanOrEqualTo(same));
    expect(after, lessThan(320));
    await tester.pumpAndSettle();
    expect(_h(tester), 320);
  });

  testWidgets('enabled=false 或动效关闭时高度即时等于内容', (tester) async {
    await tester.pumpWidget(_host(_follow(40, enabled: false)));
    await tester.pumpWidget(_host(_follow(200, enabled: false)));
    expect(_h(tester), 200);

    await tester.pumpWidget(_host(_follow(40), level: MotionLevel.off));
    await tester.pumpWidget(_host(_follow(260), level: MotionLevel.off));
    expect(_h(tester), 260);
  });

  testWidgets('显示高度小于内容时裁剪底部，落定后不再裁剪', (tester) async {
    await tester.pumpWidget(_host(_follow(40)));
    await tester.pumpWidget(_host(_follow(200)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 40));
    final render =
        tester.renderObject<RenderSpringFollowHeight>(find.byKey(_box));
    expect(render.describeApproximatePaintClip(render.child!), isNotNull);
    await tester.pumpAndSettle();
    expect(render.describeApproximatePaintClip(render.child!), isNull);
  });

  Widget section(bool expanded, {MotionLevel level = MotionLevel.full}) =>
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NexusExpandSection(
              key: _box,
              expanded: expanded,
              child: const SizedBox(width: 200, height: 120),
            ),
          ],
        ),
        level: level,
      );

  testWidgets('NexusExpandSection 展开以弹簧形变增高', (tester) async {
    await tester.pumpWidget(section(false));
    expect(_h(tester), 0);
    await tester.pumpWidget(section(true));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = _h(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(120));
    await tester.pumpAndSettle();
    expect(_h(tester), 120);
  });

  testWidgets('NexusExpandSection 在 reduced 下即时切换', (tester) async {
    await tester.pumpWidget(section(false, level: MotionLevel.reduced));
    await tester.pumpWidget(section(true, level: MotionLevel.reduced));
    await tester.pump();
    expect(_h(tester), 120);
  });
}
