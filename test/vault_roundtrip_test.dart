import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/files/vault_exporter_io.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/infrastructure/sync/sync_service.dart';

class _FakeStore extends ProviderConfigStore {
  _FakeStore({required this.configs, this.toolKeys = const {}});
  final List<ProviderConfig> configs;
  final Map<String, String> toolKeys;

  @override
  Future<List<ProviderConfig>> loadAll() async => configs;

  @override
  Future<String> readToolKey(String name) async => toolKeys[name] ?? '';
}

class _RecordingStore extends _FakeStore {
  _RecordingStore({required super.configs});
  List<ProviderConfig>? restored;
  String? activeId;
  final Map<String, String> savedKeys = {};

  @override
  Future<void> restoreProfiles(List<ProviderConfig> configs,
      {String? activeId}) async {
    restored = configs;
    this.activeId = activeId;
  }

  @override
  Future<void> saveToolKey(String name, String value) async {
    savedKeys[name] = value;
  }
}

void main() {
  test('vault encryption round-trips with the correct password', () async {
    final service = SyncService();
    final cipher = await service.encryptWithPassword('{"version":2}', 'secret-123');
    expect(await service.decryptWithPassword(cipher, 'secret-123'),
        '{"version":2}');
    // 错误口令必须解密失败（AES-GCM 认证标签校验）。
    expect(
      () => service.decryptWithPassword(cipher, 'wrong-password'),
      throwsA(anything),
    );
  });

  test('buildVaultJson -> restoreVault round-trips data and secrets',
      () async {
    final dbA = AppDatabase(NativeDatabase.memory());
    final dbB = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });
    final now = DateTime.now();
    await dbA.saveConversation(Conversation(
        id: 'c1',
        title: '会话',
        agentId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now));
    await dbA.insertMessage(MessagesCompanion.insert(
        id: 'm1',
        conversationId: 'c1',
        role: 'user',
        content: '内容',
        createdAt: now));
    await dbA.saveAgent(Agent(
        id: 'agent-1',
        name: '代理',
        systemPrompt: '专属系统提示词',
        modelProfileId: 'default',
        enabledToolsJson: '[]',
        temperature: 0.5,
        maxTokens: 1024,
        maxSteps: 4,
        topP: 0.9,
        updatedAt: now));
    await dbA.saveMemory(Memory(
        id: 'mem-1',
        content: '记住这件事',
        category: 'general',
        sourceType: 'manual',
        enabled: true,
        importance: 2,
        createdAt: now,
        updatedAt: now));
    await dbA.insertMcpServer(McpServersCompanion.insert(
      id: 'mcp-1',
      name: '本地MCP',
      kind: 'http',
      url: const Value('http://127.0.0.1:9000'),
      args: const Value('[]'),
      enabled: const Value(true),
    ));

    final sourceStore = _FakeStore(configs: const [
      ProviderConfig(
          id: 'p1',
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          apiKey: 'sk-test'),
    ], toolKeys: {
      'tavily': 'tvly-123',
    });

    final json = await buildVaultJson(dbA, providerStore: sourceStore);
    expect(json['version'], 2);
    final providerSection = json['providerProfiles'] as List;
    expect((providerSection.first as Map)['apiKey'], 'sk-test');
    expect(((json['toolKeys'] as Map))['tavily'], 'tvly-123');

    final restoreStore = _RecordingStore(configs: const []);
    await restoreVault(dbB, json, providerStore: restoreStore);

    expect((await dbB.recentConversations()).single.id, 'c1');
    expect((await dbB.messagesFor('c1')).single.content, '内容');
    expect((await dbB.allAgents()).single.systemPrompt, '专属系统提示词');
    expect((await dbB.allMemories()).single.content, '记住这件事');
    final servers = await dbB.allMcpServers();
    expect(servers, hasLength(1));
    expect(servers.first.name, '本地MCP');
    expect(restoreStore.restored, hasLength(1));
    expect(restoreStore.restored!.single.apiKey, 'sk-test');
    expect(restoreStore.activeId, 'p1');
    expect(restoreStore.savedKeys['tavily'], 'tvly-123');
  });

  test('restoreVault tolerates v1 backups without the secrets section',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await restoreVault(db, {
      'version': 1,
      'conversations': <Map<String, dynamic>>[],
      'messages': <Map<String, dynamic>>[],
    }, providerStore: _RecordingStore(configs: const []));
    expect(await db.allMcpServers(), isEmpty);
  });
}
