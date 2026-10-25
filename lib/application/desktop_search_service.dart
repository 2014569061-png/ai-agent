import 'package:drift/drift.dart';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';
import 'providers.dart';
import 'task_service.dart';
import 'chat_controller.dart';

enum DesktopSearchKind { conversation, project, task, file }

class DesktopSearchResult {
  const DesktopSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
  });

  final DesktopSearchKind kind;
  final String id;
  final String title;
  final String subtitle;
  final DateTime updatedAt;
}

class DesktopSearchService {
  const DesktopSearchService(this.db);
  final AppDatabase db;

  /// Search each table before applying its limit, including older records.
  /// instr treats %, _, quotes and backslashes as literal user input.
  Future<List<DesktopSearchResult>> search(String query) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const [];
    final rows = await db.customSelect(
      'SELECT id, title, updated_at, \'conversation\' AS kind FROM '
      '(SELECT id, title, updated_at FROM conversations '
      'WHERE instr(lower(title), ?) > 0 ORDER BY updated_at DESC LIMIT 30) '
      'UNION ALL SELECT id, name AS title, updated_at, \'project\' AS kind FROM '
      '(SELECT id, name, updated_at FROM projects WHERE archived = 0 AND '
      '(instr(lower(name), ?) > 0 OR instr(lower(canonical_root_path), ?) > 0) '
      'ORDER BY updated_at DESC LIMIT 30) '
      'UNION ALL SELECT id, type AS title, updated_at, \'task\' AS kind FROM '
      '(SELECT id, type, updated_at FROM tasks WHERE '
      'instr(lower(request_json), ?) > 0 OR instr(lower(type), ?) > 0 '
      'ORDER BY updated_at DESC LIMIT 30) ORDER BY updated_at DESC',
      variables: [for (var i = 0; i < 5; i++) Variable<String>(term)],
      readsFrom: {db.conversations, db.projects, db.tasks},
    ).get();
    final results = <DesktopSearchResult>[];
    for (final row in rows) {
      final kind = DesktopSearchKind.values.byName(row.read<String>('kind'));
      final id = row.read<String>('id');
      var title = row.read<String>('title');
      var subtitle = switch (kind) {
        DesktopSearchKind.conversation => '会话',
        DesktopSearchKind.project => '项目',
        DesktopSearchKind.task => '任务',
        DesktopSearchKind.file => '文件',
      };
      if (kind == DesktopSearchKind.task) {
        final task = await db.findTask(id);
        if (task == null) continue;
        final info = DevelopmentTaskInfo.fromTask(task);
        title = info.title;
        subtitle = '${TaskService.taskTypeLabel(task.type)} · ${task.status}';
      }
      results.add(DesktopSearchResult(
        kind: kind,
        id: id,
        title: title,
        subtitle: subtitle,
        updatedAt: row.read<DateTime>('updated_at'),
      ));
    }
    return results;
  }
}

final desktopSearchServiceProvider = FutureProvider<DesktopSearchService>(
  (ref) async => DesktopSearchService(await ref.watch(databaseProvider.future)),
);

final desktopSearchProvider = FutureProvider.autoDispose
    .family<List<DesktopSearchResult>, String>((ref, query) async {
  // Debounce database reads; a disposed provider never submits a stale query.
  var active = true;
  ref.onDispose(() => active = false);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (!active || query.trim().isEmpty) return const [];
  return (await ref.watch(desktopSearchServiceProvider.future)).search(query);
});

final desktopFileSearchProvider = FutureProvider.autoDispose
    .family<List<DesktopSearchResult>, String>((ref, query) async {
  final root =
      ref.watch(chatControllerProvider.select((s) => s.currentWorkspacePath));
  if (root == null || query.trim().isEmpty) return [];
  var active = true;
  ref.onDispose(() => active = false);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (!active) return [];
  final paths = await Isolate.run(() => searchDesktopFilePaths(root, query));
  return [
    for (final path in paths)
      DesktopSearchResult(
          kind: DesktopSearchKind.file,
          id: path,
          title: p.basename(path),
          subtitle: p.relative(path, from: root),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0))
  ];
});

List<String> searchDesktopFilePaths(String root, String query) {
  const excluded = {
    '.git',
    '.nexus',
    '.dart_tool',
    'node_modules',
    '.venv',
    'build',
    'artifacts',
    'local',
    'dist'
  };
  final queue = <Directory>[Directory(root)], matches = <String>[];
  final term = query.toLowerCase().replaceAll('\\', '/');
  var visited = 0;
  while (queue.isNotEmpty && visited < 50000 && matches.length < 30) {
    final directory = queue.removeLast();
    try {
      for (final entry in directory.listSync(followLinks: false)) {
        if (++visited > 50000) break;
        if (entry is Directory && !excluded.contains(p.basename(entry.path))) {
          queue.add(entry);
        }
        if (entry is File &&
            p
                .relative(entry.path, from: root)
                .replaceAll('\\', '/')
                .toLowerCase()
                .contains(term)) {
          matches.add(entry.path);
        }
        if (matches.length >= 30) break;
      }
    } on FileSystemException {
      /* Inaccessible directories are omitted from path search. */
    }
  }
  return matches;
}
