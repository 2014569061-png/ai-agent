import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_activity_section.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('shows every tool step inline without requiring a tap',
      (tester) async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details
          .exceptionAsString()
          .startsWith('ListTile background color')) {
        previousErrorHandler?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    await tester.pumpWidget(const _Harness(
      activities: [
        ToolActivity(
          call: ToolCall(
            id: 'terminal-1',
            name: 'terminal',
            arguments: {'command': 'flutter test'},
          ),
          risk: ToolRisk.requiresConfirmation,
          status: '执行失败',
          ok: false,
          code: 'EFFECT_UNKNOWN',
          effect: ToolEffect.unknown,
          result: '命令超时，无法确认是否仍在运行',
        ),
      ],
    ));

    // 内联时间线：行标题直接可见，不需要先点开胶囊。
    expect(find.text('需要核验：执行命令 flutter test'), findsOneWidget);
    expect(find.text('待核验'), findsOneWidget);

    await tester.tap(find.text('需要核验：执行命令 flutter test'));
    await tester.pumpAndSettle();
    expect(find.text('结果无法确认，请先检查目标状态再重试。'), findsOneWidget);
  });

  testWidgets('summarizes confirmed side effects after completion',
      (tester) async {
    await tester.pumpWidget(const _Harness(
      activities: [
        ToolActivity(
          call: ToolCall(
            id: 'write-1',
            name: 'write_file',
            arguments: {'path': 'lib/main.dart'},
          ),
          risk: ToolRisk.requiresConfirmation,
          status: '已完成',
          ok: true,
          code: 'OK',
          effect: ToolEffect.applied,
          result: '已写入文件',
        ),
      ],
    ));

    expect(find.text('1 项操作已执行'), findsOneWidget);
  });

  testWidgets('uses a human-readable result card before technical details',
      (tester) async {
    await tester.pumpWidget(const _Harness(
      activities: [
        ToolActivity(
          call: ToolCall(
            id: 'write-1',
            name: 'write_file',
            arguments: {'path': 'lib/main.dart', 'content': 'void main() {}'},
          ),
          risk: ToolRisk.requiresConfirmation,
          status: '已完成',
          ok: true,
          code: 'OK',
          effect: ToolEffect.applied,
          result: '已写入文件',
        ),
      ],
    ));

    expect(find.text('已完成：写入文件 lib/main.dart'), findsOneWidget);
    expect(find.text('操作结果已记录。'), findsOneWidget);
    expect(find.text('write_file'), findsNothing);

    await tester.tap(find.text('已完成：写入文件 lib/main.dart'));
    await tester.pumpAndSettle();

    expect(find.text('技术详情'), findsOneWidget);
    expect(find.textContaining('工具: write_file'), findsOneWidget);
  });

  testWidgets('collapses a long finished trajectory behind a toggle',
      (tester) async {
    await tester.pumpWidget(_Harness(
      activities: _longTrajectory(),
    ));

    // 超过阈值的已完成轨迹默认只显示摘要行，展开后才出现明细行。
    expect(find.text('10 项工具已完成（点击展开）'), findsOneWidget);
    expect(find.text('已完成：读取文件 a0.txt'), findsNothing);

    await tester.tap(find.text('10 项工具已完成（点击展开）'));
    await tester.pumpAndSettle();
    expect(find.text('已完成：读取文件 a0.txt'), findsOneWidget);
  });

  testWidgets('keeps a long running trajectory fully visible', (tester) async {
    await tester.pumpWidget(_Harness(
      running: true,
      activities: _longTrajectory(),
    ));

    // 运行中不折叠：用户能实时看到每一步。
    expect(find.text('已完成：读取文件 a0.txt'), findsOneWidget);
    expect(find.text('已完成：读取文件 a9.txt'), findsOneWidget);
  });
}

List<ToolActivity> _longTrajectory() => [
      for (var i = 0; i < 10; i++)
        ToolActivity(
          call: ToolCall(
            id: 'tool-$i',
            name: 'read_file',
            arguments: {'path': 'a$i.txt'},
          ),
          risk: ToolRisk.safe,
          status: '已完成',
          ok: true,
          code: 'OK',
          effect: ToolEffect.none,
          result: 'ok',
        ),
    ];

class _Harness extends StatelessWidget {
  const _Harness({required this.activities, this.running = false});

  final List<ToolActivity> activities;
  final bool running;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ToolActivityTimeline(
            activities: activities,
            running: running,
          ),
        ),
      );
}
