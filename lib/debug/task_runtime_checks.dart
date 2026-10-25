import 'dart:convert';
import 'dart:developer';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import '../application/development_execution_service.dart';
import '../application/task_service.dart';
import '../infrastructure/database/app_database.dart';

bool _registered = false;
void registerTaskRuntimeChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.taskRuntimeContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
}

Future<Map<String, dynamic>> _checks() async {
  final db = AppDatabase(NativeDatabase.memory());
  final tasks = TaskService();
  final executor = DevelopmentExecutionService(db: db);
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  Future<bool> rejects(Future<dynamic> Function() action) async {
    try {
      await action();
      return false;
    } catch (_) {
      return true;
    }
  }

  final now = DateTime.utc(2026, 10, 19);
  Task row(String id, String request, DateTime at) => Task(
      id: id,
      conversationId: 'fixture-conversation',
      projectId: null,
      stateRevision: 0,
      type: 'agent',
      status: 'running',
      requestJson: request,
      progressJson: '{}',
      resumeCount: 0,
      createdAt: at,
      updatedAt: at);
  TaskControlRequest control(String id, String task,
          {TaskControlKind kind = TaskControlKind.followUp,
          Map<String, dynamic> payload = const {}}) =>
      TaskControlRequest(
          taskId: task, kind: kind, clientControlId: id, payload: payload);
  try {
    await db.saveTask(
        row('old', '{"requestId":"old-request"}', DateTime.utc(2020)));
    for (var i = 0; i < 410; i++) {
      await db.saveTask(row('recent-$i', '{}', now));
    }
    await check(
        'request_id_search_has_no_recent_400_cap',
        () async =>
            (await tasks.findByRequestId(db, 'old-request'))?.id == 'old');
    await check('request_id_is_exact_bound_json_string', () async {
      const id = "literal %_ ' request";
      await db.saveTask(row('literal', jsonEncode({'requestId': id}), now));
      return (await tasks.findByRequestId(db, id))?.id == 'literal' &&
          await tasks.findByRequestId(db, 'literal') == null;
    });
    await check('malformed_legacy_request_does_not_abort_lookup', () async {
      await db.saveTask(row('broken', '{malformed request', now));
      return (await tasks.findByRequestId(db, 'old-request'))?.id == 'old';
    });
    await check('concurrent_enqueue_reuses_single_task', () async {
      const request = DevelopmentTaskRequest(
          prompt: 'fixture',
          conversationId: 'fixture-conversation',
          requestId: 'parallel-request');
      final results = await Future.wait(
          [executor.enqueue(request), executor.enqueue(request)]);
      return results.first.taskId == results.last.taskId;
    });
    await check(
        'request_id_cannot_cross_conversation_scope',
        () async => rejects(() => executor.enqueue(const DevelopmentTaskRequest(
            prompt: 'other',
            conversationId: 'other-conversation',
            requestId: 'parallel-request'))));
    await check('late_controls_cannot_regress_terminal_task', () async {
      await tasks.updateStatus(db, 'old', 'completed');
      for (final kind in TaskControlKind.values) {
        final receipt = await executor
            .submitControl(control('late-${kind.name}', 'old', kind: kind));
        if (receipt.status != 'rejected') return false;
      }
      return (await db.findTask('old'))?.status == 'completed' &&
          (await db.pendingRunControls(taskId: 'old')).isEmpty;
    });
    await check('identical_control_id_returns_same_receipt', () async {
      final request = control('same-control', 'recent-0',
          payload: {'text': 'read-only correction'});
      final first = await executor.submitControl(request);
      final duplicate = await executor.submitControl(request);
      return !first.duplicate &&
          duplicate.duplicate &&
          first.id == duplicate.id;
    });
    await check(
        'same_control_id_with_changed_payload_is_rejected',
        () async =>
            (await executor.submitControl(control('same-control', 'recent-0',
                    payload: {'text': 'changed object'})))
                .status ==
            'rejected');
    await check(
        'control_id_is_bound_to_original_task',
        () async =>
            (await executor.submitControl(control('same-control', 'recent-1',
                    payload: {'text': 'read-only correction'})))
                .status ==
            'rejected');
    await check('concurrent_controls_have_distinct_persisted_sequence',
        () async {
      await Future.wait([
        executor.submitControl(control('sequence-a', 'recent-2')),
        executor.submitControl(control('sequence-b', 'recent-2'))
      ]);
      final rows = await db.pendingRunControls(taskId: 'recent-2');
      return rows.length == 2 &&
          rows.map((r) => r.sequenceNo).toSet().length == 2;
    });
    await check('cancel_request_is_not_execution_stopped', () async {
      final receipt = await executor.submitControl(
          control('request-cancel', 'recent-3', kind: TaskControlKind.cancel));
      return receipt.status == 'pending' &&
          (await db.findTask('recent-3'))?.status == 'cancel_requested';
    });
    await check('oversized_or_empty_controls_rejected_before_persistence',
        () async {
      final a =
          await rejects(() => executor.submitControl(control('', 'recent-4')));
      final b = await rejects(() => executor.submitControl(
          control('oversize', 'recent-4', payload: {'text': 'x' * 17000})));
      return a &&
          b &&
          (await db.pendingRunControls(taskId: 'recent-4')).isEmpty;
    });

    await check('existing_snapshot_cas_increments_revision', () async {
      final initial = row('cas', '{}', now);
      await db.saveTask(initial);
      final accepted =
          await db.updateTaskSnapshot(initial.copyWith(status: 'paused'));
      final current = await db.findTask(initial.id);
      return accepted &&
          current?.stateRevision == 1 &&
          current?.status == 'paused';
    });
    await check('stale_snapshot_cannot_overwrite_newer_state', () async {
      final stale = row('cas', '{}', now);
      final accepted =
          await db.updateTaskSnapshot(stale.copyWith(status: 'failed'));
      return !accepted && (await db.findTask('cas'))?.status == 'paused';
    });
    await check('deleted_task_is_not_recreated_by_late_snapshot', () async {
      final snapshot = row('deleted', '{}', now);
      await db.saveTask(snapshot);
      await db.deleteTask(snapshot.id);
      return !await db.updateTaskSnapshot(snapshot) &&
          await db.findTask(snapshot.id) == null;
    });
    await check('concurrent_progress_updates_preserve_both_fields', () async {
      await db.saveTask(row('progress', '{}', now));
      await Future.wait([
        tasks.updateProgress(db, 'progress',
            phase: 'running', extra: {'one': true}),
        tasks.updateProgress(db, 'progress',
            phase: 'running', extra: {'two': true}),
      ]);
      final p = await tasks.progress(db, 'progress');
      return p['one'] == true &&
          p['two'] == true &&
          (await db.findTask('progress'))?.stateRevision == 2;
    });
    await check('concurrent_resume_count_has_no_lost_increment', () async {
      await db.saveTask(row('resumed', '{}', now));
      await Future.wait(
          [tasks.markResumed(db, 'resumed'), tasks.markResumed(db, 'resumed')]);
      final current = await db.findTask('resumed');
      return current?.resumeCount == 2 && current?.stateRevision == 2;
    });
    await check('clear_checkpoint_preserves_other_progress', () async {
      await tasks.updateProgress(db, 'progress',
          phase: 'paused', checkpoint: {'runId': 'checkpoint-run'});
      await tasks.clearCheckpoint(db, 'progress');
      final p = await tasks.progress(db, 'progress');
      return !p.containsKey('checkpoint') &&
          p['one'] == true &&
          p['two'] == true;
    });
    await check('duplicate_terminal_ack_keeps_first_summary', () async {
      await db.saveTask(row('ack', '{}', now));
      await tasks.complete(db, 'ack',
          status: 'completed', summary: 'first evidence', runId: 'same-run');
      await tasks.complete(db, 'ack',
          status: 'completed', summary: 'late overwrite', runId: 'same-run');
      final p = await tasks.progress(db, 'ack');
      return p['summary'] == 'first evidence' &&
          (await db.findTask('ack'))?.stateRevision == 1;
    });
    await check('concurrent_applied_run_ack_has_one_winner', () async {
      await db.saveTask(row('applied', '{}', now));
      final results = await Future.wait([
        tasks.markRunApplied(db, 'applied', 'one-run'),
        tasks.markRunApplied(db, 'applied', 'one-run')
      ]);
      return results.where((v) => v).length == 1 &&
          (await db.findTask('applied'))?.stateRevision == 1;
    });
  } finally {
    await db.close();
  }
  return {
    'type': 'TaskRuntimeContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((c) => c['passed'] == true).length,
    'total': cases.length
  };
}
