import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/projects/project_change_set_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 15, 12);

  Future<void> insertTask(
    AppDatabase database,
    String id,
    String title,
  ) async {
    await database.into(database.tasks).insert(
          TasksCompanion.insert(
            id: id,
            conversationId: 'conversation-1',
            requestJson: '{"title":"$title"}',
            projectId: const Value('project-1'),
            status: const Value('completed'),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  testWidgets('generic entry asks for a task instead of binding the latest one',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await insertTask(database, 'task-a', '任务 A');
    await insertTask(database, 'task-b', '任务 B');

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => database),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: SizedBox(
          width: 900,
          height: 640,
          child: ProjectChangeSetPage(
            projectId: 'project-1',
            workspacePath: '.',
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('按任务选择要回退的变更集'), findsOneWidget);
    expect(find.text('任务 A'), findsOneWidget);
    expect(find.text('任务 B'), findsOneWidget);
    expect(find.text('回退本任务改动'), findsNothing);
  });

  testWidgets('explicit task id binds that task and omits other tasks',
      (tester) async {
    final root =
        Directory.systemTemp.createTempSync('nexus-change-set-page-test');
    addTearDown(() => root.delete(recursive: true));
    final previousPathProvider = PathProviderPlatform.instance;
    addTearDown(() => PathProviderPlatform.instance = previousPathProvider);
    PathProviderPlatform.instance =
        _TempPathProvider(root.createTempSync('documents').path);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await insertTask(database, 'task-a', '任务 A');
    await insertTask(database, 'task-b', '任务 B');

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => database),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SizedBox(
          width: 900,
          height: 640,
          child: ProjectChangeSetPage(
            projectId: 'project-1',
            workspacePath: root.path,
            taskId: 'task-a',
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('当前任务：任务 A'), findsOneWidget);
    expect(find.text('任务 B'), findsNothing);
    expect(find.text('按任务选择要回退的变更集'), findsNothing);

    final unknownContainer = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => database),
    ]);
    addTearDown(unknownContainer.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: unknownContainer,
      child: const MaterialApp(
        home: SizedBox(
          width: 900,
          height: 640,
          child: ProjectChangeSetPage(
            key: ValueKey<String>('missing-task'),
            projectId: 'project-1',
            workspacePath: '.',
            taskId: 'task-missing',
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('未找到要回退的任务，或任务不属于当前项目'), findsOneWidget);
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
