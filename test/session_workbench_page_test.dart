// 阶段 7c：会话工作台页面。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart' show ToolActivity;
import 'package:mobile_agent/application/workbench/session_workbench.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/workbench/session_workbench_page.dart';

void main() {
  ToolActivity tool(String id, String name, Map<String, dynamic> args,
          {String status = '已完成', bool? ok}) =>
      ToolActivity(
        call: ToolCall(id: id, name: name, arguments: args),
        risk: ToolRisk.safe,
        status: status,
        ok: ok,
      );

  testWidgets('status bar, files and results tabs', (tester) async {
    final workbench = SessionWorkbench.project(
      messages: [
        ChatMessage(role: MessageRole.user, parts: const [MessagePart.text('修一下登录')]),
        ChatMessage(role: MessageRole.assistant, parts: const [MessagePart.text('已修复登录超时')]),
      ],
      activities: [
        tool('1', 'read_file', {'path': 'README.md'}),
        tool('2', 'edit_file', {'path': 'lib/login.dart'}),
        tool('3', 'delete_file', {'path': 'tmp.txt'}, status: '等待确认'),
      ],
      running: true,
      runProgress: ChatRunProgress.started(),
    );

    await tester.pumpWidget(MaterialApp(
      home: SessionWorkbenchView(workbench: workbench, title: '登录问题'),
    ));
    await tester.pump();

    expect(find.text('文件 (1)'), findsOneWidget);
    expect(find.text('结果 (1)'), findsOneWidget);
    expect(find.text('已收到请求'), findsOneWidget);
    expect(find.textContaining('1 项待确认'), findsOneWidget);

    expect(find.text('改动的文件 (1)'), findsOneWidget);
    expect(find.text('lib/login.dart'), findsOneWidget);
    expect(find.text('未改动的文件 (2)'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('未生效'), findsOneWidget);

    await tester.tap(find.text('结果 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('修一下登录'), findsOneWidget);
    expect(find.text('已修复登录超时'), findsOneWidget);

    await tester.tap(find.text('已修复登录超时'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 轮结果'), findsOneWidget);
  });

  testWidgets('empty session shows empty states', (tester) async {
    final workbench =
        SessionWorkbench.project(messages: const [], activities: const []);
    await tester.pumpWidget(MaterialApp(
      home: SessionWorkbenchView(workbench: workbench),
    ));
    await tester.pump();
    expect(find.text('空闲'), findsOneWidget);
    expect(find.text('本会话还没有接触文件'), findsOneWidget);
  });
}
