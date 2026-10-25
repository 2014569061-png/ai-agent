import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/tool_result.dart';
import 'app_database.dart';

/// Durable identity of a plan, distinct from a UI-local turn counter.
class RunPlanToken {
  const RunPlanToken(this.taskId, this.runId, this.version);
  final String taskId, runId;
  final int version;
}

class RunPlanHead {
  const RunPlanHead(this.token, this.state, this.pendingControls);
  final RunPlanToken token;
  final String state;
  final bool pendingControls;
}

class RunPlanControlBatch {
  const RunPlanControlBatch(this.head, this.controls);
  final RunPlanHead head;
  final List<RunControl> controls;
}

enum RunDispatchClaim { granted, superseded, duplicate }

class RunPlanConflict implements Exception {
  const RunPlanConflict();
}

/// Storage protocol only. Reuses run_controls and the existing executor; never
/// executes a tool, decides an approval, or claims to undo a dispatched action.
class RunPlanStore {
  RunPlanStore(this.db);
  final AppDatabase db;
  static const _terminal = {'completed', 'failed', 'cancelled'};
  static const _controlKinds = {'followUp', 'pause', 'resume', 'cancel'};
  String _encode(Map<String, dynamic> payload) {
    final encoded = jsonEncode(payload);
    if (utf8.encode(encoded).length > 16384) {
      throw const FormatException('计划修订内容过大');
    }
    return encoded;
  }

  Future<RunPlanHead?> head(String taskId) async {
    final row = await db.customSelect(
        'SELECT * FROM run_plan_heads WHERE task_id = ?',
        variables: [Variable<String>(taskId)]).getSingleOrNull();
    return row == null
        ? null
        : RunPlanHead(
            RunPlanToken(
                taskId, row.read<String>('run_id'), row.read<int>('version')),
            row.read<String>('state'),
            row.read<int>('pending_controls') != 0);
  }

  Future<void> _requireTask(String taskId) async {
    final task = await db.findTask(taskId);
    if (task == null || _terminal.contains(task.status)) {
      throw const RunPlanConflict();
    }
  }

  Future<RunPlanToken> bind(
          {required String taskId,
          required String runId,
          String? expectedPreviousRunId}) =>
      db.transaction(() async {
        if (runId.trim().isEmpty || runId.length > 256) {
          throw const FormatException('运行标识无效');
        }
        await _requireTask(taskId);
        final previous = await head(taskId);
        if (previous != null &&
            previous.token.runId == runId &&
            previous.state != 'queued') {
          if (_terminal.contains(previous.state)) throw const RunPlanConflict();
          return previous.token;
        }
        if (previous != null &&
            previous.token.runId.isNotEmpty &&
            previous.state != 'queued' &&
            (previous.state == 'running' ||
                previous.state == 'paused' ||
                expectedPreviousRunId != previous.token.runId)) {
          throw const RunPlanConflict();
        }
        // A fresh run id is not permission to replay an earlier unknown effect.
        final unresolved = await db.customSelect(
            "SELECT 1 FROM run_dispatch_claims WHERE task_id=? AND "
            "(state<>'settled' OR effect NOT IN ('none','applied')) LIMIT 1",
            variables: [Variable<String>(taskId)]).get();
        if (unresolved.isNotEmpty) throw const RunPlanConflict();
        final version = (previous?.token.version ?? 0) + 1;
        await db.customStatement(
            "UPDATE run_controls SET status = 'superseded', consumed_at = ? "
            "WHERE task_id = ? AND status = 'pending' AND run_id IS NOT NULL AND run_id <> ?",
            [DateTime.now().millisecondsSinceEpoch ~/ 1000, taskId, runId]);
        final pending =
            await db.pendingRunControls(taskId: taskId, runId: runId);
        await _writeHead(RunPlanHead(RunPlanToken(taskId, runId, version),
            'running', pending.isNotEmpty));
        await _append(taskId, runId, version, 'start', null, const {});
        return RunPlanToken(taskId, runId, version);
      });
  Future<bool> acceptsControl(String taskId, String? runId) async {
    final current = await head(taskId);
    return current == null ||
        (!_terminal.contains(current.state) &&
            current.state != 'interrupted' &&
            (runId == null ||
                current.token.runId.isEmpty ||
                current.token.runId == runId));
  }

  /// Called in the same transaction that inserts the original run_control row.
  Future<RunPlanToken> stageControl(RunControl control) =>
      db.transaction(() async {
        await _requireTask(control.taskId);
        if (!_controlKinds.contains(control.kind) ||
            !await acceptsControl(control.taskId, control.runId)) {
          throw const RunPlanConflict();
        }
        final duplicate = await db.customSelect(
            'SELECT version FROM plan_revisions WHERE control_id = ?',
            variables: [Variable<String>(control.id)]).getSingleOrNull();
        if (duplicate != null) return (await head(control.taskId))!.token;
        final persisted =
            await db.findRunControlByClientId(control.clientControlId);
        if (persisted?.id != control.id ||
            persisted?.taskId != control.taskId ||
            control.status != 'pending') {
          throw const RunPlanConflict();
        }
        final previous = await head(control.taskId);
        final runId = previous?.token.runId ?? control.runId ?? '';
        final version = (previous?.token.version ?? 0) + 1;
        final payload = jsonDecode(control.payloadJson);
        if (payload is! Map<String, dynamic>) {
          throw const FormatException('控制请求格式错误');
        }
        _encode(payload);
        await _writeHead(RunPlanHead(
            RunPlanToken(control.taskId, runId, version),
            previous?.state ?? 'queued',
            true));
        await _append(
            control.taskId, runId, version, control.kind, control.id, payload);
        return RunPlanToken(control.taskId, runId, version);
      });
  Future<void> _writeHead(RunPlanHead value) => db.customStatement(
          'INSERT INTO run_plan_heads (task_id, run_id, version, state, pending_controls) VALUES (?, ?, ?, ?, ?) '
          'ON CONFLICT (task_id) DO UPDATE SET run_id=excluded.run_id, version=excluded.version, '
          'state=excluded.state, pending_controls=excluded.pending_controls',
          [
            value.token.taskId,
            value.token.runId,
            value.token.version,
            value.state,
            value.pendingControls ? 1 : 0
          ]);
  Future<void> _append(String taskId, String runId, int version, String kind,
          String? controlId, Map<String, dynamic> payload) =>
      db.customStatement(
          'INSERT INTO plan_revisions (task_id, version, run_id, kind, control_id, payload_json, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            taskId,
            version,
            runId,
            kind,
            controlId,
            _encode(payload),
            DateTime.now().toUtc().toIso8601String()
          ]);
  Future<bool> isCurrent(RunPlanToken token) => db.transaction(() async {
        final task = await db.findTask(token.taskId);
        final current = await head(token.taskId);
        return task != null &&
            !_terminal.contains(task.status) &&
            current != null &&
            current.token.runId == token.runId &&
            current.token.version == token.version &&
            current.state == 'running' &&
            !current.pendingControls;
      });

  /// Atomically consumes this run's inbox and returns its new durable generation.
  /// The executor must still apply text/pausing to its existing controller.
  Future<RunPlanControlBatch> consume(String taskId, String runId) =>
      db.transaction(() async {
        await _requireTask(taskId);
        final current = await head(taskId);
        if (current == null ||
            current.token.runId != runId ||
            (_terminal.contains(current.state) ||
                current.state == 'interrupted')) {
          throw const RunPlanConflict();
        }
        final rows = await db.pendingRunControls(taskId: taskId, runId: runId);
        if (current.pendingControls && rows.isEmpty) {
          throw const RunPlanConflict();
        }
        var state = current.state;
        final consumed = <RunControl>[];
        for (final row in rows) {
          final known =
              _controlKinds.contains(row.kind) && state != 'cancelled';
          if (known) {
            if (row.kind == 'pause') state = 'paused';
            if (row.kind == 'resume') state = 'running';
            if (row.kind == 'cancel') state = 'cancelled';
            consumed.add(row);
          }
          await db.saveRunControl(row.copyWith(
              status: known ? 'consumed' : 'rejected',
              consumedAt: Value(DateTime.now())));
        }
        final updated = RunPlanHead(current.token, state, false);
        await _writeHead(updated);
        return RunPlanControlBatch(updated, List.unmodifiable(consumed));
      });

  /// The claim and control append share SQLite write ordering. If a correction
  /// wins, no dispatch; if this claim wins, later correction cannot promise undo.
  Future<RunDispatchClaim> claim(RunPlanToken token, String callId) =>
      db.transaction(() async {
        if (callId.trim().isEmpty || callId.length > 256) {
          throw const FormatException('调用标识无效');
        }
        if (!await isCurrent(token)) return RunDispatchClaim.superseded;
        final old = await db.customSelect(
            'SELECT state FROM run_dispatch_claims WHERE run_id=? AND call_id=?',
            variables: [
              Variable<String>(token.runId),
              Variable<String>(callId)
            ]).getSingleOrNull();
        if (old != null) return RunDispatchClaim.duplicate;
        await db.customStatement(
            'INSERT INTO run_dispatch_claims '
            '(run_id, call_id, task_id, plan_version, state, effect, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              token.runId,
              callId,
              token.taskId,
              token.version,
              'dispatched',
              'unknown',
              DateTime.now().toUtc().toIso8601String()
            ]);
        return RunDispatchClaim.granted;
      });

  /// Always retain the fact of an old in-flight completion, without writing its
  /// result into the new plan or resurrecting a removed task.
  Future<bool> settle(
          RunPlanToken token, String callId, ToolEffect effect) async =>
      await db.customUpdate(
          "UPDATE run_dispatch_claims SET state='settled', effect=?, settled_at=? "
          "WHERE task_id=? AND run_id=? AND call_id=? AND plan_version=? AND state='dispatched'",
          variables: [
            Variable<String>(effect.name),
            Variable<String>(DateTime.now().toUtc().toIso8601String()),
            Variable<String>(token.taskId),
            Variable<String>(token.runId),
            Variable<String>(callId),
            Variable<int>(token.version)
          ]) ==
      1;
  Future<bool> interrupt(RunPlanToken token) => db.transaction(() async {
        final current = await head(token.taskId);
        if (current == null ||
            current.token.runId != token.runId ||
            current.token.version != token.version ||
            _terminal.contains(current.state)) {
          return false;
        }
        await _writeHead(
            RunPlanHead(current.token, 'interrupted', current.pendingControls));
        return true;
      });
  Future<bool> finish(RunPlanToken token, String state) =>
      db.transaction(() async {
        if (!_terminal.contains(state)) throw const FormatException('运行终态无效');
        if (!await isCurrent(token)) return false;
        final pending = await db.customSelect(
            "SELECT 1 FROM run_dispatch_claims WHERE run_id=? AND state='dispatched' LIMIT 1",
            variables: [Variable<String>(token.runId)]).get();
        if (pending.isNotEmpty) return false;
        await _writeHead(RunPlanHead(token, state, false));
        return true;
      });
  Future<List<Map<String, dynamic>>> history(String taskId,
      {int afterVersion = 0, int limit = 50}) async {
    if (afterVersion < 0 || limit < 1 || limit > 100) {
      throw const FormatException('分页参数无效');
    }
    return [
      for (final row in await db.customSelect(
          'SELECT * FROM plan_revisions '
          'WHERE task_id=? AND version>? ORDER BY version LIMIT ?',
          variables: [
            Variable<String>(taskId),
            Variable<int>(afterVersion),
            Variable<int>(limit)
          ]).get())
        Map<String, dynamic>.unmodifiable(row.data)
    ];
  }
}
