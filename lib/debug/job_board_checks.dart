// Fixed debug checks execute inside the approved Android emulator isolate.
// The database and read markers are disposable; no app database or model is used.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/jobs/job_board_providers.dart';
import '../presentation/jobs/jobs_inbox_page.dart';
import '../infrastructure/database/app_database.dart';

bool _registered = false;
void registerJobBoardChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension('ext.nexus.jobBoardFixture', (method, params) async {
    final mode = params['mode'];
    if (mode != 'open' && mode != 'close') {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 'Fixed fixture modes only');
    }
    if (mode == 'close') {
      if (_fixtureRoute != null) _fixtureNavigator?.removeRoute(_fixtureRoute!);
    } else {
      await _openFixture();
    }
    return ServiceExtensionResponse.result(
        jsonEncode({'fixtureOnly': true, 'mode': mode}));
  });
  registerExtension('ext.nexus.jobBoardContract', (method, params) async {
    return ServiceExtensionResponse.result(jsonEncode(await _checks()));
  });
}

Future<Map<String, dynamic>> _checks() async {
  final db = AppDatabase(NativeDatabase.memory());
  final now = DateTime.utc(2026, 10, 19, 12);
  final board = JobBoard(db, seen: InMemoryInboxSeenStore(), clock: () => now);
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() action) async {
    try {
      cases.add({'name': name, 'passed': await action()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  Future<void> task(String id, String status,
      {int days = 0, int revision = 0}) {
    final at = now.subtract(Duration(days: days));
    return db.saveTask(Task(
        id: id,
        conversationId: 'fixture',
        projectId: null,
        stateRevision: revision,
        type: 'agent',
        status: status,
        requestJson: jsonEncode({'title': '隔离验收 $id', 'prompt': '合成数据，不执行'}),
        progressJson: '{}',
        resumeCount: 0,
        createdAt: at,
        updatedAt: at));
  }

  Future<void> audit(String id, String decision, String detail) =>
      db.insertAuditLog(AuditLogsCompanion.insert(
          id: id,
          type: JobBoard.scheduledRunAuditType,
          detail: detail,
          decision: Value(decision),
          createdAt: now));
  JobSummary summary(String id, int revision) => JobSummary(
      id: id,
      kind: JobKind.task,
      title: id,
      phase: JobPhase.needsApproval,
      rawStatus: 'waiting_approval',
      updatedAt: now,
      revision: revision);
  try {
    await check(
        'unknown_task_is_not_silent_or_failed',
        () async =>
            JobBoard.phaseForTaskStatus('future_state') ==
            JobPhase.needsVerification);
    await check(
        'timeout_and_unknown_require_verification',
        () async => ['timeout', 'unknown', 'future_state'].every((s) =>
            JobBoard.phaseForScheduledStatus(s) == JobPhase.needsVerification));
    await check(
        'partial_requires_explicit_state',
        () async =>
            JobBoard.phaseForScheduledStatus('partial') == JobPhase.partial &&
            JobBoard.phaseForScheduledStatus('success',
                    detail: {'result': 'partially done'}) ==
                JobPhase.completed &&
            JobBoard.phaseForTaskStatus('completed_with_errors') ==
                JobPhase.partial);
    await check(
        'explicit_failure_remains_failure',
        () async =>
            JobBoard.phaseForScheduledStatus('failed') == JobPhase.failed);
    await check(
        'legacy_success_without_execution_status',
        () async =>
            JobBoard.phaseForScheduledStatus('success',
                detail: {'status': 'success'}) ==
            JobPhase.completed);
    await check(
        'contradictory_success_is_not_complete',
        () async => [
              <String, dynamic>{'error': 'synthetic'},
              {'executionStatus': 'failed'},
              {'status': 'timeout'},
              {'businessCompleted': false},
              {'needsUserCompletion': true}
            ].every((d) =>
                JobBoard.phaseForScheduledStatus('success', detail: d) ==
                JobPhase.needsVerification));
    await check('damaged_audit_never_shown_as_success', () async {
      await audit('corrupt', 'success', '{broken');
      return (await board.jobs()).single.phase == JobPhase.needsVerification;
    });
    await check('audit_conflict_and_raw_status_preserved', () async {
      await audit(
          'conflict', 'success', '{"status":"failed","result":"synthetic"}');
      final job = (await board.jobs()).firstWhere((j) => j.id == 'conflict');
      return job.phase == JobPhase.needsVerification &&
          job.rawStatus == 'success';
    });
    await check('old_pending_survives_more_than_100_terminal_jobs', () async {
      await task('old-approval', 'waiting_approval', days: 40);
      await task('old-paused', 'paused', days: 40);
      for (var i = 0; i < 110; i++) {
        await task('history-$i', 'completed');
      }
      final pending = await board.attentionJobs();
      return pending.any((j) => j.id == 'old-approval') &&
          pending.any((j) => j.id == 'old-paused') &&
          !(await board.jobs()).any((j) => j.id == 'old-approval') &&
          (await board.inbox()).any((i) => i.job.id == 'old-approval');
    });
    await check('read_does_not_resolve_old_pending', () async {
      final captured = await board.inbox();
      await board.markSeen(captured);
      return !(await board.inbox()).any((i) => i.job.id == 'old-approval') &&
          (await board.attentionJobs()).any((j) => j.id == 'old-approval');
    });
    await check('revision_change_reappears_without_clock_change', () async {
      await task('versioned', 'waiting_approval', revision: 1);
      final captured =
          (await board.inbox()).where((i) => i.job.id == 'versioned').toList();
      await board.markSeen(captured);
      await task('versioned', 'waiting_approval', revision: 2);
      final next =
          (await board.inbox()).where((i) => i.job.id == 'versioned').toList();
      return next.length == 1 && next.single.key != captured.single.key;
    });
    await check('seen_snapshot_preserves_new_arrivals_and_versions', () async {
      final old =
          InboxItem(job: summary('same', 1), reason: InboxReason.needsApproval);
      final changed =
          InboxItem(job: summary('same', 2), reason: InboxReason.needsApproval);
      final arrived =
          InboxItem(job: summary('late', 1), reason: InboxReason.needsApproval);
      final retained =
          JobBoard.remainingAfterSeen([old, changed, arrived], [old]);
      return retained.length == 2 &&
          retained.contains(changed) &&
          retained.contains(arrived);
    });
    await check('bounded_pending_query_and_terminal_exclusion', () async {
      final pending = await board.attentionJobs(limit: 1);
      return pending.length == 1 && pending.every(JobBoard.needsAttention);
    });
    await check('failure_and_cancellation_do_not_promise_rollback', () async {
      for (final phase in [JobPhase.failed, JobPhase.cancelled]) {
        final job = JobSummary(
            id: 'safety',
            kind: JobKind.task,
            title: 'Safety',
            phase: phase,
            rawStatus: phase.name,
            updatedAt: now);
        if (job.safetyNotice == null) return false;
      }
      return true;
    });
  } finally {
    await db.close();
  }
  return {
    'type': 'JobBoardContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((c) => c['passed'] == true).length,
    'total': cases.length
  };
}

Route<void>? _fixtureRoute;
NavigatorState? _fixtureNavigator;
Future<void> _openFixture() async {
  if (_fixtureRoute != null) return;
  NavigatorState? navigator;
  void visit(Element element) {
    if (navigator != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      navigator = element.state as NavigatorState;
    } else {
      element.visitChildElements(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  if (navigator == null) throw StateError('No app navigator');
  final db = AppDatabase(NativeDatabase.memory());
  try {
    final now = DateTime.now();
    for (final entry in {
      'old-approval': 'waiting_approval',
      'partial': 'partial',
      'unknown': 'future_state',
      'paused': 'paused'
    }.entries) {
      await db.saveTask(Task(
          id: entry.key,
          conversationId: 'fixture',
          projectId: null,
          stateRevision: 1,
          type: 'agent',
          status: entry.value,
          requestJson:
              jsonEncode({'title': '隔离样例 ${entry.key}', 'prompt': '不执行任务'}),
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now.subtract(const Duration(days: 40)),
          updatedAt: now.subtract(const Duration(days: 40))));
    }
    final board = JobBoard(db, seen: InMemoryInboxSeenStore());
    final route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
              overrides: [jobBoardProvider.overrideWith((ref) async => board)],
              child: Scaffold(
                  appBar: AppBar(title: const Text('隔离验收 · 任务执行已禁用')),
                  body: JobsInboxPage(onJobSelected: (_) {})),
            ));
    _fixtureRoute = route;
    _fixtureNavigator = navigator;
    unawaited(navigator!.push(route).whenComplete(() async {
      if (identical(_fixtureRoute, route)) {
        _fixtureRoute = null;
        _fixtureNavigator = null;
      }
      await db.close();
    }));
  } catch (_) {
    await db.close();
    rethrow;
  }
}
