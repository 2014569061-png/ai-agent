import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('agent and model profile queries honor an explicit limit', () async {
    final now = DateTime(2026, 9, 17);
    for (var index = 0; index < 5; index++) {
      await db.insertAgent(AgentsCompanion.insert(
        id: 'agent-$index',
        name: 'Agent $index',
        modelProfileId: 'default',
        systemPrompt: const Value(''),
        enabledToolsJson: const Value('[]'),
        updatedAt: now,
      ));
      await db.saveModelProfile(ModelProfile(
        id: 'profile-$index',
        name: 'Profile $index',
        baseUrl: 'https://example.com',
        modelName: 'model-$index',
        apiKeyRef: 'key-$index',
        updatedAt: now,
      ));
    }

    expect(await db.allAgents(limit: 2), hasLength(2));
    expect(await db.allModelProfiles(limit: 3), hasLength(3));
  });

  test('history search applies filters and pages literal title matches',
      () async {
    final now = DateTime(2026, 9, 23);
    for (final row in [
      ('match', 'Release 100%_safe', true, false),
      ('wildcard', 'Release 100XXsafe', true, false),
      ('not-favorite', 'Release 100%_safe', false, false),
    ]) {
      await db.saveConversation(Conversation(
        id: row.$1,
        title: row.$2,
        agentId: null,
        mode: 'chat',
        isPinned: row.$4,
        isFavorite: row.$3,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));
    }

    final firstPage = await db.searchConversations(
      query: '100%_',
      filter: 'favorite',
      limit: 1,
    );
    final secondPage = await db.searchConversations(
      query: '100%_',
      filter: 'favorite',
      limit: 1,
      offset: 1,
    );

    expect(firstPage.map((item) => item.id), ['match']);
    expect(secondPage, isEmpty);
  });
}
