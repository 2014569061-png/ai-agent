import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/knowledge_service.dart';
import 'package:mobile_agent/application/memory_service.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/tools/core_tools.dart';
import 'package:mobile_agent/domain/tool_result.dart';
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

    final block =
        await knowledgeService.buildInjectionBlock(db, '什么是 Flutter Widget');
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

  test('memory_get exposes revision and pagination cursor', () async {
    for (var i = 0; i < 3; i++) {
      await db.saveMemory(Memory(
        id: 'page-$i',
        content: '分页记忆 $i',
        category: 'general',
        sourceConversationId: null,
        sourceType: 'manual',
        enabled: true,
        importance: 1,
        createdAt: DateTime.now().add(Duration(seconds: i)),
        updatedAt: DateTime.now().add(Duration(seconds: i)),
      ));
    }
    final service = MemoryService();
    final tool = MemoryGetTool(
      onGet: (query, offset, limit) async {
        final matched =
            await service.search(db, query, offset: offset, limit: limit + 1);
        final hasMore = matched.length > limit;
        final items = hasMore ? matched.take(limit).toList() : matched;
        return ToolResult.success(data: {
          'revision': await service.currentRevision(db),
          'items': items.map((item) => {'id': item.id}).toList(),
          'hasMore': hasMore,
          'nextOffset': hasMore ? offset + items.length : null,
        });
      },
    );
    final result = await tool.execute({'query': '分页', 'limit': 2});
    expect(result.ok, isTrue);
    expect(result.code, ToolCodes.ok);
    expect(result.data?['items'], hasLength(2));
    expect(result.data?['hasMore'], isTrue);
    expect(result.data?['nextOffset'], 2);
    expect((result.data?['revision'] as String), hasLength(64));
  });

  test('memory revision conflict reports the latest revision', () async {
    final service = MemoryService();
    final revision = await service.currentRevision(db);
    await service.add(database: db, content: '先写入一条');
    expect(
      () => service.add(
          database: db, content: '过期写入', expectedRevision: revision),
      throwsA(isA<MemoryConflictException>()),
    );
  });

  test('memory_write supports append and line replacement under revision lock',
      () async {
    final service = MemoryService();
    final created = await service.write(
      database: db,
      id: null,
      content: '第一行\n第二行',
    );
    final revision = await service.currentRevision(db);
    final appended = await service.write(
      database: db,
      id: created.id,
      content: '第三行',
      mode: 'append',
      expectedRevision: revision,
    );
    expect(appended.content, '第一行\n第二行\n第三行');

    final nextRevision = await service.currentRevision(db);
    final replaced = await service.write(
      database: db,
      id: created.id,
      content: '替换行',
      mode: 'line_replace',
      startLine: 2,
      endLine: 3,
      expectedRevision: nextRevision,
    );
    expect(replaced.content, '第一行\n替换行');
  });

  test('persisted checkpoints redact sensitive tool arguments and results', () {
    final context = [
      ChatMessage(
        role: MessageRole.assistant,
        parts: const [],
        toolCalls: [
          ToolCall(
            id: 'clip-1',
            // terminal 是真实存在的、参数与结果都需要持久化脱敏的工具；
            // 旧的 clipboard_read 是已删除的死条目，不能再用作夹具。
            name: 'terminal',
            arguments: {'text': '验证码-SECRET'},
          ),
        ],
      ),
      ChatMessage(
        role: MessageRole.tool,
        toolCallId: 'clip-1',
        parts: [MessagePart.text('{"text":"验证码-SECRET"}')],
      ),
    ];

    final encoded = encodeChatContextForPersistence(context).toString();
    expect(encoded, isNot(contains('验证码-SECRET')));
    expect(encoded, contains('redacted'));
    expect(encoded, contains('敏感工具结果已脱敏'));
  });
}
