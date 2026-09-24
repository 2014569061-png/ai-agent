import '../domain/history_load_result.dart';
import '../infrastructure/database/app_database.dart';

/// Owns cursor and single-flight state. Reset invalidates *all* pending results.
class ConversationHistoryPager {
  static const initialSize = 200;
  static const pageSize = 100;
  DateTime? _before;
  int? _beforeRowId;
  bool _exhausted = true;
  int _revision = 0;
  Future<(HistoryLoadResult, List<Message>)>? _pending;

  void track(List<(Message, int)> page) {
    _revision++;
    _pending = null;
    _before = page.isEmpty ? null : page.first.$1.createdAt;
    _beforeRowId = page.isEmpty ? null : page.first.$2;
    _exhausted = page.length < initialSize;
  }

  Future<(HistoryLoadResult, List<Message>)> load(
    AppDatabase db,
    String conversationId,
    bool Function() isCurrent,
  ) {
    if (_pending != null) return _pending!;
    if (_exhausted || _before == null) {
      return Future.value((HistoryLoadResult.exhausted, const <Message>[]));
    }
    final revision = _revision;
    final future = () async {
      try {
        final page = await db.messagesPage(conversationId,
            before: _before, beforeRowId: _beforeRowId, limit: pageSize);
        if (revision != _revision || !isCurrent()) {
          return (HistoryLoadResult.stale, <Message>[]);
        }
        _exhausted = page.length < pageSize;
        if (page.isEmpty) return (HistoryLoadResult.exhausted, <Message>[]);
        _before = page.first.$1.createdAt;
        _beforeRowId = page.first.$2;
        return (HistoryLoadResult.loaded, page.map((e) => e.$1).toList());
      } catch (_) {
        // Keep the cursor retryable. The caller exposes failure separately from EOF.
        return (HistoryLoadResult.failed, <Message>[]);
      } finally {
        if (revision == _revision) _pending = null;
      }
    }();
    _pending = future;
    return future;
  }
}
