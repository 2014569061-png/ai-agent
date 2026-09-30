// 阶段 7c：会话工作台投影。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart' show ToolActivity;
import 'package:mobile_agent/application/workbench/session_workbench.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  var seq = 0;
  ToolActivity tool(String name, Map<String, dynamic> args,
          {String status = '已完成', bool? ok}) =>
      ToolActivity(
        call: ToolCall(id: 'c${seq++}', name: name, arguments: args),
        risk: ToolRisk.safe,
        status: status,
        ok: ok,
      );

  ChatMessage msg(MessageRole role, String text) =>
      ChatMessage(role: role, parts: [MessagePart.text(text)]);

  WorkbenchFile file(SessionWorkbench wb, String path) =>
      wb.files.singleWhere((f) => f.path == path);

  test('files: changed first by recency, then read-only files', () {
    final wb = SessionWorkbench.project(messages: const [], activities: [
      tool('read_file', {'path': 'lib/a.dart'}),
      tool('edit_file', {'path': 'lib/a.dart'}),
      tool('read_file', {'path': 'README.md'}),
      tool('write_file', {'path': 'lib/new.dart'}),
      tool('list_directory', {'path': 'lib'}),
      tool('search_files', {'query': 'x'}),
      tool('run_command', {'command': 'ls'}),
    ]);
    // 目录浏览、全文搜索和非文件工具不进文件列表。
    expect(wb.files.map((f) => f.path), ['lib/new.dart', 'lib/a.dart', 'README.md']);
    expect(file(wb, 'lib/new.dart').change, WorkbenchFileChange.written);
    expect(file(wb, 'lib/a.dart').change, WorkbenchFileChange.modified);
    expect(file(wb, 'lib/a.dart').reads, 1);
    expect(file(wb, 'README.md').change, WorkbenchFileChange.read);
    expect(wb.status.changedFiles, 2);
  });

  test('write after read is a modification; edits keep the written mark', () {
    final wb = SessionWorkbench.project(messages: const [], activities: [
      tool('read_file', {'path': 'a.txt'}),
      tool('write_file', {'path': 'a.txt'}),
      tool('write_file', {'path': './b.txt'}),
      tool('edit_file', {'path': 'b.txt'}),
    ]);
    expect(file(wb, 'a.txt').change, WorkbenchFileChange.modified);
    expect(file(wb, 'b.txt').change, WorkbenchFileChange.written);
    expect(file(wb, 'b.txt').writes, 2);
  });

  test('delete, move and restore', () {
    final wb = SessionWorkbench.project(messages: const [], activities: [
      tool('delete_file', {'path': 'old.txt'}),
      tool('move_file', {'path': 'src\\x.dart', 'newPath': 'lib/x.dart'}),
      tool('delete_file', {'path': 'gone.txt'}),
      tool('write_file', {'path': 'gone.txt'}),
    ]);
    expect(file(wb, 'old.txt').change, WorkbenchFileChange.deleted);
    expect(file(wb, 'src/x.dart').change, WorkbenchFileChange.moved);
    expect(file(wb, 'src/x.dart').movedTo, 'lib/x.dart');
    expect(file(wb, 'lib/x.dart').change, WorkbenchFileChange.created);
    expect(file(wb, 'gone.txt').change, WorkbenchFileChange.modified);
  });

  test('failed and pending calls do not count as changes', () {
    final wb = SessionWorkbench.project(messages: const [], activities: [
      tool('edit_file', {'path': 'a.txt'}, status: '执行失败', ok: false),
      tool('delete_file', {'path': 'b.txt'}, status: '等待确认'),
      tool('write_file', {'path': 'c.txt'}, status: '执行中'),
    ]);
    expect(file(wb, 'a.txt').change, WorkbenchFileChange.attempted);
    expect(file(wb, 'a.txt').failures, 1);
    expect(file(wb, 'b.txt').changed, isFalse);
    expect(file(wb, 'b.txt').change, WorkbenchFileChange.attempted);
    expect(wb.status.changedFiles, 0);
    expect(wb.status.failedTools, 1);
    expect(wb.status.pendingApprovals, 1);
    expect(wb.status.toolCalls, 3);
  });

  test('declared traits win over the built-in fallback', () {
    final wb = SessionWorkbench.project(
      messages: const [],
      activities: [
        tool('mcp_put', {'target': 'docs/x.md'}),
        tool('write_file', {'path': 'ignored.txt'}),
      ],
      traitsFor: (name) => name == 'mcp_put'
          ? const ToolTraits(
              readOnly: false,
              scopes: {ToolEffectScope.workspace},
              pathArguments: ['target'],
              fileOperation: true)
          : ToolTraits.undeclared,
    );
    expect(wb.files.map((f) => f.path), ['docs/x.md']);
    expect(wb.files.single.change, WorkbenchFileChange.modified);
  });

  test('turns pair each prompt with its last non-empty answer, newest first', () {
    final wb = SessionWorkbench.project(messages: [
      msg(MessageRole.system, 'sys'),
      msg(MessageRole.user, '第一问'),
      msg(MessageRole.assistant, '草稿'),
      msg(MessageRole.assistant, '最终答案'),
      msg(MessageRole.assistant, '  '),
      msg(MessageRole.user, '第二问'),
    ], activities: const []);
    expect(wb.turns.length, 2);
    expect(wb.turns[0].index, 2);
    expect(wb.turns[0].prompt, '第二问');
    expect(wb.turns[0].answer, isNull);
    expect(wb.turns[1].answer, '最终答案');
    expect(wb.status.turns, 2);
  });

  test('stage label only while running or paused', () {
    final progress = ChatRunProgress.started();
    expect(
        SessionWorkbench.project(
                messages: const [], activities: const [], runProgress: progress)
            .status
            .stageLabel,
        isNull);
    expect(
        SessionWorkbench.project(
                messages: const [],
                activities: const [],
                running: true,
                runProgress: progress)
            .status
            .stageLabel,
        '已收到请求');
  });
}
