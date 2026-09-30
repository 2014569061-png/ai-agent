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
enum JobPhase { queued, running, needsApproval, paused, completed, failed, cancelled, other }

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

  bool get isActive => phase == JobPhase.queued || phase == JobPhase.running;
}

/// 收件箱条目出现的原因。
enum InboxReason { needsApproval, paused, failed, completed, scheduledRun }

/// 需要用户留意的一项。
class InboxItem {
  const InboxItem({required this.job, required this.reason});

  final JobSummary job;
  final InboxReason reason;

  /// 已读标记的键：包含状态与更新时间，任务再次变化时会重新出现。
  String get key =>
      '${job.kind.name}:${job.id}:${job.rawStatus}:${job.updatedAt.millisecondsSinceEpoch}';
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
    await prefs.setStringList(prefsKey, list.sublist(start));
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

  /// 收件箱只看这段时间内变化过的任务。
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

  /// 未读的收件箱条目，按时间倒序。
  Future<List<InboxItem>> inbox() async {
    final since = _clock().subtract(window);
    final seen = await seenStore.seen();
    return [
      for (final job in await jobs())
        if (!job.updatedAt.isBefore(since))
          if (reasonFor(job) case final reason?)
            if (InboxItem(job: job, reason: reason) case final item
                when !seen.contains(item.key))
              item,
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
        JobPhase.failed => InboxReason.failed,
        JobPhase.completed => job.kind == JobKind.scheduledRun
            ? InboxReason.scheduledRun
            : InboxReason.completed,
        _ => null,
      };

  static JobPhase phaseForTaskStatus(String status) => switch (status) {
        'queued' => JobPhase.queued,
        'running' || 'pause_requested' || 'cancel_requested' => JobPhase.running,
        'waiting_approval' || 'awaiting_approval' => JobPhase.needsApproval,
        'paused' => JobPhase.paused,
        'completed' => JobPhase.completed,
        'failed' => JobPhase.failed,
        'cancelled' => JobPhase.cancelled,
        _ => JobPhase.other,
      };

  JobSummary _fromTask(Task task) {
    final info = TaskService().describe(task);
    return JobSummary(
      id: task.id,
      kind: JobKind.task,
      title: info.title,
      phase: phaseForTaskStatus(task.status),
      rawStatus: task.status,
      updatedAt: task.updatedAt,
      conversationId: task.conversationId,
      detail: _clip(info.summary),
    );
  }

  JobSummary _fromScheduledRun(AuditLog row) {
    Map<String, dynamic> detail;
    try {
      detail = Map<String, dynamic>.from(jsonDecode(row.detail) as Map);
    } on Object {
      detail = const {};
    }
    final status = (row.decision ?? detail['status'] ?? 'unknown').toString();
    return JobSummary(
      id: row.id,
      kind: JobKind.scheduledRun,
      title: (detail['taskName'] ?? '定时任务').toString(),
      phase: status == 'success' ? JobPhase.completed : JobPhase.failed,
      rawStatus: status,
      updatedAt: row.createdAt,
      detail: _clip(detail['result']?.toString()),
    );
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
