import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/files/git_index_selection.dart';
import '../infrastructure/tools/workspace_tools.dart';
import 'change_review.dart';

class WorkspaceFileSnapshot {
  const WorkspaceFileSnapshot({
    required this.path,
    required this.hash,
    required this.bytes,
  });

  final String path;
  final String hash;
  final int bytes;

  Map<String, dynamic> toJson() => {
        'path': path,
        'hash': hash,
        'bytes': bytes,
      };

  factory WorkspaceFileSnapshot.fromJson(Map<String, dynamic> json) =>
      WorkspaceFileSnapshot(
        path: json['path']?.toString() ?? '',
        hash: json['hash']?.toString() ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.capturedAt,
    required this.files,
  });

  final DateTime capturedAt;
  final Map<String, WorkspaceFileSnapshot> files;

  Map<String, dynamic> toJson() => {
        'capturedAt': capturedAt.toIso8601String(),
        'files': files.values.map((file) => file.toJson()).toList(),
      };

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List? ?? const [];
    final files = <String, WorkspaceFileSnapshot>{};
    for (final raw in rawFiles.whereType<Map>()) {
      final snapshot =
          WorkspaceFileSnapshot.fromJson(Map<String, dynamic>.from(raw));
      if (snapshot.path.isEmpty) continue;
      files[snapshot.path] = snapshot;
    }
    return WorkspaceSnapshot(
      capturedAt: DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      files: files,
    );
  }
}

/// Captures a lightweight hash index of text files so a later review can
/// isolate this task's edits from older workspace drift.
class WorkspaceSnapshotService {
  const WorkspaceSnapshotService({
    this.maxFiles = 400,
    this.maxFileBytes = 256 * 1024,
  });

  final int maxFiles;
  final int maxFileBytes;

  static const ignoredNames = {
    '.git',
    '.nexus',
    '.dart_tool',
    '.gradle',
    '.pub-cache',
    '.venv',
    'build',
    'node_modules',
    '.idea',
    '.vscode',
    'dist',
    'coverage',
    '__pycache__',
  };

  Future<WorkspaceSnapshot> capture(String workspacePath) async {
    final sandbox = WorkspaceSandbox(workspacePath);
    final root = Directory(workspacePath);
    final files = <String, WorkspaceFileSnapshot>{};
    if (!await root.exists()) {
      return WorkspaceSnapshot(capturedAt: DateTime.now(), files: files);
    }
    await for (final entity in _sourceFiles(root, sandbox)) {
      if (files.length >= maxFiles) break;
      final relative = sandbox.toRelative(entity.path);
      if (_shouldIgnore(relative)) continue;
      try {
        final bytes = await entity.length();
        if (bytes > maxFileBytes) continue;
        final content = await entity.readAsBytes();
        files[relative] = WorkspaceFileSnapshot(
          path: relative,
          hash: sha256.convert(content).toString(),
          bytes: bytes,
        );
      } catch (_) {
        continue;
      }
    }
    return WorkspaceSnapshot(capturedAt: DateTime.now(), files: files);
  }

  /// Git applies nested ignore rules, including negation, without walking SDKs
  /// and dependency caches. Non-Git workspaces prune excluded directories before
  /// descent rather than enumerating their contents and discarding them later.
  Stream<File> _sourceFiles(Directory root, WorkspaceSandbox sandbox) async* {
    // A selected folder may itself live under another repository's ignored
    // local/ directory. Only use Git's index when it belongs to this workspace;
    // otherwise the parent's ignore rule could produce an empty snapshot.
    final hasOwnIndex =
        await FileSystemEntity.type(p.join(root.path, '.git')) !=
            FileSystemEntityType.notFound;
    final selected =
        hasOwnIndex ? await gitIndexSelection(root.absolute.path) : null;
    if (selected != null) {
      for (final path in selected.toList()..sort()) {
        if (_shouldIgnore(path)) continue;
        try {
          final resolved = sandbox.resolvePath(path);
          if (await FileSystemEntity.type(resolved, followLinks: false) ==
              FileSystemEntityType.file) {
            yield File(resolved);
          }
        } on FileSystemException {
          // A concurrent edit may remove a file or its parent.
          continue;
        } on ArgumentError {
          // Git entries are still subject to the workspace path boundary.
          continue;
        }
      }
      return;
    }
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (_shouldIgnore(sandbox.toRelative(entity.path))) continue;
          if (entity is Directory) {
            pending.add(entity);
          } else if (entity is File) {
            yield entity;
          }
        }
      } on FileSystemException {
        // An unreadable directory must not hide files in sibling directories.
        continue;
      }
    }
  }

  Future<String?> currentHash(String workspacePath, String relativePath) async {
    try {
      final file =
          File(WorkspaceSandbox(workspacePath).resolvePath(relativePath));
      if (!await file.exists()) return null;
      final bytes = await file.length();
      if (bytes > maxFileBytes) return 'too-large';
      return sha256.convert(await file.readAsBytes()).toString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> changedSinceSnapshot({
    required String workspacePath,
    required WorkspaceSnapshot snapshot,
    required String relativePath,
  }) async {
    final path = relativePath.replaceAll('\\', '/');
    final before = snapshot.files[path];
    final afterHash = await currentHash(workspacePath, path);
    if (before == null) return afterHash != null;
    if (afterHash == null) return true;
    return before.hash != afterHash;
  }

  Future<ChangeReview> reviewFromAudit({
    required String workspacePath,
    required WorkspaceSnapshot snapshot,
    required Iterable<Map<String, dynamic>> auditMetadata,
    ChangeVerificationMark mark = ChangeVerificationMark.unverified,
  }) async {
    const reviews = ChangeReviewService();
    final raw = reviews.fromMetadata(auditMetadata, mark: mark);
    final files = <FileChangeSummary>[];
    for (final file in raw.files) {
      if (_shouldIgnore(file.path)) continue;
      final changed = await changedSinceSnapshot(
        workspacePath: workspacePath,
        snapshot: snapshot,
        relativePath: file.path,
      );
      if (!changed && file.operation != 'delete') continue;
      files.add(file);
    }
    return ChangeReview(
      files: files,
      mark: mark,
      linesAdded: files.fold(0, (sum, file) => sum + file.linesAdded),
      linesRemoved: files.fold(0, (sum, file) => sum + file.linesRemoved),
    );
  }

  /// Fallback when a run left no file-operation audit (headless resume).
  /// Compares current files against the task-start snapshot.
  Future<ChangeReview> reviewFromSnapshot({
    required String workspacePath,
    required WorkspaceSnapshot snapshot,
    ChangeVerificationMark mark = ChangeVerificationMark.unverified,
  }) async {
    final current = await capture(workspacePath);
    final paths = {...snapshot.files.keys, ...current.files.keys};
    final files = <FileChangeSummary>[];
    for (final path in paths.toList()..sort()) {
      if (_shouldIgnore(path)) continue;
      final before = snapshot.files[path];
      final after = current.files[path];
      if (before != null && after != null && before.hash == after.hash) {
        continue;
      }
      final operation = before == null
          ? 'create'
          : after == null
              ? 'delete'
              : 'edit';
      files.add(FileChangeSummary(
        path: path,
        operation: operation,
        linesAdded: 0,
        linesRemoved: 0,
        diff: '',
        truncated: false,
        mark: mark,
      ));
    }
    return ChangeReview(
      files: files,
      mark: mark,
      linesAdded: files.fold(0, (sum, file) => sum + file.linesAdded),
      linesRemoved: files.fold(0, (sum, file) => sum + file.linesRemoved),
    );
  }

  bool _shouldIgnore(String relative) {
    if (RegExp(r'\.nexus-patch-[a-f0-9]{32}\.(tmp|bak)$').hasMatch(relative)) {
      return true;
    }
    final parts = p.posix.split(relative.replaceAll('\\', '/'));
    return parts.any(ignoredNames.contains);
  }
}
