import 'dart:convert';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/message_history_store.dart';

class ConversationForkService {
  const ConversationForkService();

  Future<Conversation> fork({
    required AppDatabase db,
    required String sourceConversationId,
    required String forkMessageId,
    bool replaceSubsequent = false,
  }) =>
      db.transaction(() async {
        final source = await db.findConversation(sourceConversationId);
        if (source == null) {
          throw StateError('原会话不存在');
        }
        final now = DateTime.now();
        final tags = _decodeTags(source.tagsJson)
          ..removeWhere((item) =>
              item.startsWith('parent:') || item.startsWith('forkMessage:'))
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
        // Both legacy modes copy through the anchor; never replay tool effects.
        await MessageHistoryStore(db)
            .copyThrough(sourceConversationId, forkMessageId, branch.id);
        return branch;
      });

  List<String> _decodeTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
    } catch (_) {
      // 历史数据里的 tags JSON 可能来自旧版本或手工修改；分叉仍可继续，只是
      // 在无法解析时从空标签集合开始。
    }
    return <String>[];
  }
}
