import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/draft_service.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/project_service.dart';
import 'package:mobile_agent/application/project_settings.dart';
import 'package:mobile_agent/application/project_template_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppDatabase db;
  late ProjectService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('nexus-project-');
    db = AppDatabase(NativeDatabase.memory());
    service = ProjectService(db: db);
  });

  tearDown(() async {
    await db.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('schemaVersion is 24', () {
    expect(db.schemaVersion, 24);
  });

  test('creates a static web project from template', () async {
    final project = await service.createFromTemplate(CreateProjectRequest(
      name: 'todo-web',
      templateId: 'static-web',
      parentDirectory: temp.path,
    ));
    expect(project.projectKind, ProjectKind.staticWeb.id);
    expect(File(p.join(project.canonicalRootPath, 'index.html')).existsSync(),
        isTrue);
    expect(
        File(p.join(project.canonicalRootPath, 'app.js')).existsSync(), isTrue);
    final listed = await service.list();
    expect(listed.map((item) => item.id), contains(project.id));
  });

  test('java apk template remaps package path and keeps sh build.sh', () async {
    final project = await service.createFromTemplate(CreateProjectRequest(
      name: 'mini-apk',
      templateId: 'java-apk',
      parentDirectory: temp.path,
      packageName: 'com.demo.tool',
      appName: 'DemoTool',
    ));
    expect(project.projectKind, ProjectKind.javaApk.id);
    expect(
      File(p.join(
              project.canonicalRootPath, 'src/com/demo/tool/MainActivity.java'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(p.join(project.canonicalRootPath,
              'src/com/nexus/starter/MainActivity.java'))
          .existsSync(),
      isFalse,
    );
    final manifest =
        File(p.join(project.canonicalRootPath, 'AndroidManifest.xml'))
            .readAsStringSync();
    expect(manifest, contains('package="com.demo.tool"'));
    expect(manifest, contains('android:label="DemoTool"'));
    final settings = ProjectSettings.decode(project.settingsJson);
    expect(settings.buildCommand, 'sh build.sh');
    expect(settings.packageName, 'com.demo.tool');
  });

  test('same directory is registered only once', () async {
    final directory = Directory(p.join(temp.path, 'shared'));
    await directory.create();
    await File(p.join(directory.path, 'index.html'))
        .writeAsString('<html></html>');
    final first = await service.importDirectory(
      ImportDirectoryRequest(directoryPath: directory.path),
    );
    final second = await service.importDirectory(
      ImportDirectoryRequest(directoryPath: directory.path),
    );
    expect(first.id, second.id);
    expect(await service.list(), hasLength(1));
  });

  test('rejects zip path traversal', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('../evil.txt', 'nope'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(
      () => service.importArchive(ImportArchiveRequest(
        archivePath: 'evil.zip',
        bytes: bytes,
        parentDirectory: temp.path,
      )),
      throwsA(isA<ProjectException>()),
    );
  });

  test('imports a zip into a new project directory', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('demo/index.html', '<h1>ok</h1>'))
      ..addFile(ArchiveFile.string('demo/README.md', 'hello'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final project = await service.importArchive(ImportArchiveRequest(
      archivePath: 'demo.zip',
      bytes: bytes,
      parentDirectory: temp.path,
    ));
    expect(File(p.join(project.canonicalRootPath, 'index.html')).existsSync(),
        isTrue);
    expect(project.sourceKind, 'archive');
  });

  test('opening a missing directory reports inaccessible', () async {
    final directory = Directory(p.join(temp.path, 'gone'));
    await directory.create();
    final project = await service.importDirectory(
      ImportDirectoryRequest(directoryPath: directory.path, name: 'gone'),
    );
    await directory.delete(recursive: true);
    final opened = await service.open(project.id);
    expect(opened.accessible, isFalse);
    expect(opened.missingReason, contains('重新定位'));
  });

  test('drafts persist independently of in-memory chat state', () async {
    const drafts = DraftService();
    await drafts.save(
      db,
      draftKey: DraftService.keyFor(conversationId: 'c1'),
      conversationId: 'c1',
      text: '未发送的待办需求',
    );
    final loaded =
        await drafts.load(db, DraftService.keyFor(conversationId: 'c1'));
    expect(loaded?.text, '未发送的待办需求');
  });

  test('archived project can reuse the same path', () async {
    final directory = Directory(p.join(temp.path, 'reuse'));
    await directory.create();
    final first = await service.importDirectory(
      ImportDirectoryRequest(directoryPath: directory.path, name: 'reuse'),
    );
    await service.archive(first.id);
    final second = await service.importDirectory(
      ImportDirectoryRequest(directoryPath: directory.path, name: 'reuse-2'),
    );
    expect(second.id, isNot(first.id));
    expect(await service.list(), hasLength(1));
  });

  test('fresh databases create the unique active path index', () async {
    final indexes = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_projects_active_path'")
        .get();
    expect(indexes, isNotEmpty);
  });

  test('v19 to v20 migration is idempotent', () async {
    final m = db.createMigrator();
    await db.migration.onUpgrade(m, 19, 20);
    final tables = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('projects','drafts')")
        .get();
    expect(tables.map((row) => row.data['name']),
        containsAll(['projects', 'drafts']));
    final columns =
        await db.customSelect('PRAGMA table_info(conversations)').get();
    expect(columns.map((row) => row.data['name']), contains('project_id'));
  });
}
