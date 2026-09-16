import 'dart:convert';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';

class ConversationForkService {
  const ConversationForkService();

  Future<Conversation> fork({
    required AppDatabase db,
    required String sourceConversationId,
    required String forkMessageId,
    bool replaceSubsequent = false,
  }) async {
    final source = await db.findConversation(sourceConversationId);
    if (source == null) {
      throw StateError('原会话不存在');
    }
    final messages = await db.messagesFor(sourceConversationId);
    final forkIndex = messages.indexWhere((item) => item.id == forkMessageId);
    if (forkIndex < 0) {
      throw StateError('找不到分叉消息');
    }
    final now = DateTime.now();
    final tags = _decodeTags(source.tagsJson)
      ..removeWhere((item) => item.startsWith('parent:') || item.startsWith('forkMessage:'))
      ..add('parent:$sourceConversationId')
      ..add('forkMessage:$forkMessageId');
    final branch = source.copyWith(
      id: UniqueId.generate('conv'),
      title: '${source.title}（分支）',
      tagsJson: jsonEncode(tags),
      createdAt: now,
      updatedAt: now,
    );
    await db.saveConversation(branch);
    final copied = replaceSubsequent
        ? messages.take(forkIndex + 1)
        : messages.take(forkIndex + 1);
    for (final message in copied) {
      await db.saveMessage(message.copyWith(
        id: UniqueId.generate('msg'),
        conversationId: branch.id,
      ));
    }
    return branch;
  }

  List<String> _decodeTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
    } catch (_) {}
    return <String>[];
  }
}
