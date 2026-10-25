import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/database/app_database.dart';
import '../task_service.dart';

/// 任务来源。
enum JobKind {
  /// 聊天或后台发起、写入 Tasks 表的任务。
  task,

  /// 定时任务的一次运行（记录在审计日志 `scheduled_task_run`）。
  scheduledRun,
}

/// 统一后的任务阶段。
enum JobPhase {
  queued,
  running,
  needsApproval,
  paused,
  needsVerification,
  partial,
  completed,
  failed,
  cancelled,
  other
}

/// 任务列表中的一项。
class JobSummary {
  const JobSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.phase,
    required this.rawStatus,
    required this.updatedAt,
    this.conversationId,
    this.detail,
    this.revision,
  });

  final String id;
  final JobKind kind;
  final String title;
  final JobPhase phase;

  /// 数据库里的原始状态，便于排查。
  final String rawStatus;
  final DateTime updatedAt;

  /// 任务所在会话；定时运行没有会话。
  final String? conversationId;

  /// 摘要或结果预览（已截断）。
  final String? detail;
  final int? revision;

  String? get safetyNotice => switch (phase) {
        JobPhase.needsVerification ||
        JobPhase.other =>
          '结果或副作用尚未核实；请先检查记录与实际状态，不要自动重试。',
        JobPhase.partial => '仅部分完成，不代表完整交付；请核对剩余事项。',
        JobPhase.failed => '执行失败不等于副作用已撤销；恢复前请先核对。',
        JobPhase.cancelled => '已取消不等于已回滚；请核对已经产生的变化。',
        _ => null,
      };

  bool get isActive => phase == JobPhase.queued || phase == JobPhase.running;
}

/// 收件箱条目出现的原因。
enum InboxReason {
  needsApproval,
  paused,
  needsVerification,
  partial,
  failed,
  completed,
  scheduledRun
}

/// 需要用户留意的一项。
class InboxItem {
  const InboxItem({required this.job, required this.reason});

  final JobSummary job;
  final InboxReason reason;

  /// 已读标记的键：包含状态与更新时间，任务再次变化时会重新出现。
  String get key {
    final phase =
        job.phase == JobPhase.needsVerification || job.phase == JobPhase.partial
            ? ':${job.phase.name}'
            : '';
    final revision = (job.revision ?? 0) > 0 ? ':r${job.revision}' : '';
    return '${job.kind.name}:${job.id}:${job.rawStatus}$phase$revision:${job.updatedAt.millisecondsSinceEpoch}';
  }
}

/// 收件箱已读状态。
abstract interface class InboxSeenStore {
  Future<Set<String>> seen();
  Future<void> markSeen(Iterable<String> keys);
}

class InMemoryInboxSeenStore implements InboxSeenStore {
  final _seen = <String>{};

  @override
  Future<Set<String>> seen() async => {..._seen};

  @override
  Future<void> markSeen(Iterable<String> keys) async => _seen.addAll(keys);
}

/// 存在 SharedPreferences 里，只保留最近 [capacity] 个键。
class PrefsInboxSeenStore implements InboxSeenStore {
  const PrefsInboxSeenStore({this.capacity = 500});

  static const prefsKey = 'inbox.seen.v1';
  final int capacity;

  @override
  Future<Set<String>> seen() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
  }

  @override
  Future<void> markSeen(Iterable<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(prefsKey) ?? <String>[];
    for (final key in keys) {
      list
        ..remove(key)
        ..add(key);
    }
    final start = list.length > capacity ? list.length - capacity : 0;
    if (!await prefs.setStringList(prefsKey, list.sublist(start))) {
      throw StateError('未能保存已读状态');
    }
  }
}

/// 任务列表与收件箱（阶段 7b）：把 Tasks 表和定时任务运行记录统一成一个视图。
///
/// 只读现有数据，不新增表。协作运行属于某个任务，不单独列出。
class JobBoard {
  JobBoard(
    this.db, {
    InboxSeenStore? seen,
    this.window = const Duration(days: 7),
    DateTime Function()? clock,
  })  : seenStore = seen ?? const PrefsInboxSeenStore(),
        _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final InboxSeenStore seenStore;

  /// 终结结果的收件箱时间窗口；未解决事项不按年龄丢弃。
  final Duration window;
  final DateTime Function() _clock;

  static const _detailChars = 160;
  static const scheduledRunAuditType = 'scheduled_task_run';

  /// 最近的任务与定时运行，按更新时间倒序。
  Future<List<JobSummary>> jobs({int limit = 100}) async {
    final tasks = await db.allTasks(limit: limit);
    final runs = await (db.select(db.auditLogs)
          ..where((row) => row.type.equals(scheduledRunAuditType))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
          ..limit(limit))
        .get();
    final jobs = [
      for (final task in tasks) _fromTask(task),
      for (final run in runs) _fromScheduledRun(run),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return jobs.length > limit ? jobs.sublist(0, limit) : jobs;
  }

  /// Independent bounded view: history traffic and read marks cannot hide
  /// unresolved tasks. This is not a claim of unbounded history pagination.
  Future<List<JobSummary>> attentionJobs({int limit = 100}) async {
    if (limit < 1 || limit > 1000) throw ArgumentError('limit 必须为 1–1000');
    final tasks = await (db.select(db.tasks)
          ..where((row) => row.status.isNotIn(const [
                'queued',
                'running',
                'pause_requested',
                'cancel_requested',
                'completed',
                'failed',
                'cancelled',
              ]))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(limit))
        .get();
    final runs = await (db.select(db.auditLogs)
          ..where((row) =>
              row.type.equals(scheduledRunAuditType) &
              (row.decision.isNull() |
                  row.decision.isNotIn(
                      const ['success', 'failed', 'error', 'cancelled'])))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
          ..limit(limit))
        .get();
    final candidates = <String, JobSummary>{
      for (final task in tasks) 'task:${task.id}': _fromTask(task),
      for (final run in runs) 'scheduledRun:${run.id}': _fromScheduledRun(run),
      // Include recently detected corrupt/conflicting terminal audit records.
      for (final job in await jobs(limit: limit))
        '${job.kind.name}:${job.id}': job,
    };
    final pending = candidates.values.where(needsAttention).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return pending.take(limit).toList();
  }

  static bool needsAttention(JobSummary job) => const {
        JobPhase.needsApproval,
        JobPhase.paused,
        JobPhase.needsVerification,
        JobPhase.partial,
        JobPhase.other,
      }.contains(job.phase);

  /// Unread recent terminal results plus unresolved items outside the window.
  Future<List<InboxItem>> inbox() async {
    final since = _clock().subtract(window);
    final seen = await seenStore.seen();
    final candidates = <String, JobSummary>{
      for (final job in await jobs()) '${job.kind.name}:${job.id}': job,
      for (final job in await attentionJobs())
        '${job.kind.name}:${job.id}': job,
    };
    final ordered = candidates.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final job in ordered)
        if (!job.updatedAt.isBefore(since) || needsAttention(job))
          if (reasonFor(job) case final reason?)
            if (InboxItem(job: job, reason: reason) case final item
                when !seen.contains(item.key))
              item,
    ];
  }

  /// Acknowledge only the captured versions, never items arriving during IO.
  static List<InboxItem> remainingAfterSeen(
      List<InboxItem> current, Iterable<InboxItem> captured) {
    final keys = captured.map((item) => item.key).toSet();
    return [
      for (final item in current)
        if (!keys.contains(item.key)) item
    ];
  }

  Future<int> unreadCount() async => (await inbox()).length;

  /// 打开任务详情用；任务已被删除时返回 null。
  Future<DevelopmentTaskInfo?> findTaskInfo(String id) async {
    final task = await db.findTask(id);
    return task == null ? null : DevelopmentTaskInfo.fromTask(task);
  }

  Future<void> markSeen(Iterable<InboxItem> items) =>
      seenStore.markSeen(items.map((item) => item.key));

  /// 任务处于哪个阶段时需要进收件箱；运行中、排队中、已取消的不进。
  static InboxReason? reasonFor(JobSummary job) => switch (job.phase) {
        JobPhase.needsApproval => InboxReason.needsApproval,
        JobPhase.paused => InboxReason.paused,
        JobPhase.needsVerification ||
        JobPhase.other =>
          InboxReason.needsVerification,
        JobPhase.partial => InboxReason.partial,
        JobPhase.failed => InboxReason.failed,
        JobPhase.completed => job.kind == JobKind.scheduledRun
            ? InboxReason.scheduledRun
            : InboxReason.completed,
        _ => null,
      };

  static JobPhase phaseForTaskStatus(String status) => switch (status) {
        'queued' => JobPhase.queued,
        'running' ||
        'pause_requested' ||
        'cancel_requested' =>
          JobPhase.running,
        'waiting_approval' || 'awaiting_approval' => JobPhase.needsApproval,
        'paused' => JobPhase.paused,
        'completed' => JobPhase.completed,
        'partial' ||
        'partially_completed' ||
        'completed_with_errors' =>
          JobPhase.partial,
        'failed' => JobPhase.failed,
        'cancelled' => JobPhase.cancelled,
        _ => JobPhase.needsVerification,
      };

  JobSummary _fromTask(Task task) {
    final info = TaskService().describe(task);
    return JobSummary(
      id: task.id,
      kind: JobKind.task,
      title: info.title,
      phase: phaseForTaskStatus(task.status),
      rawStatus: task.status,
      revision: task.stateRevision,
      updatedAt: task.updatedAt,
      conversationId: task.conversationId,
      detail: _clip(info.summary),
    );
  }

  JobSummary _fromScheduledRun(AuditLog row) {
    Map<String, dynamic> detail;
    var validDetail = true;
    try {
      if (row.detail.length > 65536) throw const FormatException();
      detail = Map<String, dynamic>.from(jsonDecode(row.detail) as Map);
    } on Object {
      detail = const {};
      validDetail = false;
    }
    final status = (row.decision ?? detail['status'] ?? 'unknown').toString();
    return JobSummary(
      id: row.id,
      kind: JobKind.scheduledRun,
      title: (detail['taskName'] ?? '定时任务').toString(),
      phase: phaseForScheduledStatus(status,
          detail: detail, validDetail: validDetail),
      rawStatus: status,
      updatedAt: row.createdAt,
      detail: _clip(detail['result']?.toString()),
    );
  }

  static JobPhase phaseForScheduledStatus(
    String status, {
    Map<String, dynamic> detail = const {},
    bool validDetail = true,
  }) {
    if (!validDetail ||
        (detail.containsKey('status') && detail['status'] != status) ||
        detail['effect'] == 'unknown' ||
        detail['resultEffect'] == 'unknown') {
      return JobPhase.needsVerification;
    }
    if (status == 'success' &&
        ((detail['error'] != null && detail['error'] != '') ||
            (detail.containsKey('executionStatus') &&
                detail['executionStatus'] != 'completed') ||
            detail['businessCompleted'] == false ||
            detail['needsUserCompletion'] == true)) {
      return JobPhase.needsVerification;
    }
    return switch (status) {
      'success' => JobPhase.completed,
      'paused' => JobPhase.paused,
      'cancelled' => JobPhase.cancelled,
      'failed' || 'error' => JobPhase.failed,
      'partial' ||
      'partially_completed' ||
      'completed_with_errors' =>
        JobPhase.partial,
      _ => JobPhase.needsVerification,
    };
  }

  static String? _clip(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > _detailChars
        ? '${trimmed.substring(0, _detailChars)}…'
        : trimmed;
  }
}
