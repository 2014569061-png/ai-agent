import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/auto_verification_policy.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/application/history_compactor.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/sub_agent_tool.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';

class _SummaryProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    yield TextDeltaEvent(
        requests.length == 1 ? 'Original goal; TODO remains.' : 'Final answer');
    yield const UsageEvent(promptTokens: 10, completionTokens: 5);
    yield const CompletedEvent();
  }
}

ChatMessage user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

void main() {
  test('executor summarizes before main request without leaking summary text',
      () async {
    final provider = _SummaryProvider();
    final events =
        await AgentExecutor(provider: provider, tools: ToolRegistry()).run(
      history: [user('Original goal ${'中' * 5000}'), user('Continue')],
      model: 'test',
      contextBudgetTokens: 4000,
      maxTokens: 512,
    ).toList();
    expect(provider.requests, hasLength(2));
    expect(provider.requests.first.tools, isEmpty);
    expect(
        provider.requests.last.messages
            .any((m) => m.text.startsWith(HistoryCompactor.summaryMark)),
        isTrue);
    expect(events.whereType<TextEvent>().map((e) => e.text).join(),
        'Final answer');
    expect(events.whereType<AgentUsageEvent>().last.promptTokens, 20);
  });
  test('truncation preserves final diagnostics and valid Unicode', () {
    final output = 'START${'😀' * 100}BUILD FAILED';
    final truncated = ContextWindow.truncateToolResult(output, 40);
    expect(truncated, startsWith('START'));
    expect(truncated, endsWith('BUILD FAILED'));
    expect(truncated, contains('中间省略'));
    expect(utf8.decode(utf8.encode(truncated)), truncated);
    expect(ContextWindow.truncateToolResult('short', 40), 'short');
  });

  group('agent file freshness', () {
    late Directory directory;
    late WorkspaceSandbox sandbox;
    late File file;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('nexus-fresh-');
      sandbox = WorkspaceSandbox(directory.path, requireReadBeforeWrite: true);
      file = File('${directory.path}/code.txt');
      await file.writeAsString('old value');
    });
    tearDown(() => directory.delete(recursive: true));

    test('unread overwrite and edit fail without modifying the file', () async {
      final write = await WriteFileTool(sandbox: sandbox)
          .execute({'path': 'code.txt', 'content': 'replacement'});
      final edit = await EditFileTool(sandbox: sandbox).execute({
        'path': 'code.txt',
        'targetContent': 'old',
        'replacementContent': 'new',
      });
      for (final result in [write, edit]) {
        expect(result.code, ToolCodes.readRequired);
        expect(result.effect, ToolEffect.none);
      }
      expect(await file.readAsString(), 'old value');
    });

    test('external same-size change is rejected; reread permits edit',
        () async {
      final reader = ReadFileTool(sandbox: sandbox);
      final editor = EditFileTool(sandbox: sandbox);
      await reader.execute({'path': 'code.txt'});
      await file.writeAsString('new value');
      final args = {
        'path': 'code.txt',
        'targetContent': 'value',
        'replacementContent': 'result'
      };
      expect((await editor.execute(args)).code, ToolCodes.revisionConflict);
      expect(await file.readAsString(), 'new value');
      await reader.execute({'path': './code.txt'});
      expect((await editor.execute(args)).ok, isTrue);
      expect(await file.readAsString(), 'new result');
      expect(
          (await editor.execute({
            'path': 'code.txt',
            'targetContent': 'result',
            'replacementContent': 'done'
          }))
              .ok,
          isTrue);
    });

    test('new files work; empty existing files still require read', () async {
      final writer = WriteFileTool(sandbox: sandbox);
      expect((await writer.execute({'path': 'new.txt', 'content': 'x'})).ok,
          isTrue);
      await file.writeAsString('');
      expect((await writer.execute({'path': 'code.txt', 'content': 'x'})).code,
          ToolCodes.readRequired);
      await ReadFileTool(sandbox: sandbox).execute({'path': 'code.txt'});
      final result = await writer.execute({'path': 'code.txt', 'content': 'x'});
      expect(result.ok, isTrue);
      expect(result.data?['created'], isFalse);
    });
  });

  test('subagent exceptions are failures with no internal error disclosure',
      () async {
    final tool = SubAgentTool(onRun: (_, __, budget) async {
      expect(budget, SubAgentTool.minBudget);
      throw StateError('secret-internal-detail');
    });
    final result = await tool.execute({'prompt': 'inspect', 'maxTokens': 1});
    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.toolError);
    expect(result.encode(), isNot(contains('secret-internal-detail')));
  });

  test(
      'verification requires opt-in, permissions and successful active execution',
      () {
    bool allows(
            {bool enabled = true,
            bool files = true,
            bool terminal = true,
            String status = 'completed',
            bool cancelled = false,
            bool plan = false}) =>
        AutoVerificationPolicy.allows(
            enabled: enabled,
            workspaceFiles: files,
            terminal: terminal,
            status: status,
            cancelled: cancelled,
            planMode: plan);
    expect(allows(), isTrue);
    expect(allows(enabled: false), isFalse);
    expect(allows(files: false), isFalse);
    expect(allows(terminal: false), isFalse);
    expect(allows(status: 'failed'), isFalse);
    expect(allows(status: 'paused'), isFalse);
    expect(allows(cancelled: true), isFalse);
    expect(allows(plan: true), isFalse);
  });

  group('history summaries', () {
    final window = ContextWindow(maxTokens: 2000);
    final messages = [user('Original goal ${'中' * 2400}'), user('Continue')];
    test('summarizes dropped turns and preserves the current user request',
        () async {
      var calls = 0;
      final result = await HistoryCompactor().apply(messages, window: window,
          summarize: (transcript, tokens) async {
        calls++;
        expect(transcript, contains('Original goal'));
        expect(transcript.length, lessThan(1200));
        return 'Goal retained; tests failed; fix remains TODO.';
      });
      expect(calls, 1);
      expect(result.any((m) => m.text.contains(HistoryCompactor.summaryMark)),
          isTrue);
      expect(result.last.text, 'Continue');
      expect(
          result.any((m) => m.text == ContextWindow.compactionNotice), isFalse);
      expect(
          result.fold<int>(
              0, (sum, m) => sum + ContextWindow.estimateTokens(m)),
          lessThanOrEqualTo(window.maxTokens));
    });
    test('failed summarization falls back honestly', () async {
      final result = await HistoryCompactor().apply(messages,
          window: window,
          summarize: (_, __) async => throw StateError('offline'));
      expect(
          result.any((m) => m.text == ContextWindow.compactionNotice), isTrue);
      expect(result.last.text, 'Continue');
    });
    test('ordinary turns do not invoke the model', () async {
      final result = await HistoryCompactor().apply([user('Hello')],
          window: window,
          summarize: (_, __) async => fail('unexpected summary request'));
      expect(result.single.text, 'Hello');
    });
  });
}
