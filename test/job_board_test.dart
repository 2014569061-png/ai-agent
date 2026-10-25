// 阶段 7b：任务列表与收件箱。
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/jobs/job_board.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late InMemoryInboxSeenStore seen;
  final now = DateTime(2026, 9, 30, 12);
  late JobBoard board;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seen = InMemoryInboxSeenStore();
    board = JobBoard(db, seen: seen, clock: () => now);
  });
  tearDown(() => db.close());

  Future<void> task(String id, String status,
      {Duration ago = const Duration(minutes: 5),
      String? title,
      String? summary}) {
    final at = now.subtract(ago);
    return db.saveTask(Task(
      id: id,
      conversationId: 'conv-$id',
      projectId: null,
      stateRevision: 0,
      type: 'agent',
      status: status,
      requestJson: jsonEncode({'prompt': '做点事 $id', if (title != null) 'title': title}),
      progressJson: jsonEncode({if (summary != null) 'summary': summary}),
      resumeCount: 0,
      createdAt: at,
      updatedAt: at,
    ));
  }

  Future<void> scheduledRun(String id, String status,
      {Duration ago = const Duration(minutes: 1), String result = '结果'}) {
    final at = now.subtract(ago);
    return db.insertAuditLog(AuditLogsCompanion.insert(
      id: id,
      type: JobBoard.scheduledRunAuditType,
      detail: jsonEncode({'taskId': 's1', 'taskName': '每日简报', 'status': status, 'result': result}),
      decision: Value(status),
      risk: const Value('background'),
      createdAt: at,
    ));
  }

  test('jobs merge tasks and scheduled runs, newest first', () async {
    await task('t1', 'completed', ago: const Duration(hours: 2), title: '修复登录');
    await task('t2', 'running', ago: const Duration(minutes: 10));
    await scheduledRun('r1', 'success');

    final jobs = await board.jobs();
    expect(jobs.map((j) => j.id), ['r1', 't2', 't1']);
    expect(jobs[0].kind, JobKind.scheduledRun);
    expect(jobs[0].title, '每日简报');
    expect(jobs[1].isActive, isTrue);
    expect(jobs[2].title, '修复登录');
    expect(jobs[2].conversationId, 'conv-t1');
  });

  test('task statuses map to phases', () {
    expect(JobBoard.phaseForTaskStatus('queued'), JobPhase.queued);
    expect(JobBoard.phaseForTaskStatus('pause_requested'), JobPhase.running);
    expect(JobBoard.phaseForTaskStatus('waiting_approval'), JobPhase.needsApproval);
    expect(JobBoard.phaseForTaskStatus('paused'), JobPhase.paused);
    expect(JobBoard.phaseForTaskStatus('cancelled'), JobPhase.cancelled);
    expect(JobBoard.phaseForTaskStatus('weird'), JobPhase.needsVerification);
  });

  test('inbox holds items needing attention and skips active or cancelled ones',
      () async {
    await task('approve', 'waiting_approval');
    await task('pause', 'paused');
    await task('fail', 'failed');
    await task('done', 'completed', summary: '已完成 3 个文件的修改');
    await task('run', 'running');
    await task('cancel', 'cancelled');
    await scheduledRun('ok', 'success');
    await scheduledRun('timeout', 'timeout');

    final inbox = await board.inbox();
    final reasons = {for (final i in inbox) i.job.id: i.reason};
    expect(reasons, {
      'approve': InboxReason.needsApproval,
      'pause': InboxReason.paused,
      'fail': InboxReason.failed,
      'done': InboxReason.completed,
      'ok': InboxReason.scheduledRun,
      'timeout': InboxReason.needsVerification,
    });
    expect(inbox.firstWhere((i) => i.job.id == 'done').job.detail,
        '已完成 3 个文件的修改');
  });

  test('items older than the window are left out', () async {
    await task('old', 'failed', ago: const Duration(days: 8));
    await task('new', 'failed', ago: const Duration(days: 6));
    expect((await board.inbox()).map((i) => i.job.id), ['new']);
  });

  test('marking seen hides items until the job changes again', () async {
    await task('t', 'waiting_approval');
    final first = await board.inbox();
    expect(first, hasLength(1));
    await board.markSeen(first);
    expect(await board.unreadCount(), 0);

    await task('t', 'failed', ago: const Duration(minutes: 1));
    final again = await board.inbox();
    expect(again.single.reason, InboxReason.failed);
  });

  test('long results are clipped for previews', () async {
    await scheduledRun('r', 'success', result: 'x' * 500);
    final job = (await board.jobs()).single;
    expect(job.detail!.length, lessThanOrEqualTo(161));
    expect(job.detail, endsWith('…'));
  });

  test('prefs-backed seen store keeps only the most recent keys', () async {
    SharedPreferences.setMockInitialValues({});
    const store = PrefsInboxSeenStore(capacity: 3);
    await store.markSeen(['a', 'b', 'c']);
    await store.markSeen(['d', 'a']);
    expect(await store.seen(), {'c', 'd', 'a'});
  });
}
