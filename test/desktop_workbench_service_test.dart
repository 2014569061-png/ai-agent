import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_workbench_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;
  late DesktopWorkbenchService service;
  final now = DateTime(2026, 10, 14);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = DesktopWorkbenchService(db);
  });
  tearDown(() => db.close());

  Future<void> session(String id, int age,
          {String? project = 'p', bool pinned = false}) =>
      db.into(db.conversations).insert(ConversationsCompanion.insert(
            id: id,
            title: Value(id),
            projectId: Value(project),
            isPinned: Value(pinned),
            createdAt: now,
            updatedAt: now.subtract(Duration(minutes: age)),
          ));

  test(
      'expanding the session window includes older project records in stable order',
      () async {
    for (var i = 0; i < 65; i++) {
      await session('c$i', i);
    }
    await session('other-project', 0, project: 'other');
    await session('pinned-old', 100, pinned: true);
    final initial = await service.sessions('p', limit: 31).first;
    final expanded = await service.sessions('p', limit: 61).first;
    expect(initial, hasLength(31));
    expect(initial.first.id, 'pinned-old');
    expect(expanded.take(31).map((s) => s.id), initial.map((s) => s.id));
    expect(expanded.map((s) => s.id), contains('c59'));
    expect(expanded.map((s) => s.id), isNot(contains('other-project')));
    expect(await service.sessions('p', limit: 91).first, hasLength(66));
  });
  test('unassigned sessions remain separate from project sessions', () async {
    await session('assigned', 0);
    await session('unassigned', 1, project: null);
    expect((await service.sessions(null).first).single.id, 'unassigned');
  });
  test('older tasks are reachable without mixing conversations', () async {
    for (var i = 0; i < 35; i++) {
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'task${i.toString().padLeft(2, '0')}',
            conversationId: 'c',
            requestJson: '{}',
            createdAt: now,
            updatedAt: now,
          ));
    }
    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 'other',
        conversationId: 'other',
        requestJson: '{}',
        createdAt: now,
        updatedAt: now));
    final initial = await service.tasks('c', limit: 31).first;
    final expanded = await service.tasks('c', limit: 61).first;
    expect(initial, hasLength(31));
    expect(expanded, hasLength(35));
    expect(expanded.take(31).map((t) => t.id), initial.map((t) => t.id));
    expect(expanded.last.id, 'task00');
  });
}
