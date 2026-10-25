import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_search_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;
  late DesktopSearchService search;
  final now = DateTime(2026, 10, 6);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    search = DesktopSearchService(db);
  });
  tearDown(() => db.close());

  Future<void> conversation(String id, String title, {DateTime? at}) =>
      db.into(db.conversations).insert(
            ConversationsCompanion.insert(
                id: id,
                title: Value(title),
                createdAt: now,
                updatedAt: at ?? now),
          );

  test('search merges real conversations, projects and tasks', () async {
    await conversation('c', '修复 Nexus 搜索');
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: 'p',
          name: 'Nexus 桌面',
          canonicalRootPath: 'D:/nexus',
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 't',
          conversationId: 'c',
          requestJson: jsonEncode({'title': 'Nexus 数据库检查', 'prompt': '查一下搜索'}),
          createdAt: now,
          updatedAt: now,
        ));
    final results = await search.search(' nExUs ');
    expect(
        results.map((r) => r.kind).toSet(), {DesktopSearchKind.conversation, DesktopSearchKind.project, DesktopSearchKind.task});
    expect(results.singleWhere((r) => r.kind == DesktopSearchKind.task).title,
        'Nexus 数据库检查');
    expect(results.map((r) => r.id).toSet(), {'c', 'p', 't'});
    expect((await search.search('数据库')).single.id, 't');
  });

  test('search treats SQL wildcard characters literally and excludes archives',
      () async {
    await conversation('literal', r"100%_\'完成");
    await conversation('other', '普通会话');
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: 'archived',
          name: '100%_旧项目',
          canonicalRootPath: 'D:/archived',
          archived: const Value(true),
          createdAt: now,
          updatedAt: now,
        ));
    expect((await search.search('%_')).map((r) => r.id), ['literal']);
    expect(await search.search("' OR 1=1 --"), isEmpty);
    expect(await search.search('  '), isEmpty);
  });

  test('search finds older matches beyond the recent records window', () async {
    await conversation('old', '需要找到的老会话',
        at: now.subtract(const Duration(days: 100)));
    for (var i = 0; i < 110; i++) {
      await conversation('recent-$i', '普通会话 $i');
    }
    expect((await search.search('老会话')).single.id, 'old');
  });
}
