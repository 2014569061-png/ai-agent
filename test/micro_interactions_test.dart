// L7：微交互（数字滚动 / 徽章轻弹 / 复制 ✓）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/motion/micro_interactions.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/motion/motion_tier.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      builder: (context, c) => MotionTierScope(
        controller: MotionTierController(initial: MotionTier.high),
        child: NexusMotionScope(level: MotionLevel.full, child: c!),
      ),
      home: Scaffold(body: Center(child: child)),
    );

Finder _popTransform() => find.descendant(
    of: find.byType(PopOnChange), matching: find.byType(Transform));

void main() {
  testWidgets('RollingText：只滚动变化的字符，静止后回到单个 Text', (tester) async {
    await tester.pumpWidget(_host(const RollingText('12')));
    expect(find.text('12'), findsOneWidget);
    await tester.pumpWidget(_host(const RollingText('13')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('1'), findsOneWidget, reason: '未变的十位保持静止');
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('13'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('PopOnChange：触发值变化时先缩小再弹回', (tester) async {
    Widget pop(Object t) =>
        _host(PopOnChange(trigger: t, child: const Text('运行中')));
    await tester.pumpWidget(pop('a'));
    expect(_popTransform(), findsNothing);
    await tester.pumpWidget(pop('b'));
    await tester.pump();
    final scale =
        tester.widget<Transform>(_popTransform()).transform.entry(0, 0);
    expect(scale, lessThan(0.95));
    await tester.pumpAndSettle();
    final settled =
        tester.widget<Transform>(_popTransform()).transform.entry(0, 0);
    expect(settled, closeTo(1, 0.001));
  });

  testWidgets('CopyFeedbackButton：点按形变为 ✓，稍后恢复', (tester) async {
    var copied = 0;
    await tester.pumpWidget(_host(CopyFeedbackButton(onCopy: () => copied++)));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(copied, 1);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pump(CopyFeedbackButton.resetAfter);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });
}
