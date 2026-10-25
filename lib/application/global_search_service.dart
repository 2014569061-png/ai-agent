import 'dart:convert';
import 'package:drift/drift.dart';
import '../infrastructure/database/app_database.dart';

enum SearchKind {
  conversation,
  message,
  task,
  project,
  artifact,
  knowledge,
  memory
}

class SearchCursor {
  const SearchCursor(this.seconds, this.kind, this.id);
  final int seconds;
  final String kind;
  final String id;
}

class SearchHit {
  const SearchHit(
      {required this.kind,
      required this.id,
      required this.title,
      required this.snippet,
      required this.seconds,
      this.projectId,
      this.conversationId});
  final SearchKind kind;
  final String id, title, snippet;
  final int seconds;
  final String? projectId, conversationId;
  DateTime get updatedAt =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  SearchCursor get cursor => SearchCursor(seconds, kind.name, id);
  String get key => '${kind.name}:$id';
}

class SearchPageResult {
  const SearchPageResult(this.items, this.next);
  final List<SearchHit> items;
  final SearchCursor? next;
}

/// Read-only, on-device database search. No model, network, or recent-list cache.
/// Cursor paging avoids offset skips caused by unrelated insertions/deletions.
class GlobalSearchService {
  const GlobalSearchService(this.db);
  final AppDatabase db;
  static const _records = '''
SELECT 'conversation' AS kind, c.id AS id, c.title AS title, c.title AS body,
 c.project_id AS project_id, c.id AS conversation_id, c.updated_at AS stamp,
 c.title AS search_text FROM conversations c
UNION ALL
SELECT 'message', m.id, c.title, m.content, c.project_id, c.id, m.created_at,
 m.content FROM messages m JOIN conversations c ON c.id=m.conversation_id
UNION ALL
SELECT 'task', id, substr(request_json,1,16000), status, project_id, conversation_id,
 updated_at, request_json || ' ' || progress_json || ' ' || status FROM tasks
UNION ALL
SELECT 'project', id, name, canonical_root_path, id, NULL, updated_at,
 name || ' ' || canonical_root_path FROM projects
UNION ALL
SELECT 'artifact', id, relative_path, inspection_json, project_id, NULL,
 COALESCE(CAST(strftime('%s',created_at) AS INTEGER),0),
 relative_path || ' ' || kind || ' ' || task_id FROM artifacts
UNION ALL
SELECT 'knowledge', d.id, d.name, d.source_type, s.project_id, NULL, d.updated_at,
 d.name FROM knowledge_docs d LEFT JOIN knowledge_doc_scopes s ON s.doc_id=d.id
UNION ALL
SELECT 'memory', id, category, content,
 CASE WHEN lower(substr(trim(category),1,8))='project:' THEN substr(trim(category),9) ELSE NULL END,
 source_conversation_id, updated_at, content || ' ' || category FROM memories
''';

  Future<SearchPageResult> search(
      {String query = '',
      SearchKind? kind,
      String? projectId,
      DateTime? since,
      DateTime? before,
      SearchCursor? after,
      int limit = 50}) async {
    final normalized = query.trim();
    if (normalized.length > 512 ||
        (projectId?.length ?? 0) > 256 ||
        limit < 1 ||
        limit > 100) {
      throw ArgumentError('搜索词最多512字符，每页1–100项');
    }
    if (since != null && before != null && !since.isBefore(before)) {
      throw ArgumentError('日期范围无效');
    }
    final where = <String>[];
    final variables = <Variable>[];
    if (normalized.isNotEmpty) {
      final escaped = normalized
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      where.add(
          "(search_text LIKE ? ESCAPE '\\' OR (kind='knowledge' AND EXISTS("
          "SELECT 1 FROM knowledge_chunks k WHERE k.doc_id=records.id AND k.content LIKE ? ESCAPE '\\')))");
      variables.addAll(
          [Variable<String>('%$escaped%'), Variable<String>('%$escaped%')]);
    }
    if (kind != null) {
      where.add('kind=?');
      variables.add(Variable<String>(kind.name));
    }
    if (projectId != null && projectId.trim().isNotEmpty) {
      where.add('project_id=?');
      variables.add(Variable<String>(projectId.trim()));
    }
    if (since != null) {
      where.add('stamp>=?');
      variables.add(Variable<int>(since.millisecondsSinceEpoch ~/ 1000));
    }
    if (before != null) {
      where.add('stamp<?');
      variables.add(Variable<int>(before.millisecondsSinceEpoch ~/ 1000));
    }
    if (after != null) {
      if (!SearchKind.values.any((k) => k.name == after.kind)) {
        throw ArgumentError('游标类型无效');
      }
      where.add('(stamp<? OR (stamp=? AND (kind>? OR (kind=? AND id>?))))');
      variables.addAll([
        Variable<int>(after.seconds),
        Variable<int>(after.seconds),
        Variable<String>(after.kind),
        Variable<String>(after.kind),
        Variable<String>(after.id)
      ]);
    }
    final rows = await db.customSelect(
        'WITH records AS ($_records) '
        'SELECT kind,id,substr(title,1,16000) AS title,substr(body,1,240) AS snippet,'
        'project_id,conversation_id,stamp FROM records '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY stamp DESC,kind ASC,id ASC LIMIT ?',
        variables: [...variables, Variable<int>(limit + 1)]).get();
    final hits = [for (final row in rows.take(limit)) _hit(row)];
    return SearchPageResult(
        List.unmodifiable(hits), rows.length > limit ? hits.last.cursor : null);
  }

  /// Reread on opening: deleted records return null; never execute a search hit.
  /// Source text is explicitly capped, not advertised as an unbounded export.
  Future<String?> readSource(SearchHit hit) async {
    final rows = await db.customSelect(
        'WITH records AS ($_records) '
        'SELECT kind,id,title,substr(body,1,12001) AS body,project_id,conversation_id,stamp '
        'FROM records WHERE kind=? AND id=? LIMIT 1',
        variables: [
          Variable<String>(hit.kind.name),
          Variable<String>(hit.id)
        ]).get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    var body = row.read<String>('body');
    if (hit.kind == SearchKind.knowledge) {
      final chunks = await (db.select(db.knowledgeChunks)
            ..where((c) => c.docId.equals(hit.id))
            ..orderBy([(c) => OrderingTerm.asc(c.index)])
            ..limit(16))
          .get();
      body = [
        row.read<String>('title'),
        body,
        for (final c in chunks.take(15)) '${c.id}\n${c.content}',
        if (chunks.length > 15) '[仅读取前15个分块]',
      ].join('\n');
    }
    return [
      '类型：${label(hit.kind)}',
      '记录标识：${hit.id}',
      '项目：${row.readNullable<String>('project_id') ?? '无项目关联'}',
      '会话：${row.readNullable<String>('conversation_id') ?? '未关联'}',
      '时间（UTC）：${DateTime.fromMillisecondsSinceEpoch(row.read<int>('stamp') * 1000, isUtc: true).toIso8601String()}',
      '只读本地记录；不代表文件仍存在、内容可信或任务已完成。',
      '',
      body.length > 12000 ? '${body.substring(0, 12000)}\n[仅展示前12000字符]' : body,
    ].join('\n');
  }

  static SearchHit _hit(QueryRow row) {
    final kind = SearchKind.values.byName(row.read<String>('kind'));
    final id = row.read<String>('id');
    var title = row.read<String>('title');
    if (kind == SearchKind.task) {
      try {
        final detail = jsonDecode(title);
        title = detail is Map
            ? (detail['title'] ?? detail['prompt'] ?? '任务 $id').toString()
            : '任务 $id';
      } catch (_) {
        title = '任务 $id';
      }
    }
    return SearchHit(
        kind: kind,
        id: id,
        title: String.fromCharCodes(title.runes.take(120)),
        snippet: row.read<String>('snippet'),
        seconds: row.read<int>('stamp'),
        projectId: row.readNullable<String>('project_id'),
        conversationId: row.readNullable<String>('conversation_id'));
  }

  static String label(SearchKind kind) => switch (kind) {
        SearchKind.conversation => '会话',
        SearchKind.message => '会话消息',
        SearchKind.task => '任务',
        SearchKind.project => '项目',
        SearchKind.artifact => '成果记录',
        SearchKind.knowledge => '知识资料',
        SearchKind.memory => '记忆',
      };
}
