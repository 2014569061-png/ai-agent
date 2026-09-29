import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/file_baseline_store.dart';
import 'package:mobile_agent/application/run_event_tracker.dart';
import 'package:mobile_agent/application/tool_pipeline/execution_interceptors.dart';
import 'package:mobile_agent/application/tool_pipeline/run_event_interceptor.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_run_context.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

void main() {
  late AppDatabase db;
  late RunEventTracker tracker;
  late Directory workspace;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tracker = RunEventTracker(database: db, runId: 'run-1');
    workspace = await Directory.systemTemp.createTemp('nexus-run-events');
  });
  tearDown(() async {
    await db.close();
    await workspace.delete(recursive: true);
  });

  ToolInvocation invocation(String name, Map<String, dynamic> arguments,
          {ToolRegistration? registration}) =>
      ToolInvocation(
        call: ToolCall(id: 'c1', name: name, arguments: arguments),
        registration: registration,
        context: ToolRunContext.detached(),
      );

  Future<RunEvent> onlyEvent() async {
    await tracker.flush();
    final events = await db.eventsForRun('run-1');
    expect(events, hasLength(1));
    return events.single;
  }

  Map<String, dynamic> metadataOf(RunEvent event) =>
      Map<String, dynamic>.from(jsonDecode(event.metadataJson) as Map);

  test('executed file call is one finished row with tool metadata', () async {
    final tool = WriteFileTool(sandbox: WorkspaceSandbox(workspace.path));
    final registration = ToolRegistration(
      spec: ToolSpec.fromManifest(tool.manifest),
      executor: tool,
    );
    final result = await RunEventInterceptor(tracker).intercept(
      invocation('write_file', {'path': 'a.txt', 'content': 'hi'},
          registration: registration),
      (current) {
        current.context.markExecutionStarted();
        return executeWithTimeout(current);
      },
    );

    expect(result.ok, isTrue);
    final event = await onlyEvent();
    expect(event.type, 'file_operation');
    expect(event.status, 'success');
    expect(event.endedAt, isNotNull);
    final metadata = metadataOf(event);
    expect(metadata['executed'], isTrue);
    // write_file counts as a sensitive tool for RunEventTracker, which redacts
    // its path exactly as it does on the chat path.
    expect(metadata['path'], '[REDACTED]');
    expect(metadata['toolCode'], result.code);
    // From the tool's own lastMetadata, like the chat path.
    expect(metadata, contains('contentHashAfter'));
  });

  test('call stopped before execution is recorded as not executed', () async {
    await RunEventInterceptor(tracker).intercept(
      invocation('calculator', {'a': 1}),
      (_) async => ToolResult.failure(code: 'DENIED', message: 'no'),
    );
    final event = await onlyEvent();
    expect(event.type, 'tool_call');
    expect(event.status, 'failed');
    final metadata = metadataOf(event);
    expect(metadata['executed'], isFalse);
    expect(metadata['toolCode'], 'DENIED');
  });

  test('cancellation is recorded and rethrown', () async {
    await expectLater(
      RunEventInterceptor(tracker).intercept(
        invocation('calculator', const {}),
        (_) => throw const ToolRunCancelled(),
      ),
      throwsA(isA<ToolRunCancelled>()),
    );
    expect((await onlyEvent()).status, 'cancelled');
  });

  test('pipeline errors are recorded and rethrown', () async {
    await expectLater(
      RunEventInterceptor(tracker).intercept(
        invocation('calculator', const {}),
        (_) => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect((await onlyEvent()).status, 'failed');
  });

  test('buildToolPipeline puts recording first and baseline last', () {
    final defaults = defaultToolInterceptors().map((i) => i.id).toList();
    expect(buildToolPipeline().interceptors.map((i) => i.id), defaults);
    final full = buildToolPipeline(
      runEvents: tracker,
      baseline: FileBaselineStore(taskId: 't', workspacePath: workspace.path),
    ).interceptors.map((i) => i.id).toList();
    expect(full.first, 'run-events');
    expect(full.last, 'file-baseline');
    expect(full.sublist(1, full.length - 1), defaults);
  });
}
