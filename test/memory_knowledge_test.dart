import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/knowledge_service.dart';
import 'package:mobile_agent/application/memory_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  final memoryService = MemoryService();
  final knowledgeService = KnowledgeService();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('memory injection block contains enabled memories in importance order',
      () async {
    await db.saveMemory(Memory(
      id: 'm-low',
      content: '用户偏好浅色模式。',
      category: 'general',
      sourceConversationId: null,
      sourceType: 'manual',
      enabled: true,
      importance: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await db.saveMemory(Memory(
      id: 'm-high',
      content: '用户是 Flutter 开发者。',
      category: 'general',
      sourceConversationId: null,
      sourceType: 'auto',
      enabled: true,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    final block = await memoryService.buildInjectionBlock(db);
    expect(block, contains('用户是 Flutter 开发者'));
    expect(block, contains('用户偏好浅色模式'));
    expect(block.startsWith('## 长期记忆'), isTrue);
  });

  test('memory injection returns empty when disabled', () async {
    await db.saveMemory(Memory(
      id: 'm1',
      content: '测试记忆',
      category: 'general',
      sourceConversationId: null,
      sourceType: 'manual',
      enabled: true,
      importance: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await memoryService.setEnabled(false);
    addTearDown(() => memoryService.setEnabled(true));
    expect(await memoryService.buildInjectionBlock(db), isEmpty);
  });

  test('knowledge injection returns relevant chunks via BM25', () async {
    await knowledgeService.ingest(
      db: db,
      name: 'flutter 笔记',
      sourceType: 'text',
      content: 'Flutter 使用 Dart 语言开发跨平台应用，组件叫 Widget。',
    );
    await knowledgeService.ingest(
      db: db,
      name: '无关笔记',
      sourceType: 'text',
      content: '今天天气很好，适合出去散步。',
    );

    final block = await knowledgeService.buildInjectionBlock(db, '什么是 Flutter Widget');
    expect(block, isNotEmpty);
    expect(block, contains('Flutter 使用 Dart 语言'));
    expect(block.startsWith('## 知识库相关片段'), isTrue);
  });

  test('knowledge injection is empty for irrelevant query', () async {
    await knowledgeService.ingest(
      db: db,
      name: '笔记',
      sourceType: 'text',
      content: 'Flutter 使用 Dart 语言开发跨平台应用。',
    );
    final block = await knowledgeService.buildInjectionBlock(db, 'zzzzzzzz');
    expect(block, isEmpty);
  });
}
