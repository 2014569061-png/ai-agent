import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/conversation_fork_service.dart';
import 'package:mobile_agent/domain/message_display_metadata.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

ChatMessage _reply() => ChatMessage(
      id: 'reply',
      role: MessageRole.assistant,
      parts: [const MessagePart.text('preserved body')],
      modelName: 'test-model',
      elapsed: const Duration(microseconds: 19300123),
      ttft: const Duration(milliseconds: 220),
      reasoningDuration: const Duration(milliseconds: 110),
      usage: const Usage(
        promptTokens: 150,
        completionTokens: 30,
        cachedTokens: 90,
        cacheWriteTokens: 10,
        reasoningTokens: 12,
        usageReported: true,
        cacheStatsReported: true,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('display metadata preserves all measured fields without changing text',
      () {
    final source = _reply();
    final bare = ChatMessage(
      id: 'persisted-id',
      role: source.role,
      parts: source.parts,
      reasoning: 'preserved reasoning',
    );
    final restored = MessageDisplayMetadata.restore(
        bare, MessageDisplayMetadata.encode(source));
    expect(restored.id, bare.id);
    expect(restored.text, source.text);
    expect(restored.reasoning, bare.reasoning);
    expect(restored.modelName, source.modelName);
    expect(restored.elapsed, source.elapsed);
    expect(restored.ttft, source.ttft);
    expect(restored.reasoningDuration, source.reasoningDuration);
    expect(restored.usage?.promptTokens, 150);
    expect(restored.usage?.completionTokens, 30);
    expect(restored.usage?.cachedTokens, 90);
    expect(restored.usage?.cacheWriteTokens, 10);
    expect(restored.usage?.reasoningTokens, 12);
    expect(restored.usage?.usageReported, isTrue);
    expect(restored.usage?.cacheStatsReported, isTrue);
  });

  test('legacy, invalid and future metadata leave the body readable', () {
    final message = ChatMessage(
        role: MessageRole.assistant, parts: [const MessagePart.text('legacy')]);
    for (final encoded in <String?>[
      null,
      '',
      '{invalid',
      '[]',
      'null',
      '{"version":2,"modelName":"unsupported"}',
      'x' * 16385,
    ]) {
      expect(MessageDisplayMetadata.restore(message, encoded), same(message));
    }
    expect(MessageDisplayMetadata.encode(message), isNull);
  });

  test('invalid field types and negative or huge durations are ignored', () {
    final message = ChatMessage(
        role: MessageRole.assistant, parts: [const MessagePart.text('body')]);
    final restored = MessageDisplayMetadata.restore(
        message,
        jsonEncode({
          'version': 1,
          'modelName': <String>[],
          'elapsedUs': -1,
          'ttftUs': 31536000000001,
          'reasoningUs': '123',
          'usage': {'promptTokens': -2, 'completionTokens': '3'},
        }));
    expect(restored.text, 'body');
    expect(restored.modelName, isNull);
    expect(restored.elapsed, isNull);
    expect(restored.ttft, isNull);
    expect(restored.reasoningDuration, isNull);
    expect(restored.usage?.totalTokens, 0);
    expect(restored.usage?.usageReported, isFalse);
  });

  test('v24 to v25 preserves existing rows and adds nullable metadata',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 9, 22);
    await db.insertMessage(MessagesCompanion.insert(
      id: 'legacy-message',
      conversationId: 'legacy-conversation',
      role: 'assistant',
      content: 'old body',
      createdAt: now,
    ));
    await db.customStatement(
        'ALTER TABLE messages DROP COLUMN display_metadata_json');
    await db.migration.onUpgrade(db.createMigrator(), 24, 25);
    // Re-entry is safe for a partially applied legacy migration.
    await db.migration.onUpgrade(db.createMigrator(), 24, 25);
    final rows = await db.messagesFor('legacy-conversation');
    expect(rows, hasLength(1));
    expect(rows.single.content, 'old body');
    expect(rows.single.createdAt, now);
    expect(rows.single.displayMetadataJson, isNull);
    final oldBackupRow = rows.single.toJson()..remove('displayMetadataJson');
    expect(Message.fromJson(oldBackupRow).content, 'old body');
    expect(Message.fromJson(oldBackupRow).displayMetadataJson, isNull);
  });

  test('fork copies display metadata and leaves source unchanged', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 9, 22);
    final encoded = MessageDisplayMetadata.encode(_reply());
    await db.saveConversation(Conversation(
      id: 'source',
      title: 'source title',
      agentId: null,
      projectId: null,
      mode: 'chat',
      providerProfileId: null,
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'reply',
      conversationId: 'source',
      role: 'assistant',
      content: 'preserved body',
      displayMetadataJson: Value(encoded),
      createdAt: now,
    ));
    final fork = await const ConversationForkService().fork(
      db: db,
      sourceConversationId: 'source',
      forkMessageId: 'reply',
    );
    final copied = (await db.messagesFor(fork.id)).single;
    final original = (await db.messagesFor('source')).single;
    expect(copied.displayMetadataJson, encoded);
    expect(original.displayMetadataJson, encoded);
    expect(original.id, 'reply');
    expect(copied.id, isNot(original.id));
    final roundTrip = Message.fromJson(copied.toJson());
    expect(roundTrip.displayMetadataJson, encoded);
    expect(roundTrip.content, original.content);
  });
}
