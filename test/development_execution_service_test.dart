import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/development_execution_service.dart';
import 'package:mobile_agent/application/execution_lease_service.dart';
import 'package:mobile_agent/application/project_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('follow-up on ended task returns 任务已结束', () async {
    final service = DevelopmentExecutionService(db: db);
    final handle = await service.enqueue(const DevelopmentTaskRequest(
      prompt: 'build',
      conversationId: 'c1',
    ));
    await db.updateTaskStatus(handle.taskId, 'completed');
    final receipt = await service.submitControl(TaskControlRequest(
      taskId: handle.taskId,
      kind: TaskControlKind.followUp,
      clientControlId: 'client-1',
      payload: const {'text': '再改一处'},
    ));
    expect(receipt.status, 'rejected');
    expect(receipt.message, '任务已结束');
  });

  test('duplicate clientControlId is idempotent', () async {
    final service = DevelopmentExecutionService(db: db);
    final handle = await service.enqueue(const DevelopmentTaskRequest(
      prompt: 'build',
      conversationId: 'c1',
    ));
    final first = await service.submitControl(TaskControlRequest(
      taskId: handle.taskId,
      kind: TaskControlKind.pause,
      clientControlId: 'same-id',
    ));
    final second = await service.submitControl(TaskControlRequest(
      taskId: handle.taskId,
      kind: TaskControlKind.pause,
      clientControlId: 'same-id',
    ));
    expect(first.duplicate, isFalse);
    expect(second.duplicate, isTrue);
    expect(second.id, first.id);
  });

  test('workspace lease serializes two tasks on the same path', () async {
    const leases = ExecutionLeaseService();
    await leases.acquire(
      db: db,
      resourceKey: ExecutionLeaseService.workspaceKey(
          ProjectService.canonicalizePath('/tmp/app')),
      taskId: 't1',
      runId: 'r1',
    );
    expect(
      () => leases.acquire(
        db: db,
        resourceKey: ExecutionLeaseService.workspaceKey(
            ProjectService.canonicalizePath('/tmp/app')),
        taskId: 't2',
        runId: 'r2',
      ),
      throwsA(isA<ExecutionLeaseConflict>()),
    );
  });

  test('queued task reports queued status when workspace is occupied',
      () async {
    const leases = ExecutionLeaseService();
    await leases.acquire(
      db: db,
      resourceKey: ExecutionLeaseService.workspaceKey(
          ProjectService.canonicalizePath('/tmp/app')),
      taskId: 't1',
      runId: 'r1',
    );

    final handle = await DevelopmentExecutionService(db: db).enqueue(
      const DevelopmentTaskRequest(
        prompt: 'wait for workspace',
        conversationId: 'c1',
        workspacePath: '/tmp/app',
        requestId: 'queued-request',
      ),
    );

    expect(handle.status, 'queued');
    expect((await db.findTask(handle.taskId))?.status, 'queued');
  });
}
