import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_activity_section.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_disclosure.dart';

/// 顶部执行面板回归：compact 时间线不再嵌套滚动，只显示最近几条，
/// 其余通过「查看全部」查看——以前最后一条会被裁掉、滚不到。
ToolActivity _activity(int index, {String status = '已完成'}) => ToolActivity(
      call:
          ToolCall(id: 'call-$index', name: 'tool_$index', arguments: const {}),
      risk: ToolRisk.safe,
      status: status,
    );

Future<void> _pump(WidgetTester tester, List<ToolActivity> activities) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.exceptionAsString().startsWith('ListTile background color')) {
      previousErrorHandler?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = previousErrorHandler);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ToolActivityTimeline(
            activities: activities,
            running: true,
            compact: true,
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('compact dock shows the latest three rows plus a show-all entry',
      (tester) async {
    await _pump(tester, [for (var i = 0; i < 10; i++) _activity(i)]);
    expect(tester.takeException(), isNull);
    expect(find.byType(NexusDisclosure), findsNWidgets(3));
    expect(find.text('查看全部 10 条'), findsOneWidget);
  });

  testWidgets('older confirmation-required rows stay visible in compact mode',
      (tester) async {
    await _pump(tester, [
      _activity(0, status: '等待确认'),
      for (var i = 1; i < 10; i++) _activity(i),
    ]);
    expect(find.byType(NexusDisclosure), findsNWidgets(4));
    expect(find.text('查看全部 10 条'), findsOneWidget);
  });

  testWidgets('show-all opens a sheet listing every row', (tester) async {
    await _pump(tester, [for (var i = 0; i < 10; i++) _activity(i)]);
    await tester.tap(find.byKey(const ValueKey('tool-activity-show-all')));
    // 运行中的头部状态是循环动画，pumpAndSettle 不会收敛，这里推进固定时长。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final sheet = find.byKey(const ValueKey('tool-activity-all-sheet'));
    expect(sheet, findsOneWidget);
    expect(find.text('全部执行步骤（10）'), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.byType(NexusDisclosure)),
      findsNWidgets(10),
    );
  });

  testWidgets('short timelines render every row without a show-all entry',
      (tester) async {
    await _pump(tester, [for (var i = 0; i < 3; i++) _activity(i)]);
    expect(find.byType(NexusDisclosure), findsNWidgets(3));
    expect(find.byKey(const ValueKey('tool-activity-show-all')), findsNothing);
  });
}
