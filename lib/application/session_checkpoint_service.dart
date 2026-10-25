// 会话级 checkpoint：每个对话轮次开始前记录“会话 + 代码”起点的时间线。
// 文件内容由各任务的 ChangeSetService 变更集承载，本模块只保存轮次台账，
// 因此体量小、可随会话增长而无需额外清理策略。
import 'dart:convert';
import 'dart:io';
import 'session_operation_guard.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/unique_id.dart';
import 'file_baseline_store.dart' show validateTaskStorageId;
import 'change_set_service.dart';

/// 一次对话轮次开始前的时间线快照。
class SessionCheckpoint {
  const SessionCheckpoint({
    required this.id,
    required this.conversationId,
    required this.workspacePath,
    required this.messageCount,
    required this.createdAt,
    required this.turn,
    this.label = '',
  });

  final String id;
  final String conversationId;

  /// 打点时的项目工作区（可能为空字符串：当时未绑定目录）。
  final String workspacePath;

  /// 打点时会话已有的消息数；“回退会话”仅保留前 N 条。
  final int messageCount;
  final DateTime createdAt;

  /// 本轮是第几轮（从 1 起）；UI 默认文案使用它。
  final int turn;

  /// 可选备注（未设置时 UI 显示 “第 N 轮前”）。
  final String label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'workspacePath': workspacePath,
        'messageCount': messageCount,
        'createdAt': createdAt.toIso8601String(),
        'turn': turn,
        'label': label,
      };

  factory SessionCheckpoint.fromJson(Map<String, dynamic> json) =>
      SessionCheckpoint(
        id: json['id']?.toString() ?? '',
        conversationId: json['conversationId']?.toString() ?? '',
        workspacePath: json['workspacePath']?.toString() ?? '',
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        turn: (json['turn'] as num?)?.toInt() ?? 1,
        label: json['label']?.toString() ?? '',
      );
}

/// 时间线的 JSON 存储（每会话一个文件，整体重写；每轮一条，量级很小）。
class SessionCheckpointStore {
  const SessionCheckpointStore({this.overrideDirectory});
  static final Map<String, Future<void>> _writes = {};

  Future<void> _mutate(String id, Future<void> Function(File) action) async {
    final file = await _file(id);
    final key = file.absolute.path;
    final previous = _writes[key] ?? Future<void>.value();
    final work = previous.catchError((Object error) {
      /* The next write reports its own result. */
    }).then((_) => action(file));
    _writes[key] = work;
    try {
      await work;
    } finally {
      if (identical(_writes[key], work)) {
        final _ = _writes.remove(key);
      }
    }
  }

  Future<void> _publish(File file, List<SessionCheckpoint> values) async {
    final temporary = File('${file.path}.next');
    await temporary.writeAsString(
        jsonEncode(values.map((v) => v.toJson()).toList()),
        flush: true);
    await temporary.rename(file.path);
  }

  /// 测试或特定环境下指定的根目录（未提供时使用应用文档目录）。
  final Directory? overrideDirectory;

  Future<Directory> _root() async {
    if (overrideDirectory != null) {
      final dir = Directory(p.join(overrideDirectory!.path, 'checkpoints'));
      await dir.create(recursive: true);
      return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'checkpoints'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String conversationId) async {
    if (conversationId.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId', '不能为空');
    }
    validateTaskStorageId(conversationId);
    return File(p.join((await _root()).path, '$conversationId.json'));
  }

  Future<List<SessionCheckpoint>> listFor(String conversationId) async {
    final file = await _file(conversationId);
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString());
      return (raw as List<dynamic>)
          .whereType<Map>()
          .map((item) =>
              SessionCheckpoint.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on FormatException {
      throw const FormatException('检查点记录损坏；原文件已保留，请从备份恢复');
    }
  }

  Future<void> append(SessionCheckpoint checkpoint) async {
    await _mutate(checkpoint.conversationId, (file) async {
      final list = [...await listFor(checkpoint.conversationId), checkpoint];
      await _publish(file, list);
    });
  }

  Future<void> remove(String conversationId, String id) async {
    await _mutate(conversationId, (file) async {
      final kept = (await listFor(conversationId))
          .where((item) => item.id != id)
          .toList(growable: false);
      await _publish(file, kept);
    });
  }
}

/// "回退代码" 的汇总：涉及任务数、恢复的文件数与冲突明细。
class CheckpointRewindSummary {
  const CheckpointRewindSummary({
    required this.tasks,
    required this.restored,
    required this.conflicts,
  });

  final int tasks;
  final int restored;
  final List<RollbackConflict> conflicts;

  String get conflictText =>
      conflicts.map((c) => '${c.path}（${c.reason}）').join('、');
}

/// rewindCode 所需的任务投影：避免应用层直接依赖 drift 行类型。
class CheckpointTaskRef {
  const CheckpointTaskRef({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}

/// 会话级 checkpoint：创建与三种回退（回会话 / 回代码 / 两者）。
///
/// - 回会话：`AppDatabase.deleteMessagesByIds` 截断到 [SessionCheckpoint.messageCount]；
/// - 回代码：把 checkpoint 之后创建的任务变更集从新到旧逐个回滚；
/// - 两者：先回代码再回会话（见 UI 层编排）。
class SessionCheckpointService {
  const SessionCheckpointService({
    this.changeSets = const ChangeSetService(),
  });

  final ChangeSetService changeSets;

  /// Validate every task in reverse chronological order without changing disk.
  /// Virtual hashes account for multiple tasks editing the same file.
  Future<CheckpointRewindSummary> preflight(
    SessionCheckpoint checkpoint, {
    required Future<List<CheckpointTaskRef>> Function() tasksAfter,
  }) async {
    final tasks = await tasksAfter();
    final hashes = <String, String>{};
    final conflicts = <RollbackConflict>[];
    var files = 0;
    for (final task in tasks.reversed) {
      final set = await changeSets.load(taskId: task.id);
      if (set == null) continue;
      final skipped = await changeSets.rollback(
          workspacePath: checkpoint.workspacePath,
          changeSet: set,
          currentHashes: hashes,
          dryRun: true);
      conflicts.addAll(skipped);
      final blocked = skipped.map((f) => f.path).toSet();
      for (final file in set.files) {
        if (!blocked.contains(file.relativePath)) {
          hashes[file.relativePath] = file.beforeHash;
          files++;
        }
      }
    }
    return CheckpointRewindSummary(
        tasks: tasks.length, restored: files, conflicts: conflicts);
  }

  Future<T> withRestoreLock<T>(
    SessionCheckpoint checkpoint, {
    required Future<bool> Function() isRunning,
    required Future<T> Function() action,
  }) =>
      SessionOperationGuard.restore(checkpoint.conversationId, () async {
        if (await isRunning()) throw StateError('任务仍在执行，请先停止任务再恢复');
        return action();
      });

  /// 每轮对话开始前打点；同位置重复打点（消息数/工作区均未推进）会被
  /// 跳过，避免自动+手动双重噪声。
  Future<SessionCheckpoint?> recordTurn({
    required SessionCheckpointStore store,
    required String conversationId,
    required String? workspacePath,
    required int messageCount,
    DateTime? now,
  }) async {
    final existing = await store.listFor(conversationId);
    final last = existing.isEmpty ? null : existing.last;
    if (last != null &&
        last.messageCount == messageCount &&
        last.workspacePath == (workspacePath ?? '')) {
      return null;
    }
    final checkpoint = SessionCheckpoint(
      id: UniqueId.generate('checkpoint'),
      conversationId: conversationId,
      workspacePath: workspacePath ?? '',
      messageCount: messageCount,
      createdAt: now ?? DateTime.now(),
      turn: (last?.turn ?? 0) + 1,
    );
    await store.append(checkpoint);
    return checkpoint;
  }

  /// 回退代码：把 checkpoint 之后创建的任务变更集从新到旧逐个回滚。
  /// 无工作区或无任务属于合法的“无代码改动”，返回全零汇总。
  Future<CheckpointRewindSummary> rewindCode(
    SessionCheckpoint checkpoint, {
    required Future<List<CheckpointTaskRef>> Function() tasksAfter,
  }) async {
    if (checkpoint.workspacePath.isEmpty) {
      return const CheckpointRewindSummary(
          tasks: 0, restored: 0, conflicts: []);
    }
    final tasks = await tasksAfter();
    var restored = 0;
    final conflicts = <RollbackConflict>[];
    for (final task in tasks.reversed) {
      final set = await changeSets.load(taskId: task.id);
      if (set == null) continue;
      final skipped = await changeSets.rollback(
          workspacePath: checkpoint.workspacePath, changeSet: set);
      restored += set.files.length - skipped.length;
      conflicts.addAll(skipped);
    }
    return CheckpointRewindSummary(
        tasks: tasks.length, restored: restored, conflicts: conflicts);
  }
}
