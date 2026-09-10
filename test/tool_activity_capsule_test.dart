import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_activity_section.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('shows the verification warning for unknown effects',
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

    expect(find.text('有 1 项结果待核验'), findsOneWidget);
    await tester.tap(find.text('有 1 项结果待核验'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();
    expect(find.text('待核验'), findsOneWidget);
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
}

class _Harness extends StatelessWidget {
  const _Harness({required this.activities});

  final List<ToolActivity> activities;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ToolActivityCapsule(activities: activities, running: false),
        ),
      );
}
