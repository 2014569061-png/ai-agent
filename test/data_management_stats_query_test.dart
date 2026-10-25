import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/data_management_stats_query.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

class _SelectAudit extends QueryInterceptor {
  final statements = <String>[];
  final resultShapes = <(int, int)>[];
  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) async {
    final rows = await executor.runSelect(statement, args);
    statements.add(statement);
    resultShapes.add((rows.length, rows.isEmpty ? 0 : rows.first.length));
    return rows;
  }

  void clear() {
    statements.clear();
    resultShapes.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _SelectAudit audit;
  late DataManagementStatsQuery query;
  setUp(() async {
    audit = _SelectAudit();
    db = AppDatabase(NativeDatabase.memory().interceptWith(audit));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    audit.clear();
    query = DataManagementStatsQuery(database: () async => db);
  });

  Future<void> seed({int memories = 1, int docs = 2, int schedules = 3}) async {
    for (final entry in [
      (
        memories,
        'memories',
        'id,content,enabled,created_at,updated_at',
        "'m-'||n,'memory-'||n,n%2,1,1"
      ),
      (
        docs,
        'knowledge_docs',
        'id,name,source_type,chunk_count,created_at,updated_at',
        "'k-'||n,'doc-'||n,'text',10,1,1"
      ),
      (
        schedules,
        'scheduled_tasks',
        'id,name,prompt,cron,enabled,created_at,updated_at',
        "'s-'||n,'schedule-'||n,'prompt','0 9 * * *',n%2,1,1"
      ),
    ]) {
      if (entry.$1 == 0) continue;
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < ${entry.$1})
        INSERT INTO ${entry.$2} (${entry.$3}) SELECT ${entry.$4} FROM seq
      ''');
    }
  }

  test('empty database returns real zeros in one aggregate result row',
      () async {
    final stats = await query.load();
    expect((stats.memoryCount, stats.knowledgeCount, stats.scheduledCount),
        (0, 0, 0));
    expect(audit.statements, hasLength(1));
    expect(
        RegExp(r'COUNT\(\*\)', caseSensitive: false)
            .allMatches(audit.statements.single),
        hasLength(3));
    expect(audit.resultShapes, [(1, 3)]);
  });

  test(
      'counts preserve all-record semantics including disabled memories and schedules',
      () async {
    await seed(memories: 2);
    audit.clear();
    final stats = await query.load();
    expect((stats.memoryCount, stats.knowledgeCount, stats.scheduledCount),
        (2, 2, 3));
    expect(audit.resultShapes, [(1, 3)]);
  });

  test('thousands of records still materialize only three integers', () async {
    await seed(memories: 5000, docs: 1300, schedules: 430);
    audit.clear();
    final stats = await query.load();
    expect((stats.memoryCount, stats.knowledgeCount, stats.scheduledCount),
        (5000, 1300, 430));
    expect(audit.statements, hasLength(1));
    expect(audit.resultShapes, [(1, 3)]);
  });

  test(
      'subsequent loads reflect additions, deletions and cleared data without caching rows',
      () async {
    await seed();
    expect((await query.load()).memoryCount, 1);
    await db.customStatement(
        "INSERT INTO memories(id,content,created_at,updated_at) VALUES('extra','extra',1,1)");
    expect((await query.load()).memoryCount, 2);
    await db.customStatement('DELETE FROM knowledge_docs');
    expect((await query.load()).knowledgeCount, 0);
    await db.clearAllUserData();
    final stats = await query.load();
    expect((stats.memoryCount, stats.knowledgeCount, stats.scheduledCount),
        (0, 0, 0));
  });

  test(
      'query and database opening failures propagate rather than becoming zero counts',
      () async {
    final unavailable = DataManagementStatsQuery(
        database: () async => throw StateError('offline'));
    await expectLater(unavailable.load(), throwsStateError);
    await db.customStatement('DROP TABLE knowledge_docs');
    await expectLater(query.load(), throwsException);
  });
}
