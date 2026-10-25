import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/unique_id.dart';
import '../infrastructure/observability/unified_diff.dart';
import '../infrastructure/tools/workspace_tools.dart';
import 'change_review.dart';
import 'file_baseline_store.dart';

class ChangeSetFile {
  const ChangeSetFile({
    required this.relativePath,
    required this.operation,
    required this.beforeHash,
    required this.afterHash,
    this.beforeRef,
    this.afterRef,
    this.reversible = true,
    this.note,
  });

  final String relativePath;
  final String operation;

  /// sha256 of the content the task started from ('' when the task created
  /// the file or the baseline could not be reconstructed).
  final String beforeHash;

  /// sha256 of the content right after the task ('' when absent).
  final String afterHash;
  final String? beforeRef;
  final String? afterRef;
  final bool reversible;

  /// Why the file is not reversible; shown to the user.
  final String? note;

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'operation': operation,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
        if (beforeRef != null) 'beforeRef': beforeRef,
        if (afterRef != null) 'afterRef': afterRef,
        'reversible': reversible,
        if (note != null) 'note': note,
      };

  factory ChangeSetFile.fromJson(Map<String, dynamic> json) => ChangeSetFile(
        relativePath: json['relativePath']?.toString() ?? '',
        operation: json['operation']?.toString() ?? 'edit',
        beforeHash: json['beforeHash']?.toString() ?? '',
        afterHash: json['afterHash']?.toString() ?? '',
        beforeRef: json['beforeRef']?.toString(),
        afterRef: json['afterRef']?.toString(),
        reversible: json['reversible'] != false,
        note: json['note']?.toString(),
      );
}

class ChangeSet {
  const ChangeSet({
    required this.id,
    required this.taskId,
    required this.projectId,
    required this.files,
    required this.createdAt,
    this.version = currentVersion,
  });

  /// v1 never stored a baseline; v2 reconstructs and verifies it at capture.
  static const currentVersion = 2;

  final String id;
  final String taskId;
  final String projectId;
  final List<ChangeSetFile> files;
  final DateTime createdAt;
  final int version;

  Map<String, dynamic> toJson() => {
        'version': version,
        'id': id,
        'taskId': taskId,
        'projectId': projectId,
        'files': files.map((file) => file.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChangeSet.fromJson(Map<String, dynamic> json) => ChangeSet(
        version: (json['version'] as num?)?.toInt() ?? 1,
        id: json['id']?.toString() ?? '',
        taskId: json['taskId']?.toString() ?? '',
        projectId: json['projectId']?.toString() ?? '',
        files: (json['files'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                ChangeSetFile.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class RollbackConflict {
  const RollbackConflict({required this.path, required this.reason});
  final String path;
  final String reason;
}

/// Result of reconstructing one file's pre-task content.
class _Baseline {
  const _Baseline.create()
      : content = null,
        ref = null,
        hash = null,
        note = null,
        isCreate = true;
  const _Baseline.restore(String this.content)
      : ref = null,
        hash = null,
        note = null,
        isCreate = false;

  /// Original bytes saved by [FileBaselineStore] before the first mutation.
  const _Baseline.stored(String this.ref, String this.hash)
      : content = null,
        note = null,
        isCreate = false;
  const _Baseline.irreversible(String this.note)
      : content = null,
        ref = null,
        hash = null,
        isCreate = false;

  final String? content;
  final String? ref;
  final String? hash;
  final String? note;
  final bool isCreate;
  bool get reversible => note == null;
}

class ChangeSetService {
  const ChangeSetService();

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'changesets'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifest(String taskId) async {
    validateTaskStorageId(taskId);
    return File(p.join((await _root()).path, taskId, 'changeset.json'));
  }

  /// Returns the change set persisted for [taskId], or `null` when none exists
  /// or it was written by v1 (which never stored a baseline).
  ///
  /// Callers should prefer this over [capture]: re-capturing after the user
  /// edited files would move the "after" baseline onto the human edits.
  Future<ChangeSet?> load({required String taskId}) async {
    final file = await _manifest(taskId);
    if (!await file.exists()) return null;
    try {
      final set = ChangeSet.fromJson(
          Map<String, dynamic>.from(jsonDecode(await file.readAsString())));
      return set.version >= ChangeSet.currentVersion ? set : null;
    } catch (_) {
      return null;
    }
  }

  /// Returns the persisted change set for [taskId], capturing a new one when
  /// none exists or the task has mutated files since it was captured.
  Future<ChangeSet> loadOrCapture({
    required String projectId,
    required String taskId,
    required String workspacePath,
    required ChangeReview review,
  }) async {
    final cached = await load(taskId: taskId);
    if (cached != null) {
      final known = {for (final file in cached.files) file.relativePath};
      final baselineAt = await FileBaselineStore.lastModified(taskId);
      final stale = review.files
              .any((f) => !known.contains(normalizeWorkspacePath(f.path))) ||
          (baselineAt != null && baselineAt.isAfter(cached.createdAt));
      if (!stale) return cached;
    }
    return capture(
      projectId: projectId,
      taskId: taskId,
      workspacePath: workspacePath,
      review: review,
    );
  }

  /// Snapshots the task's end state and determines each file's pre-task
  /// content: the original saved by [FileBaselineStore] when available,
  /// otherwise reconstructed by reverse-applying recorded diffs (newest first).
  ///
  /// A file is only marked reversible when the baseline is exact; otherwise it
  /// carries a [ChangeSetFile.note] explaining why.
  Future<ChangeSet> capture({
    required String projectId,
    required String taskId,
    required String workspacePath,
    required ChangeReview review,
  }) async {
    validateTaskStorageId(taskId);
    final sandbox = WorkspaceSandbox(workspacePath);
    final files = <ChangeSetFile>[];
    final objectDir = Directory(p.join((await _root()).path, taskId));
    await objectDir.create(recursive: true);

    final byPath = <String, List<FileChangeSummary>>{};
    for (final change in review.files) {
      byPath
          .putIfAbsent(normalizeWorkspacePath(change.path), () => [])
          .add(change);
    }
    final stored = await FileBaselineStore.read(taskId);
    for (final path in stored.keys) {
      byPath.putIfAbsent(path, () => []);
    }

    for (final entry in byPath.entries) {
      final path = entry.key;
      final changes = entry.value;
      // Flattening paths aliases a/b.txt and a_b.txt. Hash the full normalized
      // path so every file keeps its own snapshots, including on Windows.
      final stem =
          p.join(objectDir.path, sha256.convert(utf8.encode(path)).toString());
      List<int>? bytes;
      String afterHash = '';
      String? afterRef;
      _Baseline baseline;
      try {
        final current = File(sandbox.resolvePath(path));
        if (await current.exists()) {
          bytes = await current.readAsBytes();
          afterHash = sha256.convert(bytes).toString();
          afterRef = '$stem.after';
          await File(afterRef).writeAsBytes(bytes, flush: true);
        }
        final entry = stored[path];
        if (entry != null && changes.isEmpty) {
          // Touched by a tool but absent from the review (e.g. a move source,
          // or a call that failed). Skip when nothing actually changed.
          final unchanged = entry.existed
              ? entry.captured && entry.hash == afterHash
              : bytes == null;
          if (unchanged) continue;
        }
        baseline = _fromStore(entry) ??
            (changes.isEmpty
                ? _Baseline.irreversible(entry?.note ?? '缺少改动记录')
                : _reconstruct(changes, bytes));
      } catch (error) {
        baseline = _Baseline.irreversible('读取失败：$error');
      }

      String beforeHash = baseline.hash ?? '';
      String? beforeRef = baseline.ref;
      final content = baseline.content;
      if (content != null) {
        final beforeBytes = utf8.encode(content);
        beforeHash = sha256.convert(beforeBytes).toString();
        beforeRef = '$stem.before';
        await File(beforeRef).writeAsBytes(beforeBytes, flush: true);
      }
      files.add(ChangeSetFile(
        relativePath: path,
        operation: _operationLabel(baseline, changes),
        beforeHash: beforeHash,
        afterHash: afterHash,
        beforeRef: beforeRef,
        afterRef: afterRef,
        reversible: baseline.reversible,
        note: baseline.note,
      ));
    }
    final set = ChangeSet(
      id: UniqueId.generate('cs'),
      taskId: taskId,
      projectId: projectId,
      files: files,
      createdAt: DateTime.now(),
    );
    await File(p.join(objectDir.path, 'changeset.json'))
        .writeAsString(jsonEncode(set.toJson()), flush: true);
    return set;
  }

  static String _operationLabel(
      _Baseline baseline, List<FileChangeSummary> changes) {
    if (baseline.isCreate) return 'create';
    if (changes.isEmpty) return 'modified';
    final first = changes.first.operation;
    // write_file labels an existing-but-empty file as 'create'; the stored
    // baseline proved it existed, so undo must restore rather than delete.
    return first == 'create' ? 'write' : first;
  }

  static _Baseline? _fromStore(FileBaselineEntry? entry) {
    if (entry == null || !entry.captured) return null;
    if (!entry.existed) return const _Baseline.create();
    final ref = entry.ref;
    final hash = entry.hash;
    if (ref == null || hash == null) return null;
    return _Baseline.stored(ref, hash);
  }

  _Baseline _reconstruct(List<FileChangeSummary> changes, List<int>? bytes) {
    final ops = changes.map((c) => c.operation).toSet();
    if (ops.contains('binary')) return const _Baseline.irreversible('二进制文件');
    if (ops.contains('delete') || ops.contains('move')) {
      return const _Baseline.irreversible('包含删除或移动，暂不支持自动回退');
    }
    // The task brought the file into existence: undo means delete it.
    if (changes.first.operation == 'create') return const _Baseline.create();
    if (bytes == null) return const _Baseline.irreversible('文件已不存在');

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return const _Baseline.irreversible('不是 UTF-8 文本');
    }
    var redacted = false;
    for (final change in changes.reversed) {
      if (change.diff.isEmpty) {
        if (change.linesAdded == 0 && change.linesRemoved == 0) continue;
        return const _Baseline.irreversible('缺少改动记录（diff）');
      }
      if (change.truncated) {
        return const _Baseline.irreversible('改动过大，记录已截断');
      }
      redacted = redacted || change.diff.contains('[REDACTED]');
      final previous = applyUnifiedDiff(text, change.diff, reverse: true);
      if (previous == null) {
        return const _Baseline.irreversible('当前内容与任务记录不一致，可能已被人工修改');
      }
      text = previous;
    }
    final expected = changes.first.contentHashBefore;
    if (expected != null) {
      final actual = sha256.convert(utf8.encode(text)).toString();
      if (actual != expected) {
        return const _Baseline.irreversible('重建的改动前内容校验失败');
      }
    } else if (redacted) {
      // Without a hash we cannot tell a redacted secret from the real text.
      return const _Baseline.irreversible('改动记录含脱敏内容，无法可靠重建');
    }
    return _Baseline.restore(text);
  }

  static Future<String> _hashOf(File file) async {
    if (!await file.exists()) return '';
    return sha256.convert(await file.readAsBytes()).toString();
  }

  /// Restores every reversible file to its pre-task content.
  ///
  /// The current content is hashed from disk unless [currentHashes] supplies
  /// it; any file that no longer matches the task's end state is reported as a
  /// conflict instead of being overwritten.
  Future<List<RollbackConflict>> rollback({
    required String workspacePath,
    required ChangeSet changeSet,
    Map<String, String>? currentHashes,
    bool dryRun = false,
  }) async {
    final conflicts = <RollbackConflict>[];
    final sandbox = WorkspaceSandbox(workspacePath);
    final journal = <String>[];
    for (final file in changeSet.files) {
      if (!file.reversible) {
        conflicts.add(RollbackConflict(
            path: file.relativePath, reason: file.note ?? '不可自动回退'));
        continue;
      }
      final target = File(sandbox.resolvePath(file.relativePath));
      final currentHash =
          currentHashes?[file.relativePath] ?? await _hashOf(target);
      if (currentHash != file.afterHash) {
        conflicts.add(RollbackConflict(
          path: file.relativePath,
          reason: '人工后续修改，拒绝静默覆盖',
        ));
        continue;
      }
      try {
        if (file.operation == 'create') {
          if (!dryRun && await target.exists()) await target.delete();
          journal.add('deleted:${file.relativePath}');
          continue;
        }
        final beforeRef = file.beforeRef;
        if (beforeRef == null || !await File(beforeRef).exists()) {
          conflicts.add(RollbackConflict(
            path: file.relativePath,
            reason: '缺少改动前内容，无法回退',
          ));
          continue;
        }
        final beforeBytes = await File(beforeRef).readAsBytes();
        if (sha256.convert(beforeBytes).toString() != file.beforeHash) {
          conflicts.add(RollbackConflict(
            path: file.relativePath,
            reason: '改动前备份校验失败，无法安全回退',
          ));
          continue;
        }
        if (!dryRun) {
          await target.parent.create(recursive: true);
          await target.writeAsBytes(beforeBytes, flush: true);
        }
        journal.add('restored:${file.relativePath}');
      } catch (error) {
        conflicts.add(RollbackConflict(
          path: file.relativePath,
          reason: '回退中断：$error；已处理 ${journal.join(', ')}',
        ));
        break;
      }
    }
    return conflicts;
  }
}
