import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/jobs/job_board.dart';
import 'package:mobile_agent/application/scheduled_task_runner.dart';
import 'package:mobile_agent/application/scheduled_task_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

HeadlessRunResult outcome(RunStatus status,
        {String text = '',
        String? error,
        String? failureKind,
        AgentPauseReason? pauseReason}) =>
    HeadlessRunResult(
      text: text,
      status: status,
      error: error,
      failureKind: failureKind,
      pauseReason: pauseReason,
      runId: 'fake-run',
      inputTokens: 3,
      outputTokens: 2,
      cachedTokens: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late List<String> notices;
  Future<void> notify(
      {required int id, required String title, required String body}) async {
    notices.add(body);
  }

  Future<void> seed(String id) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 2));
    await db.saveScheduledTask(ScheduledTask(
        id: id,
        name: id,
        prompt: 'test',
        cron: const ScheduleSpec(hour: 0, minute: 0).toCron(),
        agentId: null,
        enabled: true,
        lastResult: null,
        lastRunAt: null,
        createdAt: yesterday,
        updatedAt: yesterday));
  }

  Future<Map<String, dynamic>> audit(String id) async {
    final records = await db.allAuditLogs();
    return records
        .map((r) => jsonDecode(r.detail) as Map<String, dynamic>)
        .singleWhere((r) => r['taskId'] == id);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    notices = [];
    await seed('first');
  });
  tearDown(() => db.close());

  final cases = [
    (outcome(RunStatus.completed, text: '完成内容'), 'success', '完成内容'),
    (outcome(RunStatus.completed), 'success', '任务完成'),
    (
      outcome(RunStatus.failed, error: '鉴权失败', failureKind: 'authentication'),
      'failed',
      '鉴权失败'
    ),
    (
      outcome(RunStatus.failed, error: '网络断开', failureKind: 'network'),
      'failed',
      '网络断开'
    ),
    (
      outcome(RunStatus.paused, pauseReason: AgentPauseReason.budget),
      'paused',
      '任务已暂停'
    ),
    (outcome(RunStatus.approvalRequired), 'paused', '任务已暂停'),
    (outcome(RunStatus.cancelled), 'cancelled', '任务已取消'),
    (outcome(RunStatus.completed, error: '有错误'), 'failed', '有错误'),
    (outcome(RunStatus.waitingModel), 'failed', '任务执行失败'),
  ];
  for (final entry in cases) {
    test('调度结果 ${entry.$1.status.name}/${entry.$1.failureKind} 映射 ${entry.$2}',
        () async {
      var calls = 0;
      Future<HeadlessRunResult> execute(
          ScheduledTask _, AgentCancellationToken __, CancelToken ___) async {
        calls++;
        return entry.$1;
      }

      await runDueScheduledTasks(db, execute: execute, notify: notify);
      final record = await audit('first');
      expect(record['status'], entry.$2);
      expect(record['runId'], 'fake-run');
      expect(record['executionStatus'], entry.$1.status.name);
      expect(record['failureKind'], entry.$1.failureKind);
      expect(record['error'], entry.$1.error);
      expect(record['pauseReason'], entry.$1.pauseReason?.name);
      expect(record['retryPolicy'], 'next_scheduled_occurrence');
      final saved = (await db.allScheduledTasks()).single;
      expect(saved.lastResult, contains(entry.$3));
      expect(saved.lastRunAt, isNotNull);
      expect(record['result'], saved.lastResult);
      expect(notices.single, contains(entry.$3));
      await runDueScheduledTasks(db, execute: execute, notify: notify);
      expect(calls, 1, reason: '不能隐式重放已执行工具');
    });
  }

  test('不响应取消的执行器有界退出，下一任务运行且晚到成功不覆盖超时', () async {
    await seed('second');
    final pending = Completer<HeadlessRunResult>();
    AgentCancellationToken? cancelled;
    CancelToken? httpCancelled;
    String? stuckId;
    await runDueScheduledTasks(
      db,
      executionTimeout: const Duration(milliseconds: 20),
      cancellationGrace: const Duration(milliseconds: 20),
      notify: notify,
      execute: (task, cancellation, http) {
        if (stuckId == null) {
          stuckId = task.id;
          cancelled = cancellation;
          httpCancelled = http;
          return pending.future;
        }
        return Future.value(outcome(RunStatus.completed, text: '下一任务完成'));
      },
    ).timeout(const Duration(seconds: 5));
    expect(cancelled!.isCancelled, isTrue);
    expect(httpCancelled!.isCancelled, isTrue);
    expect((await audit(stuckId!))['status'], 'timeout');
    expect(notices, hasLength(2));
    expect(notices, contains(contains('超时')));
    pending.complete(outcome(RunStatus.completed, text: '晚到成功'));
    await Future<void>.delayed(Duration.zero);
    expect((await audit(stuckId!))['status'], 'timeout');
    final otherId = stuckId == 'first' ? 'second' : 'first';
    expect((await audit(otherId))['status'], 'success');
  });

  test('任务看板与收件箱保留暂停和取消语义', () async {
    final board = JobBoard(db, seen: InMemoryInboxSeenStore());
    for (final status in [RunStatus.paused, RunStatus.cancelled]) {
      final id = status.name;
      await seed(id);
    }
    await runDueScheduledTasks(db, notify: notify,
        execute: (task, _, __) async {
      return outcome(switch (task.id) {
        'paused' => RunStatus.paused,
        'cancelled' => RunStatus.cancelled,
        _ => RunStatus.completed,
      });
    });
    final jobs = await board.jobs();
    expect(jobs.singleWhere((j) => j.rawStatus == 'paused').phase,
        JobPhase.paused);
    expect(jobs.singleWhere((j) => j.rawStatus == 'cancelled').phase,
        JobPhase.cancelled);
    final inbox = await board.inbox();
    expect(inbox.any((i) => i.reason == InboxReason.paused), isTrue);
    expect(inbox.any((i) => i.job.rawStatus == 'cancelled'), isFalse);
  });

  test('同步抛错按失败记录而不是成功', () async {
    await runDueScheduledTasks(db,
        notify: notify,
        execute: (_, __, ___) => throw StateError('fake execution failure'));
    expect((await audit('first'))['status'], 'failed');
    expect(notices.single, contains('任务执行失败'));
  });
}
