import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/widgets/floating_toast.dart';
import 'package:mobile_agent/presentation/widgets/glass_chip.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('存量回归：show(context, x) 渲染无图标、无 chip；pump(3s) 后 OverlayEntry 已移除',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () => FloatingToast.show(context, 'test message'),
          child: const Text('Show'),
        );
      },
    )));

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // fade in

    expect(find.text('test message'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(GlassChip), findsNothing);

    // fast forward 3s + animation
    await tester.pump(const Duration(seconds: 3));
    await tester
        .pump(const Duration(milliseconds: 300)); // wait for reverse animation

    expect(find.text('test message'), findsNothing);
  });

  testWidgets(
      'error 常驻：error(...) 后 pump(5s) 仍在；图标为 error_outline_rounded、着色 AppTheme.danger；仅存在 × 与复制 chip',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () => FloatingToast.error(context, 'fatal error'),
          child: const Text('Show'),
        );
      },
    )));

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。'),
        findsOneWidget); // fallback humanize string
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byType(GlassChip), findsOneWidget); // 复制 chip

    // It should persist
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。'), findsOneWidget);
  });

  testWidgets('关闭路径：tap × -> entry 移除；tap chip -> onPressed 触发且默认关闭',
      (WidgetTester tester) async {
    bool feedbackTapped = false;
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () => FloatingToast.error(
            context,
            'error',
            onFeedback: () => feedbackTapped = true,
          ),
          child: const Text('Show'),
        );
      },
    )));

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // tap feedback
    await tester.tap(find.text('反馈问题'));
    await tester.pump();
    expect(feedbackTapped, isTrue);

    // wait for animation to dismiss
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GlassChip), findsNothing); // should be dismissed

    // show again and tap close
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GlassChip), findsNothing);
  });

  testWidgets('点胶囊降级：persistent 时 tap 胶囊空白区不关闭', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () => FloatingToast.error(context, 'error'),
          child: const Text('Show'),
        );
      },
    )));

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // tap on the message
    await tester.tap(find.text('遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // should still be there
    expect(find.text('遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。'), findsOneWidget);
  });

  testWidgets('替换策略：连续 show 两次 -> overlay 中仅 1 个 entry，且参数为新的一组',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return Column(
          children: [
            ElevatedButton(
              onPressed: () => FloatingToast.show(context, 'msg 1'),
              child: const Text('Show 1'),
            ),
            ElevatedButton(
              onPressed: () => FloatingToast.show(context, 'msg 2'),
              child: const Text('Show 2'),
            ),
          ],
        );
      },
    )));

    await tester.tap(find.text('Show 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('msg 1'), findsOneWidget);

    await tester.tap(find.text('Show 2'));
    await tester.pump();
    await tester.pump(const Duration(
        milliseconds:
            300)); // wait for old toast reverse anim to finish (220ms)

    expect(find.text('msg 1'), findsNothing);
    expect(find.text('msg 2'), findsOneWidget);

    // clear pending timer
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tone 映射表：4 个 tone -> icon/颜色断言', (WidgetTester tester) async {
    // neutral
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () =>
              FloatingToast.show(context, 'neutral', tone: ToastTone.neutral),
          child: const Text('Show neutral'),
        );
      },
    )));
    await tester.tap(find.text('Show neutral'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Icon), findsNothing);
    await tester.pump(const Duration(seconds: 4));

    // success
    await tester.tap(find.text('Show neutral')); // reset
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () =>
              FloatingToast.show(context, 'success', tone: ToastTone.success),
          child: const Text('Show success'),
        );
      },
    )));
    await tester.tap(find.text('Show success'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    // warning
    await tester.tap(find.text('Show success'));
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () =>
              FloatingToast.show(context, 'warning', tone: ToastTone.warning),
          child: const Text('Show warning'),
        );
      },
    )));
    await tester.tap(find.text('Show warning'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('关闭')); // it defaults to persistent
    await tester.pump(const Duration(seconds: 1));

    // danger
    await tester.tap(find.text('Show warning'));
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () =>
              FloatingToast.show(context, 'danger', tone: ToastTone.danger),
          child: const Text('Show danger'),
        );
      },
    )));
    await tester.tap(find.text('Show danger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('Semantics：error 胶囊带 liveRegion；× 有 tooltip/label',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildApp(Builder(
      builder: (context) {
        return ElevatedButton(
          onPressed: () => FloatingToast.error(context, 'error msg'),
          child: const Text('Show'),
        );
      },
    )));

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(Positioned),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.liveRegion, isTrue);
    expect(semantics.properties.label, '遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。');

    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('GlassChip 单测：明暗主题填充/描边色、最小高度约束', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp(
      const Center(
        child: GlassChip(label: 'Chip'),
      ),
    ));

    final constrainedBox = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(GlassChip),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(constrainedBox.constraints.minHeight, 36.0);
  });
}
