import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import 'memory_service.dart';

/// Immutable, application-owned scope. Model arguments never select the project.
class ScopedMemoryAccess {
  ScopedMemoryAccess(
      {required this.database, String? projectId, this.sourceConversationId})
      : scope = MemoryScope(projectId: projectId);
  final Future<AppDatabase> Function() database;
  final MemoryScope scope;
  final String? sourceConversationId;
  final _service = MemoryService();
  Future<ToolResult> _guard(Future<ToolResult> Function(AppDatabase) action,
      {bool mayMutate = false}) async {
    try {
      return await action(await database());
    } on MemoryConflictException catch (error) {
      return ToolResult.failure(
          code: ToolCodes.revisionConflict,
          message: '记忆已变化，请重新调用 memory_get，并基于本次范围的 revision 确认后再写入',
          data: {'revision': error.currentRevision});
    } on MemoryForgottenException {
      return ToolResult.failure(
          code: ToolCodes.permissionRequired,
          message: '用户已遗忘或更正此内容，或已关闭原来源会话的自动记忆；未写入。不得改写后重试。需要时请用户在记忆管理中手动保存。',
          data: const {'reason': 'memory_forgotten'});
    } on MemoryAccessDenied {
      return ToolResult.failure(
          code: ToolCodes.permissionRequired,
          message: '记忆不在本次运行的项目授权范围内，未读取或修改');
    } on FormatException catch (error) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments, message: error.message);
    } catch (_) {
      return ToolResult.failure(
          code: ToolCodes.toolError,
          message: '记忆操作未完成，未确认写入；请刷新记录后核实',
          effect: mayMutate ? ToolEffect.unknown : ToolEffect.none);
    }
  }

  Future<ToolResult> get(String query, int offset, int limit) =>
      _guard((db) => db.transaction(() async {
            if (query.length > 512 || offset < 0 || limit < 1 || limit > 100) {
              throw const FormatException('记忆查询参数超出范围');
            }
            final matched = await _service.search(db, query,
                offset: offset, limit: limit + 1, scope: scope);
            final hasMore = matched.length > limit;
            final rows = matched.take(limit).toList();
            return ToolResult.success(
                message: rows.isEmpty ? '未找到匹配记忆' : '已读取 ${rows.length} 条记忆',
                data: {
                  'revision': await _service.currentRevision(db, scope: scope),
                  'revisionScope': scope.projectId == null
                      ? 'global'
                      : 'global+project:${scope.projectId}',
                  'offset': offset,
                  'limit': limit,
                  'hasMore': hasMore,
                  'nextOffset': hasMore ? offset + rows.length : null,
                  'items': rows
                      .map((r) => {
                            'id': r.id,
                            'content': r.content,
                            'category': r.category,
                            'importance': r.importance,
                            'sourceType': r.sourceType,
                            'sourceConversationId': r.sourceConversationId,
                            'updatedAt': r.updatedAt.toUtc().toIso8601String()
                          })
                      .toList(),
                });
          }));
  Future<ToolResult> remember(String content, String? expectedRevision) =>
      _guard(
          (db) => db.transaction(() async {
                if (content.trim().isEmpty || content.length > 3500) {
                  throw const FormatException('长期记忆必须为1–3500字符');
                }
                final memory = await _service.add(
                    database: db,
                    content: content,
                    sourceType: 'agent',
                    importance: 2,
                    sourceConversationId: sourceConversationId,
                    expectedRevision: expectedRevision,
                    scope: scope);
                return ToolResult.success(
                    message: '已按本次授权保存记忆',
                    effect: ToolEffect.applied,
                    data: {
                      'id': memory.id,
                      'category': memory.category,
                      'revision':
                          await _service.currentRevision(db, scope: scope)
                    });
              }),
          mayMutate: true);
  Future<ToolResult> write(
          {required String? id,
          required String content,
          required String mode,
          required int? startLine,
          required int? endLine,
          required String? expectedRevision}) =>
      _guard(
          (db) => db.transaction(() async {
                if (id != null &&
                    id.isNotEmpty &&
                    (expectedRevision == null || expectedRevision.isEmpty)) {
                  throw MemoryConflictException(
                      await _service.currentRevision(db, scope: scope));
                }
                final memory = await _service.write(
                    database: db,
                    id: id,
                    content: content,
                    mode: mode,
                    startLine: startLine,
                    endLine: endLine,
                    expectedRevision: expectedRevision,
                    scope: scope,
                    sourceConversationId: sourceConversationId);
                return ToolResult.success(
                    message: '记忆已按授权范围写入',
                    effect: ToolEffect.applied,
                    data: {
                      'id': memory.id,
                      'category': memory.category,
                      'mode': mode,
                      'revision':
                          await _service.currentRevision(db, scope: scope)
                    });
              }),
          mayMutate: true);
}
