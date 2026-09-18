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
}
