import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/background_execution_gateway.dart';
import 'package:mobile_agent/application/execution_lease_service.dart';
import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/project_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    for (final id in [
      'task-1',
      'task-heartbeat',
      'task-live',
      'task-lost',
      'task-other'
    ]) {
      await db.into(db.tasks).insert(Task(
          id: id,
          conversationId: '',
          stateRevision: 0,
          type: 'test',
          status: 'pending',
          requestJson: '{}',
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now,
          updatedAt: now));
    }
  });

  tearDown(() async {
    await db.close();
  });

  test('gateway occupies workspace lease for a live task and releases it',
      () async {
    const leases = ExecutionLeaseService();
    final gateway = BackgroundExecutionGateway(leases: leases);
    final started = Completer<void>();
    final release = Completer<void>();
    final future = gateway.run(
      db: db,
      config: const ProviderConfig(
        baseUrl: 'https://example.invalid',
        model: 'demo',
        apiKey: '',
      ),
      prompt: 'hello',
      taskId: 'task-live',
      workspacePath: '/tmp/app',
      execute: () async {
        started.complete();
        await release.future;
        return const HeadlessRunResult(
          text: 'ok',
          status: RunStatus.completed,
          inputTokens: 0,
          outputTokens: 0,
          cachedTokens: 0,
        );
      },
    );
    await started.future;
    expect(
      () => leases.acquire(
        db: db,
        resourceKey: ExecutionLeaseService.workspaceKey(
            ProjectService.canonicalizePath('/tmp/app')),
        taskId: 'task-other',
        runId: 'run-other',
      ),
      throwsA(isA<ExecutionLeaseConflict>()),
    );
    release.complete();
    await future;
    final leftover = await db.findExecutionLease(
      ExecutionLeaseService.workspaceKey(
          ProjectService.canonicalizePath('/tmp/app')),
    );
    expect(leftover, isNull);
  });

  test('scheduled-style run without taskId does not take a workspace lease',
      () async {
    const leases = ExecutionLeaseService();
    await BackgroundExecutionGateway(leases: leases).run(
      db: db,
      config: const ProviderConfig(
        baseUrl: 'https://example.invalid',
        model: 'demo',
        apiKey: '',
      ),
      prompt: 'hello',
      workspacePath: '/tmp/app',
      execute: () async => const HeadlessRunResult(
        text: 'ok',
        status: RunStatus.completed,
        inputTokens: 0,
        outputTokens: 0,
        cachedTokens: 0,
      ),
    );
    await leases.acquire(
      db: db,
      resourceKey: ExecutionLeaseService.workspaceKey(
          ProjectService.canonicalizePath('/tmp/app')),
      taskId: 'task-1',
      runId: 'run-1',
    );
  });

  testWidgets('consecutive heartbeat failures cancel the live run',
      (tester) async {
    final gateway = BackgroundExecutionGateway(
      leases: _ThrowingLeases(),
      heartbeatInterval: const Duration(milliseconds: 40),
      heartbeatFailureLimit: 3,
    );
    final token = AgentCancellationToken();
    final started = Completer<void>();
    final future = gateway.run(
      db: db,
      config: const ProviderConfig(
        baseUrl: 'https://example.invalid',
        model: 'demo',
        apiKey: '',
      ),
      prompt: 'hello',
      taskId: 'task-heartbeat',
      workspacePath: '/tmp/app',
      cancellationToken: token,
      execute: () async {
        started.complete();
        await token.whenCancelled;
        return const HeadlessRunResult(
          text: 'stopped',
          status: RunStatus.cancelled,
          inputTokens: 0,
          outputTokens: 0,
          cachedTokens: 0,
        );
      },
    );
    await started.future;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final result = await future;
    expect(token.isCancelled, isTrue);
    expect(result.status, RunStatus.cancelled);
  });

  testWidgets('a lost workspace lease cancels the live run immediately',
      (tester) async {
    final gateway = BackgroundExecutionGateway(
      leases: _LostLeases(),
      heartbeatInterval: const Duration(milliseconds: 40),
    );
    final token = AgentCancellationToken();
    final started = Completer<void>();
    final future = gateway.run(
      db: db,
      config: const ProviderConfig(
        baseUrl: 'https://example.invalid',
        model: 'demo',
        apiKey: '',
      ),
      prompt: 'hello',
      taskId: 'task-lost',
      workspacePath: '/tmp/app',
      cancellationToken: token,
      execute: () async {
        started.complete();
        await token.whenCancelled;
        return const HeadlessRunResult(
          text: 'stopped',
          status: RunStatus.cancelled,
          inputTokens: 0,
          outputTokens: 0,
          cachedTokens: 0,
        );
      },
    );
    await started.future;
    await tester.pump(const Duration(milliseconds: 40));
    final result = await future;
    expect(token.isCancelled, isTrue);
    expect(result.status, RunStatus.cancelled);
  });
}

class _ThrowingLeases extends ExecutionLeaseService {
  @override
  Future<bool> heartbeat({
    required AppDatabase db,
    required ExecutionLease lease,
    Duration ttl = const Duration(minutes: 2),
  }) async {
    throw StateError('database unavailable');
  }
}

class _LostLeases extends ExecutionLeaseService {
  @override
  Future<bool> heartbeat({
    required AppDatabase db,
    required ExecutionLease lease,
    Duration ttl = const Duration(minutes: 2),
  }) async {
    return false;
  }
}
