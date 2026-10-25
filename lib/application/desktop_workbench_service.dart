import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/command_tool.dart';
import 'providers.dart';

class DesktopSessionSummary {
  const DesktopSessionSummary(
      {required this.id,
      required this.title,
      required this.updatedAt,
      this.status});
  final String id;
  final String title;
  final DateTime updatedAt;
  final String? status;
}

class DesktopWorkbenchService {
  const DesktopWorkbenchService(this.db);
  final AppDatabase db;

  Stream<List<DesktopSessionSummary>> sessions(String? projectId,
      {int limit = 30}) {
    return db
        .customSelect(
          'SELECT c.id, c.title, c.updated_at, '
          '(SELECT t.status FROM tasks t WHERE t.conversation_id = c.id '
          'ORDER BY t.updated_at DESC, t.id DESC LIMIT 1) AS task_status '
          'FROM conversations c WHERE '
          '${projectId == null ? 'c.project_id IS NULL' : 'c.project_id = ?'} '
          'ORDER BY c.is_pinned DESC, c.updated_at DESC, c.id DESC LIMIT ?',
          variables: [
            if (projectId != null) Variable<String>(projectId),
            Variable<int>(limit)
          ],
          readsFrom: {db.conversations, db.tasks},
        )
        .watch()
        .map((rows) => rows
            .map((row) => DesktopSessionSummary(
                  id: row.read<String>('id'),
                  title: row.read<String>('title'),
                  updatedAt: row.read<DateTime>('updated_at'),
                  status: row.readNullable<String>('task_status'),
                ))
            .toList(growable: false));
  }

  Stream<List<Task>> tasks(String conversationId, {int limit = 30}) =>
      (db.select(db.tasks)
            ..where((row) => row.conversationId.equals(conversationId))
            ..orderBy([
              (row) => OrderingTerm.desc(row.updatedAt),
              (row) => OrderingTerm.desc(row.id)
            ])
            ..limit(limit))
          .watch();

  Stream<List<Project>> projects() => (db.select(db.projects)
        ..where((row) => row.archived.equals(false))
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
        ..limit(5))
      .watch();
}

final desktopWorkbenchServiceProvider = FutureProvider<DesktopWorkbenchService>(
    (ref) async =>
        DesktopWorkbenchService(await ref.watch(databaseProvider.future)));

final desktopSessionsProvider = StreamProvider.autoDispose
    .family<List<DesktopSessionSummary>, String?>((ref, projectId) async* {
  yield* (await ref.watch(desktopWorkbenchServiceProvider.future))
      .sessions(projectId, limit: 31);
});
// Read one extra record so the UI offers "more" only when older records exist.
final desktopSessionPageProvider = StreamProvider.autoDispose
    .family<List<DesktopSessionSummary>, (String?, int)>((ref, page) async* {
  yield* (await ref.watch(desktopWorkbenchServiceProvider.future))
      .sessions(page.$1, limit: page.$2 + 1);
});
final desktopTasksProvider = StreamProvider.autoDispose
    .family<List<Task>, String?>((ref, conversationId) async* {
  if (conversationId == null) {
    yield const [];
    return;
  }
  yield* (await ref.watch(desktopWorkbenchServiceProvider.future))
      .tasks(conversationId, limit: 31);
});
final desktopTaskPageProvider = StreamProvider.autoDispose
    .family<List<Task>, (String, int)>((ref, page) async* {
  yield* (await ref.watch(desktopWorkbenchServiceProvider.future))
      .tasks(page.$1, limit: page.$2 + 1);
});
final desktopProjectsProvider =
    StreamProvider.autoDispose<List<Project>>((ref) async* {
  yield* (await ref.watch(desktopWorkbenchServiceProvider.future)).projects();
});

class DesktopLayoutSettings {
  const DesktopLayoutSettings(
      {this.sideWidth = 560,
      this.terminalHeight = 220,
      this.sideOpen = false,
      this.terminalOpen = false,
      this.sideTab = 0});
  final double sideWidth, terminalHeight;
  final bool sideOpen, terminalOpen;
  final int sideTab;

  static double _bounded(
          double? value, double fallback, double min, double max) =>
      value == null || !value.isFinite ? fallback : value.clamp(min, max);

  static Future<DesktopLayoutSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    // The split workspace has different pane proportions and tab ordering.
    // Migrate once; subsequent resizes and visibility changes are preserved.
    if (prefs.getInt('desktop.layout.version') != 2) {
      const settings = DesktopLayoutSettings();
      await settings.save();
      return settings;
    }
    return DesktopLayoutSettings(
        sideWidth:
            _bounded(prefs.getDouble('desktop.side.width'), 560, 340, 780),
        terminalHeight:
            _bounded(prefs.getDouble('desktop.terminal.height'), 220, 160, 480),
        sideOpen: prefs.getBool('desktop.side.open') ?? false,
        terminalOpen: prefs.getBool('desktop.terminal.open') ?? false,
        sideTab: (prefs.getInt('desktop.side.tab') ?? 0).clamp(0, 3));
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('desktop.side.width', sideWidth);
    await prefs.setDouble('desktop.terminal.height', terminalHeight);
    await prefs.setBool('desktop.side.open', sideOpen);
    await prefs.setBool('desktop.terminal.open', terminalOpen);
    await prefs.setInt('desktop.side.tab', sideTab);
    await prefs.setInt('desktop.layout.version', 2);
  }
}

class DesktopFileEntry {
  const DesktopFileEntry({required this.relativePath, required this.directory});
  final String relativePath;
  final bool directory;
  String get name => p.basename(relativePath);
}

/// Bounded, read-only previews and explicit editor launches. No shell commands
/// are assembled from file names. Symlinks must stay inside the real workspace.
class DesktopWorkspaceFiles {
  const DesktopWorkspaceFiles();
  static const previewLimit = 256 * 1024;

  Future<String> resolve(String root, String path) async {
    final workspace = await Directory(root).resolveSymbolicLinks();
    final candidate =
        p.normalize(p.isAbsolute(path) ? path : p.join(workspace, path));
    if (candidate != workspace && !p.isWithin(workspace, candidate)) {
      throw const FileSystemException('文件不在当前项目中');
    }
    final type = await FileSystemEntity.type(candidate);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('文件不存在', path);
    }
    final resolved = type == FileSystemEntityType.directory
        ? await Directory(candidate).resolveSymbolicLinks()
        : await File(candidate).resolveSymbolicLinks();
    if (resolved != workspace && !p.isWithin(workspace, resolved)) {
      throw const FileSystemException('链接指向项目外部');
    }
    return resolved;
  }

  Future<List<DesktopFileEntry>> list(String root, String directory) async {
    final workspace = await Directory(root).resolveSymbolicLinks();
    final resolved = await resolve(root, directory);
    final entries = <DesktopFileEntry>[];
    await for (final entity in Directory(resolved).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (const {'.git', 'node_modules', 'build', '.dart_tool'}
          .contains(name)) {
        continue;
      }
      // Links are deliberately not navigable; resolve() also checks all parents.
      if (entity is! File && entity is! Directory) continue;
      entries.add(DesktopFileEntry(
          relativePath: p.relative(entity.path, from: workspace),
          directory: entity is Directory));
      if (entries.length >= 1000) break;
    }
    entries.sort((a, b) => a.directory == b.directory
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : a.directory
            ? -1
            : 1);
    return entries;
  }

  Future<String> preview(String root, String path) async {
    final file = File(await resolve(root, path));
    if (await file.length() > previewLimit) {
      throw const FileSystemException('文件大于 256 KB，请在外部编辑器打开');
    }
    final bytes = await file
        .openRead(0, previewLimit + 1)
        .fold<List<int>>([], (result, chunk) => result..addAll(chunk));
    if (bytes.length > previewLimit || bytes.contains(0)) {
      throw const FileSystemException('文件过大或为二进制，请在外部编辑器打开');
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FileSystemException('文件不是 UTF-8 文本，请在外部编辑器打开');
    }
  }

  Future<String?> editorPath() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString('desktop.editor.executable');
    if (configured != null && await File(configured).exists()) {
      return configured;
    }
    final roots = [
      Platform.environment['LOCALAPPDATA'],
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)']
    ];
    final candidates = [
      if (roots[0] != null)
        p.join(roots[0]!, 'Programs', 'Microsoft VS Code', 'Code.exe'),
      if (roots[1] != null) p.join(roots[1]!, 'Microsoft VS Code', 'Code.exe'),
      if (roots[2] != null) p.join(roots[2]!, 'Microsoft VS Code', 'Code.exe'),
      if (roots[0] != null)
        p.join(roots[0]!, 'Programs', 'cursor', 'Cursor.exe'),
      if (!Platform.isWindows) '/usr/local/bin/code',
      if (!Platform.isWindows) '/usr/bin/code',
      if (Platform.isMacOS)
        '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<void> configureEditor(String executable) async {
    if (!p.isAbsolute(executable) || !await File(executable).exists()) {
      throw const FileSystemException('请选择存在的编辑器程序');
    }
    await (await SharedPreferences.getInstance())
        .setString('desktop.editor.executable', executable);
  }

  Future<void> openEditor(String root, {String? path}) async {
    final workspace = await resolve(root, '.');
    final file = path == null ? null : await resolve(root, path);
    final executable = await editorPath();
    if (executable == null) throw const FileSystemException('未找到编辑器，请先选择编辑器程序');
    final name = p.basenameWithoutExtension(executable).toLowerCase();
    final vscode = const {'code', 'cursor', 'codium'}.contains(name);
    await Process.start(
        executable,
        [
          if (vscode) '--reuse-window',
          if (vscode || file == null) workspace,
          if (file != null) ...[if (vscode) '--goto', file],
        ],
        workingDirectory: workspace,
        mode: ProcessStartMode.detached);
  }
}

class DesktopTerminalPool {
  final _services = <String, TerminalCommandService>{};
  TerminalCommandService forWorkspace(String root) => _services.putIfAbsent(
      root, () => TerminalCommandService(workspacePath: root));
}

final desktopWorkspaceFilesProvider =
    Provider<DesktopWorkspaceFiles>((ref) => const DesktopWorkspaceFiles());
