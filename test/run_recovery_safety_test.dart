import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/background_execution_gateway.dart';
import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/run_approval_scope.dart';
import 'package:mobile_agent/application/run_recovery_safety.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/domain/approval_action_codec.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/run_plan_store.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late RunPlanStore store;
  late String taskId;
  late RunPlanToken token;
  const safety = RunRecoverySafety();
  const call = ToolCall(id: 'write-1', name: 'write_file', arguments: {});

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = RunPlanStore(db);
    final task = await TaskService().create(
        db: db,
        conversationId: 'c1',
        requestJson: jsonEncode({'prompt': 'DO NOT REPLAY'}));
    taskId = task.id;
    token = await store.bind(taskId: taskId, runId: 'before');
    addTearDown(db.close);
  });

  Future<void> checkpoint(List<ChatMessage> context,
      {String runId = 'before'}) async {
    await db.customUpdate('UPDATE tasks SET progress_json=? WHERE id=?',
        variables: [
          Variable<String>(jsonEncode({
            'checkpoint': {
              'version': 1,
              'runId': runId,
              'context': encodeChatContextForPersistence(context),
            }
          })),
          Variable<String>(taskId),
        ]);
  }

  List<ChatMessage> completedContext() => [
        ChatMessage(
            role: MessageRole.assistant,
            parts: const [],
            toolCalls: const [call]),
        ChatMessage(role: MessageRole.tool, toolCallId: call.id, parts: [
          MessagePart.text(
              ToolResult.success(effect: ToolEffect.applied).encode())
        ]),
      ];

  Future<void> dispatch({ToolEffect? settle}) async {
    expect(await store.claim(token, call.id), RunDispatchClaim.granted);
    if (settle != null) {
      expect(await store.settle(token, call.id, settle), isTrue);
    }
  }

  test('unknown dispatch blocks recovery without changing the task or claim',
      () async {
    await dispatch();
    final before = await db.findTask(taskId);
    await expectLater(
        safety.requireSafe(db, taskId), throwsA(isA<RunRecoveryNeedsReview>()));
    final after = await db.findTask(taskId);
    expect(after!.status, before!.status);
    expect(after.progressJson, before.progressJson);
    final row = await db
        .customSelect('SELECT state,effect FROM run_dispatch_claims')
        .getSingle();
    expect(row.read<String>('state'), 'dispatched');
    expect(row.read<String>('effect'), 'unknown');
  });

  test(
      'settled unknown remains blocked even with a complete-looking checkpoint',
      () async {
    await dispatch(settle: ToolEffect.unknown);
    final context = completedContext();
    await checkpoint(context);
    await expectLater(safety.requireSafe(db, taskId, initialHistory: context),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('new run id cannot bypass an older unknown dispatch at store boundary',
      () async {
    await dispatch();
    await store.interrupt(token);
    await expectLater(
        store.bind(
            taskId: taskId, runId: 'fresh', expectedPreviousRunId: 'before'),
        throwsA(isA<RunPlanConflict>()));
    expect((await store.head(taskId))!.token.runId, 'before');
  });

  test('settled no-effect read-only work may safely restart', () async {
    await dispatch(settle: ToolEffect.none);
    await safety.requireSafe(db, taskId);
    await store.interrupt(token);
    final fresh = await store.bind(
        taskId: taskId, runId: 'fresh', expectedPreviousRunId: 'before');
    expect(fresh.runId, 'fresh');
  });

  test('applied operation without checkpoint cannot replay the original prompt',
      () async {
    await dispatch(settle: ToolEffect.applied);
    await expectLater(
        safety.requireSafe(db, taskId), throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('applied operation may continue only with matching call/result context',
      () async {
    await dispatch(settle: ToolEffect.applied);
    final context = completedContext();
    await checkpoint(context);
    await safety.requireSafe(db, taskId, initialHistory: context);
    await safety.requireSafe(db, taskId, inspectPersisted: true);
    // Inspecting a saved checkpoint is not permission to omit it at execution.
    await expectLater(
        safety.requireSafe(db, taskId), throwsA(isA<RunRecoveryNeedsReview>()));
    expect(await store.claim(token, call.id), RunDispatchClaim.duplicate);
  });

  test('checkpoint from another run cannot authorize continuation', () async {
    await dispatch(settle: ToolEffect.applied);
    final context = completedContext();
    await checkpoint(context, runId: 'unrelated');
    await expectLater(safety.requireSafe(db, taskId, initialHistory: context),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('incomplete checkpoint cannot forget an applied operation', () async {
    await dispatch(settle: ToolEffect.applied);
    final context = completedContext().take(1).toList();
    await checkpoint(context);
    await expectLater(safety.requireSafe(db, taskId, initialHistory: context),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('checkpoint with result but no assistant call is not complete',
      () async {
    await dispatch(settle: ToolEffect.applied);
    final context = completedContext().skip(1).toList();
    await checkpoint(context);
    await expectLater(safety.requireSafe(db, taskId, initialHistory: context),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('legacy unknown tool result is blocked even without a dispatch row',
      () async {
    final context = [
      ChatMessage(role: MessageRole.tool, toolCallId: 'legacy', parts: [
        MessagePart.text(ToolResult.failure(
                code: 'TIMEOUT', message: 'unknown', effect: ToolEffect.unknown)
            .encode())
      ])
    ];
    await expectLater(safety.requireSafe(db, taskId, initialHistory: context),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('regenerate is blocked by durable claims even after UI state is lost',
      () async {
    await dispatch();
    await expectLater(
        safety.requireReplayFreeConversation(db,
            conversationId: 'c1', visibleEffects: const [], messages: const []),
        throwsA(isA<RunRecoveryNeedsReview>()));
    // A different conversation is unaffected by this task.
    await safety.requireReplayFreeConversation(db,
        conversationId: 'c2', visibleEffects: const [], messages: const []);
  });

  test('regenerate cannot discard applied tool messages', () async {
    await expectLater(
        safety.requireReplayFreeConversation(db,
            conversationId: null,
            visibleEffects: const [],
            messages: completedContext()),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('read-only regenerate keeps its existing path', () async {
    await dispatch(settle: ToolEffect.none);
    await safety.requireReplayFreeConversation(db,
        conversationId: 'c1',
        visibleEffects: const [ToolEffect.none],
        messages: const []);
  });

  test('gateway blocks before custom executor, status mutation or model access',
      () async {
    await dispatch();
    await TaskService().updateStatus(db, taskId, 'paused');
    var called = false;
    await expectLater(
        BackgroundExecutionGateway().run(
            db: db,
            config: const ProviderConfig(
                baseUrl: 'http://127.0.0.1:1/v1', model: 'fake', apiKey: ''),
            taskId: taskId,
            runId: 'after',
            prompt: 'DO NOT REPLAY',
            execute: () async {
              called = true;
              throw StateError('must not execute');
            }),
        throwsA(isA<RunRecoveryNeedsReview>()));
    expect(called, isFalse);
    expect((await db.findTask(taskId))!.status, 'paused');
    expect((await store.head(taskId))!.token.runId, 'before');
  });

  test('direct headless entry cannot bypass recovery guard', () async {
    await dispatch();
    await expectLater(
        HeadlessExecutor.runDetailed(
            db: db,
            config: const ProviderConfig(
                baseUrl: 'http://127.0.0.1:1/v1', model: 'fake', apiKey: ''),
            taskId: taskId,
            runId: 'after',
            prompt: 'DO NOT REPLAY'),
        throwsA(isA<RunRecoveryNeedsReview>()));
  });

  test('expired approval cannot be reused', () async {
    await db.insertPendingApproval(
        requestId: 'expired',
        toolName: 'terminal',
        summary: 'redacted',
        risk: 'dangerous',
        ttl: const Duration(seconds: -1));
    expect(await db.decidePendingApproval('expired', approvalApproveAction),
        isFalse);
  });

  test(
      'plan invalidation rejects late scoped approval at the database boundary',
      () async {
    final scope = await RunApprovalScope.open(
        db: db,
        token: token,
        call: call,
        risk: ToolRisk.dangerous,
        invalidated: Completer<void>().future,
        remember: (_, __) {});
    expect(scope, isNotNull);
    await store.interrupt(token);
    expect(
        await db.decidePendingApproval(scope!.requestId, approvalApproveAction),
        isFalse);
    expect(await db.findPendingApprovalDecision(scope.requestId), isNull);
  });

  test('a completed decision cannot be overwritten or reused', () async {
    await db.insertPendingApproval(
        requestId: 'one-time',
        toolName: 'terminal',
        summary: 'redacted',
        risk: 'dangerous',
        ttl: const Duration(minutes: 1));
    expect(
        await db.decidePendingApproval('one-time', approvalDenyAction), isTrue);
    expect(await db.decidePendingApproval('one-time', approvalApproveAction),
        isFalse);
  });
}
