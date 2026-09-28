// L6：分段控件滑动 + 拉伸指示器。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_segmented_button.dart';

Widget _host({MotionLevel level = MotionLevel.full}) {
  var value = 'a';
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, c) => MotionTierScope(
      controller: MotionTierController(initial: MotionTier.high),
      child: NexusMotionScope(level: level, child: c!),
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: StatefulBuilder(
            builder: (context, setState) => NexusSegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'a', label: Text('甲')),
                ButtonSegment(value: 'b', label: Text('乙')),
                ButtonSegment(value: 'c', label: Text('丙')),
              ],
              selected: {value},
              onSelectionChanged: (s) => setState(() => value = s.first),
            ),
          ),
        ),
      ),
    ),
  );
}

Rect _indicator(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('nexus_segment_indicator')));

void main() {
  testWidgets('切换时指示器滑向目标并在途中拉伸，到位后收回原宽', (tester) async {
    await tester.pumpWidget(_host());
    final rest = _indicator(tester);
    // 300 宽 3 段，减去 1px 描边后每段约 99.3，内缩 3。
    expect(rest.width, closeTo(300 / 3 - 6, 2));
    await tester.tap(find.text('丙'));
    await tester.pump();
    var maxWidth = 0.0;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final w = _indicator(tester).width;
      if (w > maxWidth) maxWidth = w;
    }
    expect(maxWidth, greaterThan(rest.width * 1.2));
    await tester.pumpAndSettle();
    final end = _indicator(tester);
    expect(end.width, closeTo(rest.width, 0.5));
    expect(end.left, greaterThan(rest.left + 150));
  });

  testWidgets('点击已选中的分段不回调；动效关闭时直接到位', (tester) async {
    await tester.pumpWidget(_host(level: MotionLevel.off));
    final rest = _indicator(tester);
    await tester.tap(find.text('甲'));
    await tester.pump();
    expect(_indicator(tester), rest);
    await tester.tap(find.text('乙'));
    await tester.pump();
    await tester.pump();
    expect(_indicator(tester).left, closeTo(rest.left + rest.width + 6, 2));
  });
}
