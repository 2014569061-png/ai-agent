// 会话日志附件改为 blobRef：大附件按哈希单独存储，日志只保留引用。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/session_log/chat_message_codec.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/application/session_log/session_recorder.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

final _bigImage = 'data:image/png;base64,${'A' * 4000}';

ChatMessage _withImage(String text, {String? image}) => ChatMessage(
      role: MessageRole.user,
      parts: [
        MessagePart.text(text),
        MessagePart.image(image ?? _bigImage, mimeType: 'image/png'),
      ],
    );

Future<void> _record(SessionEventStore store, String conversation,
    List<ChatMessage> messages) async {
  final recorder = SessionRecorder(
      store: store, conversationId: conversation, runId: 'r-$conversation',
      model: 'm')
    ..start()
    ..onRequest(1, UnifiedRequest(model: 'm', messages: messages));
  await recorder.flush();
}

void main() {
  group('codec', () {
    test('large attachments become blob refs, small ones stay inline', () {
      final message = ChatMessage(role: MessageRole.user, parts: [
        const MessagePart.text('看图'),
        MessagePart.image(_bigImage, mimeType: 'image/png'),
        const MessagePart.file('/tmp/a.txt', mimeType: 'text/plain'),
      ]);
      final encoded = ChatMessageCodec.encodeForLog(message);
      final parts = encoded.payload['parts'] as List;

      expect(parts[0], {'type': 'text', 'value': '看图'});
      expect((parts[1] as Map).containsKey('value'), isFalse);
      expect(parts[1]['size'], _bigImage.length);
      expect(parts[2]['value'], '/tmp/a.txt');
      expect(encoded.blobs.values.single.data, _bigImage);
      expect(ChatMessageCodec.blobRefs(encoded.payload),
          [encoded.blobs.keys.single]);

      final decoded =
          ChatMessageCodec.decode(encoded.payload, blobs: {
        for (final e in encoded.blobs.entries) e.key: e.value.data,
      });
      expect(ChatMessageCodec.canonicalJson(decoded),
          ChatMessageCodec.canonicalJson(message));
    });

    test('a missing blob decodes to a placeholder text part', () {
      final encoded = ChatMessageCodec.encodeForLog(_withImage('hi'));
      final decoded = ChatMessageCodec.decode(encoded.payload);
      expect(decoded.parts[1].type, 'text');
      expect(decoded.parts[1].value, ChatMessageCodec.missingBlobText);
    });
  });

  group('recorder + reader (in-memory)', () {
    test('logs refs instead of attachment data and restores it on load',
        () async {
      final store = InMemorySessionEventStore();
      final message = _withImage('看图');
      await _record(store, 'c1', [message]);

      final events = await store.events('c1');
      final logged = events.firstWhere((e) => e.type == SessionEventType.message);
      expect(logged.payloadJson.contains('AAAA'), isFalse);

      final reader = await SessionLogReader.load(store, 'c1');
      final request = reader.requestsFor('r-c1').single;
      expect(ChatMessageCodec.canonicalJson(request.single),
          ChatMessageCodec.canonicalJson(message));
      // contentKey 不因拆分改变，重复内容仍能去重。
      expect(logged.contentKey, ChatMessageCodec.contentKey(message));
    });

    test('shared attachments are kept until no conversation references them',
        () async {
      final store = InMemorySessionEventStore();
      await _record(store, 'a', [_withImage('a')]);
      await _record(store, 'b', [_withImage('b')]);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      store.deleteConversation('a');
      expect(await store.pruneBlobs(unusedSince: yesterday), 0);
      store.deleteConversation('b');
      expect(await store.pruneBlobs(unusedSince: yesterday), 1);
    });
  });

  group('drift', () {
    late AppDatabase db;
    late DriftSessionEventStore store;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftSessionEventStore(db);
    });
    tearDown(() => db.close());

    test('round-trips attachments through session_blobs', () async {
      final message = _withImage('看图');
      await _record(store, 'c1', [message, _withImage('again')]);

      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM session_blobs')
          .getSingle();
      expect(count.read<int>('c'), 1, reason: '同一附件只存一份');
      final reader = await SessionLogReader.load(store, 'c1');
      expect(
          ChatMessageCodec.canonicalJson(reader.requestsFor('r-c1').single[0]),
          ChatMessageCodec.canonicalJson(message));
    });

    test('deleting the conversation lets maintenance drop its attachments',
        () async {
      final conversation = Conversation(
        id: 'c1',
        title: 't',
        agentId: null,
        projectId: null,
        mode: 'chat',
        providerProfileId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await db.saveConversation(conversation);
      await _record(store, 'c1', [_withImage('看图')]);
      final monthAgo = DateTime.now().subtract(const Duration(days: 30));

      expect(await store.pruneBlobs(unusedSince: monthAgo), 0);
      await db.deleteConversation('c1');
      expect(await store.pruneBlobs(unusedSince: monthAgo), 1);
    });

    test('attachments unused past the retention window are dropped',
        () async {
      await _record(store, 'c1', [_withImage('看图')]);
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      expect(await store.pruneBlobs(unusedSince: tomorrow), 1);
      final reader = await SessionLogReader.load(store, 'c1');
      final restored = reader.requestsFor('r-c1').single.single;
      expect(restored.parts[1].value, ChatMessageCodec.missingBlobText);
    });
  });
}
