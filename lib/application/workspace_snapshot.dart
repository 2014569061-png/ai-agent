import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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
    '.dart_tool',
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
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (files.length >= maxFiles) break;
      if (entity is! File) continue;
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

  Future<String?> currentHash(String workspacePath, String relativePath) async {
    try {
      final file = File(WorkspaceSandbox(workspacePath).resolvePath(relativePath));
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
    final parts = p.posix.split(relative.replaceAll('\\', '/'));
    return parts.any(ignoredNames.contains);
  }
}
