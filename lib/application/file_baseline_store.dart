import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../infrastructure/tools/workspace_tools.dart';

/// Canonical form of a workspace-relative path, shared by the baseline store
/// and change sets so both key the same file identically.
String normalizeWorkspacePath(String path) {
  final normalized = p.posix.normalize(path.trim().replaceAll(r'\', '/'));
  return normalized.startsWith('./') ? normalized.substring(2) : normalized;
}

/// What a file looked like before the task first touched it.
class FileBaselineEntry {
  const FileBaselineEntry({
    required this.path,
    required this.existed,
    required this.captured,
    this.hash,
    this.ref,
    this.note,
  });

  final String path;

  /// Whether the file existed before the task's first mutation.
  final bool existed;

  /// Whether the original content is available for restore. `existed=false`
  /// is always captured (restore means delete).
  final bool captured;

  /// sha256 of the original bytes (only when captured and existed).
  final String? hash;

  /// Absolute path of the stored original bytes.
  final String? ref;

  /// Why the content was not captured.
  final String? note;

  Map<String, dynamic> toJson() => {
        'path': path,
        'existed': existed,
        'captured': captured,
        if (hash != null) 'hash': hash,
        if (ref != null) 'ref': ref,
        if (note != null) 'note': note,
      };

  factory FileBaselineEntry.fromJson(Map<String, dynamic> json) =>
      FileBaselineEntry(
        path: json['path']?.toString() ?? '',
        existed: json['existed'] == true,
        captured: json['captured'] == true,
        hash: json['hash']?.toString(),
        ref: json['ref']?.toString(),
        note: json['note']?.toString(),
      );
}

/// Per-task store of original file contents, written right before a tool
/// mutates a file. First write wins: later mutations of the same path within
/// the task never replace the baseline.
///
/// Stored next to the task's change set:
/// `<documents>/changesets/<taskId>/baseline/`.
class FileBaselineStore {
  FileBaselineStore({
    required this.taskId,
    required this.workspacePath,
    this.maxBytes = 8 * 1024 * 1024,
  });

  final String taskId;
  final String workspacePath;

  /// Files larger than this are recorded as not captured.
  final int maxBytes;

  Map<String, FileBaselineEntry>? _entries;
  Future<void> _tail = Future.value();

  static Future<Directory> directoryFor(String taskId) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'changesets', taskId, 'baseline'));
  }

  static Future<File> _manifestFor(String taskId) async =>
      File(p.join((await directoryFor(taskId)).path, 'manifest.json'));

  /// Baseline entries recorded for [taskId], keyed by normalized path.
  static Future<Map<String, FileBaselineEntry>> read(String taskId) async {
    final manifest = await _manifestFor(taskId);
    if (!await manifest.exists()) return {};
    try {
      final raw = jsonDecode(await manifest.readAsString()) as Map;
      final list = raw['entries'] as List? ?? const [];
      return {
        for (final item in list.whereType<Map>())
          for (final entry in [
            FileBaselineEntry.fromJson(Map<String, dynamic>.from(item))
          ])
            entry.path: entry,
      };
    } catch (_) {
      return {};
    }
  }

  /// When the baseline for [taskId] last changed; `null` when none exists.
  static Future<DateTime?> lastModified(String taskId) async {
    final manifest = await _manifestFor(taskId);
    if (!await manifest.exists()) return null;
    return manifest.lastModified();
  }

  /// Records the current state of [paths] unless already recorded.
  /// Calls are serialized so concurrent tool calls cannot race the manifest.
  Future<void> preserve(Iterable<String> paths) {
    final pending = paths.toList(growable: false);
    final run = _tail.then((_) => _preserve(pending));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _preserve(List<String> paths) async {
    final entries = _entries ??= await read(taskId);
    final dir = await directoryFor(taskId);
    final sandbox = WorkspaceSandbox(workspacePath);
    var changed = false;
    for (final raw in paths) {
      final path = normalizeWorkspacePath(raw);
      if (path.isEmpty || path == '.' || entries.containsKey(path)) continue;
      final resolved = sandbox.resolvePath(path);
      final entry = await _snapshot(path, resolved, dir, entries.length);
      entries[path] = entry;
      changed = true;
    }
    if (!changed) return;
    await dir.create(recursive: true);
    final manifest = File(p.join(dir.path, 'manifest.json'));
    final temp = File('${manifest.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'taskId': taskId,
        'entries': [for (final entry in entries.values) entry.toJson()],
      }),
      flush: true,
    );
    await temp.rename(manifest.path);
  }

  Future<FileBaselineEntry> _snapshot(
      String path, String resolved, Directory dir, int index) async {
    switch (await FileSystemEntity.type(resolved)) {
      case FileSystemEntityType.notFound:
        return FileBaselineEntry(path: path, existed: false, captured: true);
      case FileSystemEntityType.directory:
        return FileBaselineEntry(
            path: path, existed: true, captured: false, note: '目录不支持自动回退');
      default:
        final file = File(resolved);
        if (await file.length() > maxBytes) {
          return FileBaselineEntry(
              path: path, existed: true, captured: false, note: '文件过大，未保存原始内容');
        }
        final bytes = await file.readAsBytes();
        await dir.create(recursive: true);
        final ref = p.join(dir.path, '$index.bin');
        await File(ref).writeAsBytes(bytes, flush: true);
        return FileBaselineEntry(
          path: path,
          existed: true,
          captured: true,
          hash: sha256.convert(bytes).toString(),
          ref: ref,
        );
    }
  }
}
