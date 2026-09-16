import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import 'project_kind.dart';
import 'project_kind_detector.dart';
import 'project_settings.dart';
import 'project_template_service.dart';
import 'providers.dart';
import 'workspace_service.dart';

class ProjectException implements Exception {
  const ProjectException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProjectOpenResult {
  const ProjectOpenResult({
    required this.project,
    required this.accessible,
    this.missingReason,
  });

  final Project project;
  final bool accessible;
  final String? missingReason;
}

class ProjectService {
  ProjectService({
    required this.db,
    WorkspaceService? workspace,
    ProjectTemplateService? templates,
    ProjectKindDetector? detector,
  })  : _workspace = workspace ?? WorkspaceService(),
        _templates = templates ?? const ProjectTemplateService(),
        _detector = detector ?? const ProjectKindDetector();

  static const activeProjectPref = 'settings.project.active_id';
  static const maxArchiveFiles = 2000;
  static const maxArchiveBytes = 80 * 1024 * 1024;

  final AppDatabase db;
  final WorkspaceService _workspace;
  final ProjectTemplateService _templates;
  final ProjectKindDetector _detector;

  Future<List<Project>> list({bool includeArchived = false}) =>
      db.allProjects(includeArchived: includeArchived);

  Future<Project?> find(String id) => db.findProject(id);

  Future<Project?> activeProject() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(activeProjectPref);
    if (id != null && id.isNotEmpty) {
      final project = await db.findProject(id);
      if (project != null && !project.archived) return project;
    }
    final path = await _workspace.getActiveWorkspace();
    if (path == null || path.isEmpty) return null;
    return db.findProjectByCanonicalPath(canonicalizePath(path));
  }

  Future<Project> createFromTemplate(CreateProjectRequest request) async {
    final template = _templates.findById(request.templateId);
    if (template == null) {
      throw const ProjectException('未知项目模板');
    }
    final name = _sanitizeName(request.name);
    final parent = await _resolveParent(request.parentDirectory);
    final target = Directory(p.join(parent, name));
    if (await target.exists()) {
      throw ProjectException('目录已存在：$name');
    }
    await target.create(recursive: true);
    try {
      for (final file in template.files) {
        var contents = file.contents;
        var relativePath = file.relativePath;
        final packageName = request.packageName?.trim();
        if (packageName != null && packageName.isNotEmpty) {
          contents = contents.replaceAll('com.nexus.starter', packageName);
          relativePath = relativePath.replaceAll(
              'com/nexus/starter', packageName.replaceAll('.', '/'));
        }
        if (request.appName != null && request.appName!.trim().isNotEmpty) {
          contents = contents.replaceAll('NexusStarter', request.appName!.trim());
        }
        final dest = File(p.join(target.path, relativePath));
        await dest.parent.create(recursive: true);
        await dest.writeAsString(contents);
      }
      final settings = template.settings.copyWith(
        packageName: request.packageName ?? template.settings.packageName,
        appName: request.appName ?? template.settings.appName,
        providerProfileId: request.providerProfileId,
      );
      return await registerExistingDirectory(
        directoryPath: target.path,
        name: name,
        sourceKind: 'template',
        kind: template.kind,
        settings: settings,
      );
    } catch (error) {
      await _deleteIfEmptyOrCreated(target);
      rethrow;
    }
  }

  Future<Project> importDirectory(ImportDirectoryRequest request) async {
    final directory = Directory(request.directoryPath);
    if (!await directory.exists()) {
      throw const ProjectException('目录不存在');
    }
    try {
      await directory.list().take(1).toList();
    } on FileSystemException {
      throw const ProjectException('目录不可读，请重新授权或选择其他位置');
    }
    final probe = File(p.join(directory.path, '.nexus-write-probe'));
    try {
      await probe.writeAsString('ok');
      await probe.delete();
    } catch (_) {
      throw const ProjectException('目录不可写');
    }
    return registerExistingDirectory(
      directoryPath: directory.path,
      name: request.name,
      sourceKind: 'directory',
    );
  }

  Future<Project> importArchive(ImportArchiveRequest request) async {
    if (request.bytes.length > maxArchiveBytes) {
      throw const ProjectException('压缩包超过 80MB 上限');
    }
    final archive = _decodeZip(Uint8List.fromList(request.bytes));
    final extracted = _extractSafeEntries(archive);
    final name = _sanitizeName(
      request.name ?? p.basenameWithoutExtension(request.archivePath),
    );
    final parent = await _resolveParent(request.parentDirectory);
    final stagingParent =
        Directory(p.join(parent, '.nexus-import-${DateTime.now().microsecondsSinceEpoch}'));
    final staging = Directory(p.join(stagingParent.path, name));
    await staging.create(recursive: true);
    try {
      for (final entry in extracted.entries) {
        final dest = File(p.join(staging.path, entry.key));
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(entry.value, flush: true);
      }
      final target = Directory(p.join(parent, name));
      if (await target.exists()) {
        throw ProjectException('目标目录已存在：$name');
      }
      await staging.rename(target.path);
      await _deleteQuietly(stagingParent);
      return await registerExistingDirectory(
        directoryPath: target.path,
        name: name,
        sourceKind: 'archive',
      );
    } catch (error) {
      await _deleteQuietly(stagingParent);
      rethrow;
    }
  }

  Future<Project> registerExistingDirectory({
    required String directoryPath,
    String? name,
    String sourceKind = 'directory',
    ProjectKind? kind,
    ProjectSettings? settings,
  }) async {
    final canonical = canonicalizePath(directoryPath);
    final existing = await db.findProjectByCanonicalPath(canonical);
    if (existing != null) return existing;
    final detection = await _detector.detect(canonical);
    final now = DateTime.now();
    final project = Project(
      id: UniqueId.generate('project', now: now),
      name: (name ?? p.basename(canonical)).trim().isEmpty
          ? p.basename(canonical)
          : (name ?? p.basename(canonical)).trim(),
      canonicalRootPath: canonical,
      sourceKind: sourceKind,
      projectKind: (kind ?? detection.kind).id,
      runtimePreference: null,
      settingsJson: (settings ?? const ProjectSettings())
          .mergeDetection(detection)
          .encode(),
      settingsVersion: ProjectSettings.version,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveProject(project);
    return project;
  }

  Future<ProjectOpenResult> open(String projectId) async {
    final project = await db.findProject(projectId);
    if (project == null) {
      throw const ProjectException('项目不存在');
    }
    final accessible = kIsWeb
        ? true
        : await Directory(project.canonicalRootPath).exists();
    if (accessible) {
      await _workspace.setActiveWorkspace(project.canonicalRootPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(activeProjectPref, project.id);
      await db.saveProject(project.copyWith(updatedAt: DateTime.now()));
    }
    return ProjectOpenResult(
      project: project,
      accessible: accessible,
      missingReason: accessible ? null : '原目录不可访问，请重新定位项目路径',
    );
  }

  Future<void> updateSettings(String projectId, ProjectSettings settings) async {
    final project = await db.findProject(projectId);
    if (project == null) throw const ProjectException('项目不存在');
    await db.saveProject(project.copyWith(
      settingsJson: settings.encode(),
      settingsVersion: ProjectSettings.version,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> archive(String projectId, {bool deleteFiles = false}) async {
    final project = await db.findProject(projectId);
    if (project == null) return;
    await db.saveProject(project.copyWith(
      archived: true,
      updatedAt: DateTime.now(),
    ));
    if (deleteFiles && !kIsWeb) {
      final directory = Directory(project.canonicalRootPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(activeProjectPref) == projectId) {
      await prefs.remove(activeProjectPref);
    }
  }

  Future<List<Project>> migrateLegacyWorkspaces() async {
    final created = <Project>[];
    final recent = await _workspace.getRecentWorkspaces();
    final active = await _workspace.getActiveWorkspace();
    final paths = <String>[
      if (active != null && active.trim().isNotEmpty) active,
      ...recent,
    ];
    for (final path in paths) {
      if (kIsWeb) continue;
      final directory = Directory(path);
      if (!await directory.exists()) continue;
      final project = await registerExistingDirectory(
        directoryPath: path,
        sourceKind: 'legacy',
      );
      if (created.every((item) => item.id != project.id)) {
        created.add(project);
      }
    }
    if (active != null && active.trim().isNotEmpty) {
      final project =
          await db.findProjectByCanonicalPath(canonicalizePath(active));
      if (project != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(activeProjectPref, project.id);
      }
    }
    return created;
  }

  static String canonicalizePath(String path) {
    final normalized = p.normalize(path.trim());
    if (!p.isAbsolute(normalized)) return normalized.replaceAll('\\', '/');
    return p.normalize(p.absolute(normalized)).replaceAll('\\', '/');
  }

  Future<String> _resolveParent(String? parentDirectory) async {
    if (parentDirectory != null && parentDirectory.trim().isNotEmpty) {
      return canonicalizePath(parentDirectory);
    }
    if (kIsWeb) return '/projects';
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'projects'));
    await root.create(recursive: true);
    return canonicalizePath(root.path);
  }

  String _sanitizeName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (cleaned.isEmpty) throw const ProjectException('项目名称不能为空');
    return cleaned;
  }

  Archive _decodeZip(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ProjectException('仅支持 ZIP 项目压缩包');
    }
  }

  Map<String, Uint8List> _extractSafeEntries(Archive archive) {
    final files = <String, Uint8List>{};
    var total = 0;
    final rootPrefix = _commonRootPrefix(archive);
    for (final file in archive) {
      final rawName = file.name.replaceAll('\\', '/');
      if (rawName.contains('..') ||
          rawName.startsWith('/') ||
          rawName.contains(':')) {
        throw ProjectException('压缩包包含路径逃逸：${file.name}');
      }
      var relative = rawName;
      if (rootPrefix.isNotEmpty && relative.startsWith(rootPrefix)) {
        relative = relative.substring(rootPrefix.length);
      }
      if (relative.startsWith('/')) relative = relative.substring(1);
      if (relative.isEmpty) continue;
      final normalized = p.posix.normalize(relative);
      if (normalized.isEmpty ||
          normalized == '.' ||
          normalized == '..' ||
          normalized.startsWith('../') ||
          p.isAbsolute(normalized)) {
        throw ProjectException('压缩包包含路径逃逸：$relative');
      }
      relative = normalized;
      if (file.isSymbolicLink) {
        throw ProjectException('压缩包不允许外部链接：$relative');
      }
      if (file.isDirectory) continue;
      if (!file.isFile) {
        throw ProjectException('压缩包包含不支持的条目：$relative');
      }
      if (files.length >= maxArchiveFiles) {
        throw const ProjectException('压缩包文件数超过上限');
      }
      final data = file.readBytes() ?? Uint8List(0);
      total += data.length;
      if (total > maxArchiveBytes) {
        throw const ProjectException('解压后体积超过上限');
      }
      files[relative] = data;
    }
    if (files.isEmpty) throw const ProjectException('压缩包是空的');
    return files;
  }

  String _commonRootPrefix(Archive archive) {
    final names = archive
        .where((file) => file.name.isNotEmpty)
        .map((file) => file.name.replaceAll('\\', '/'))
        .toList(growable: false);
    if (names.isEmpty || names.any((name) => !name.contains('/'))) return '';
    final prefix = names.first.split('/').first;
    return names.every((name) => name == prefix || name.startsWith('$prefix/'))
        ? '$prefix/'
        : '';
  }

  Future<void> _deleteIfEmptyOrCreated(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _deleteQuietly(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}

final projectServiceProvider = FutureProvider<ProjectService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ProjectService(
    db: db,
    workspace: ref.read(workspaceServiceProvider),
  );
});
