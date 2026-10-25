import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/apply_patch_tool.dart';
import 'package:mobile_agent/infrastructure/tools/parallel_sub_agents_tool.dart';
import 'package:mobile_agent/infrastructure/tools/repo_map_tool.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';
import 'package:mobile_agent/presentation/chat/transcript_view_policy.dart';

void main() {
  late Directory root;
  late WorkspaceSandbox sandbox;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-mechanisms-');
    sandbox = WorkspaceSandbox(root.path, requireReadBeforeWrite: true);
  });
  tearDown(() => root.delete(recursive: true));

  test('AST symbols distinguish declarations from comments and string literals',
      () async {
    await File('${root.path}/main.dart').writeAsString('''
// class Fake {}
class Real {
  String label() => 'void imaginary() {}';
}
void main() {}
''');
    final tool = RepoMapTool(sandbox: sandbox);
    final result = await tool.execute({});
    expect(result.ok, isTrue);
    final symbols = result.data!['symbols'] as List;
    expect(symbols.map((s) => s['name']), ['Real', 'label', 'main']);
    expect(symbols[1]['owner'], 'Real');
    expect(symbols.first['line'], 2);
    expect(symbols.first['parseErrors'], 0);
    // Indexing is not read-before-write authorization.
    expect(
        (await WriteFileTool(sandbox: sandbox).execute({
          'path': 'main.dart',
          'content': 'overwritten',
        }))
            .code,
        ToolCodes.readRequired);
    await File('${root.path}/main.dart').writeAsString('class Changed {}');
    final changed = await tool.execute({'query': 'changed'});
    expect((changed.data!['symbols'] as List).single['name'], 'Changed');
  });

  test(
      'repo map skips generated files and build directories and bounds results',
      () async {
    await Directory('${root.path}/build').create();
    await File('${root.path}/build/hidden.dart')
        .writeAsString('class Hidden {}');
    await File('${root.path}/data.g.dart').writeAsString('class Generated {}');
    await File('${root.path}/a.dart').writeAsString('class A {}\nclass B {}');
    final result = await RepoMapTool(sandbox: sandbox).execute({'limit': 1});
    expect(result.data!['scannedFiles'], 1);
    expect(result.data!['truncated'], isTrue);
    expect((result.data!['symbols'] as List).single['name'], 'A');
    expect(
        (await RepoMapTool(sandbox: sandbox).execute({'path': '../escape'})).ok,
        isFalse);
  });

  test(
      'multi-hunk patch is all-or-nothing on context mismatch and checks freshness',
      () async {
    final file = File('${root.path}/code.txt');
    await file.writeAsString('a\nb\nc\nd\n');
    final patcher = ApplyPatchTool(sandbox: sandbox);
    const patch =
        '--- a/code.txt\n+++ b/code.txt\n@@ -1 +1 @@\n-a\n+A\n@@ -4 +4 @@\n-d\n+D\n';
    expect((await patcher.execute({'path': 'code.txt', 'patch': patch})).code,
        ToolCodes.readRequired);
    await ReadFileTool(sandbox: sandbox).execute({'path': 'code.txt'});
    final bad = await patcher.execute(
        {'path': 'code.txt', 'patch': patch.replaceFirst('-d', '-wrong')});
    expect(bad.ok, isFalse);
    expect(bad.effect, ToolEffect.none);
    expect(await file.readAsString(), 'a\nb\nc\nd\n');
    expect((await patcher.execute({'path': 'code.txt', 'patch': patch})).ok,
        isTrue);
    expect(await file.readAsString(), 'A\nb\nc\nD\n');
    expect(patcher.lastMetadata['contentHashAfter'], isNotEmpty);
    await file.writeAsString('external\n');
    expect((await patcher.execute({'path': 'code.txt', 'patch': patch})).code,
        ToolCodes.revisionConflict);
  });

  test('patch preserves CRLF and supports explicit missing final newline', () {
    expect(
        applyUnifiedPatch(
            'a\r\nb\r\n', '--- a/f\n+++ b/f\n@@ -2 +2 @@\n-b\n+B\n', 'f'),
        'a\r\nB\r\n');
    expect(
        applyUnifiedPatch(
            'a',
            '--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b\n\\ No newline at end of file\n',
            'f'),
        'b');
    expect(
        () => applyUnifiedPatch(
            'a\n', '--- a/other\n+++ b/other\n@@ -1 +1 @@\n-a\n+b\n', 'f'),
        throwsFormatException);
  });

  test(
      'parallel tasks start together, preserve order and settle failures independently',
      () async {
    final started = <String>[];
    final barrier = Completer<void>();
    final tool = ParallelSubAgentsTool(onRun: (_, prompt, budget) async {
      started.add(prompt);
      if (started.length == 2) barrier.complete();
      await barrier.future;
      if (prompt == 'fail') throw StateError('private details');
      return 'ok';
    });
    final result = await tool.execute({
      'tasks': [
        {'id': 'a', 'prompt': 'pass'},
        {'id': 'b', 'prompt': 'fail'},
      ]
    }).timeout(const Duration(seconds: 2));
    expect(started, ['pass', 'fail']);
    expect(result.ok, isFalse);
    final results = result.data!['results'] as List;
    expect(results.map((r) => r['id']), ['a', 'b']);
    expect(results.first['ok'], isTrue);
    expect(results.last['ok'], isFalse);
    expect(result.encode(), isNot(contains('private details')));
  });

  test('invalid parallel batch never partially starts work', () async {
    var calls = 0;
    final tool = ParallelSubAgentsTool(onRun: (_, __, ___) async {
      calls++;
      return '';
    });
    final result = await tool.execute({
      'tasks': [
        {'id': 'a', 'prompt': 'one', 'maxTokens': 8000},
        {'id': 'b', 'prompt': 'two', 'maxTokens': 8000},
      ]
    });
    expect(result.code, ToolCodes.invalidArguments);
    expect(calls, 0);
  });

  test(
      'disclosure policy keeps approvals visible and collapses settled history',
      () {
    expect(
        TranscriptViewPolicy.forTimeline(
                running: false, compact: true, count: 20, needsApproval: true)
            .forceToolsOpen,
        isTrue);
    expect(
        TranscriptViewPolicy.forTimeline(
                running: false, compact: false, count: 20, needsApproval: false)
            .toolsExpanded,
        isFalse);
    expect(
        TranscriptViewPolicy.forPlan(confirmed: true, status: 'paused')
            .planExpanded,
        isTrue);
    expect(
        TranscriptViewPolicy.forPlan(confirmed: true, status: 'completed')
            .planExpanded,
        isFalse);
    expect(
        TranscriptViewPolicy.forReasoning(
                streaming: true, hasAnswer: true, hasProgress: true)
            .condensedProgress,
        isTrue);
  });
}
