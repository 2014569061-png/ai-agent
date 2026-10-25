import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/knowledge_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scoped search must never load the entire multi-project corpus first.
class _ScopedDatabase extends AppDatabase {
  _ScopedDatabase() : super(NativeDatabase.memory());

  @override
  Future<List<KnowledgeChunk>> allKnowledgeChunks() =>
      throw StateError('Unscoped chunk load');
  @override
  Future<List<KnowledgeDoc>> allKnowledgeDocs() =>
      throw StateError('Unscoped document load');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ScopedDatabase db;
  final service = KnowledgeService();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = _ScopedDatabase();
  });
  tearDown(() => db.close());

  Future<KnowledgeDoc> ingest(String name, {String? project}) async {
    final doc = await service.ingest(
      db: db,
      name: name,
      sourceType: 'text',
      content: 'needle $name',
    );
    if (project != null) await db.bindKnowledgeDocument(doc.id, project);
    return doc;
  }

  test('SQL corpus includes global and selected project without other projects',
      () async {
    final global = await ingest('global');
    final first = await ingest('project-one', project: 'one');
    await ingest('project-two', project: 'two');
    final corpus = await db.knowledgeCorpusForSearch('one');
    expect(corpus.documents.map((d) => d.id),
        unorderedEquals([global.id, first.id]));
    expect(corpus.chunks.map((c) => c.docId),
        unorderedEquals([global.id, first.id]));
    expect(corpus.scopes, {first.id: 'one'});
    final block =
        await service.buildInjectionBlock(db, 'needle', projectId: 'one');
    expect(block, contains('project-one'));
    expect(block, contains('global'));
    expect(block, isNot(contains('project-two')));
  });

  test(
      'global search cannot recall project-only knowledge and refreshes scope changes',
      () async {
    final private = await ingest('private', project: 'one');
    expect(await service.buildInjectionBlock(db, 'needle'), isEmpty);
    await db.bindKnowledgeDocument(private.id, null);
    expect(
        await service.buildInjectionBlock(db, 'needle'), contains('private'));
    await db.bindKnowledgeDocument(private.id, 'two');
    expect(await service.buildInjectionBlock(db, 'needle'), isEmpty);
  });
}
