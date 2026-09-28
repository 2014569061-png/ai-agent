// L6 追加：弹簧开关。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_switch.dart';

Widget _host(Widget Function(bool value, ValueChanged<bool> set) build,
    {bool initial = false}) {
  var value = initial;
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, c) => MotionTierScope(
      controller: MotionTierController(initial: MotionTier.high),
      child: NexusMotionScope(level: MotionLevel.full, child: c!),
    ),
    home: Scaffold(
      body: Center(
        child: StatefulBuilder(
          builder: (context, setState) =>
              build(value, (v) => setState(() => value = v)),
        ),
      ),
    ),
  );
}

double _thumbX(WidgetTester tester) =>
    tester.getCenter(find.byKey(const ValueKey('nexus_switch_thumb'))).dx;

void main() {
  testWidgets('点击切换：滑块弹簧滑到另一端并带一次轻回弹', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host((v, set) => NexusSwitch(
          value: v,
          onChanged: (n) {
            calls++;
            set(n);
          },
        )));
    final off = _thumbX(tester);
    await tester.tap(find.byType(NexusSwitch));
    await tester.pump();
    var maxX = 0.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final x = _thumbX(tester);
      if (x > maxX) maxX = x;
    }
    await tester.pumpAndSettle();
    final on = _thumbX(tester);
    expect(calls, 1);
    expect(
        on - off, closeTo(NexusSwitch.trackWidth - NexusSwitch.trackHeight, 1));
    expect(maxX, greaterThan(on + 0.3), reason: '到位前应略微越过终点');
  });

  testWidgets('禁用时点击无回调', (tester) async {
    await tester.pumpWidget(
        _host((v, set) => const NexusSwitch(value: false, onChanged: null)));
    await tester.tap(find.byType(NexusSwitch));
    await tester.pumpAndSettle();
    expect(tester.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isFalse);
  });

  testWidgets('NexusSwitchListTile 整行可点', (tester) async {
    await tester.pumpWidget(_host((v, set) => NexusSwitchListTile(
          value: v,
          onChanged: set,
          title: const Text('自动保存'),
        )));
    await tester.tap(find.text('自动保存'));
    await tester.pumpAndSettle();
    expect(tester.widget<NexusSwitch>(find.byType(NexusSwitch)).value, isTrue);
  });
}
