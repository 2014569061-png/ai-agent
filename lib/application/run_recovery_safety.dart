import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import '../domain/models.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/run_plan_store.dart';
import 'task_service.dart';

class RunRecoveryNeedsReview implements Exception {
  const RunRecoveryNeedsReview(this.reason);
  final String reason;
  static const verificationSteps = '先以只读方式检查工作区文件、Git diff/日志，以及外部目标的实际状态；'
      '对照任务执行记录确认哪些步骤已经生效。不要重新提交原终端命令。'
      '核实后保留原记录，以明确的新请求仅执行尚未完成的步骤；'
      '本入口不会自动把未知结果标记为未执行。';
  @override
  String toString() => '$reason 已阻止直接重跑，原断点与记录已保留。$verificationSteps';
}

/// Recovery does not mean replay. Unknown dispatches are never converted to
/// effect=none; applied effects require a matching, result-complete checkpoint.
class RunRecoverySafety {
  const RunRecoverySafety();

  Future<void> requireSafe(AppDatabase db, String taskId,
          {List<ChatMessage>? initialHistory, bool inspectPersisted = false}) =>
      db.transaction(() async {
        final task = await db.findTask(taskId);
        if (task == null) {
          throw const RunRecoveryNeedsReview('任务记录不存在，无法核实原运行。');
        }
        final rows = await db.customSelect(
          'SELECT run_id,call_id,state,effect FROM run_dispatch_claims WHERE task_id=?',
          variables: [Variable<String>(taskId)],
        ).get();
        if (rows.any((row) =>
            row.read<String>('state') != 'settled' ||
            !const {'none', 'applied'}.contains(row.read<String>('effect')))) {
          throw const RunRecoveryNeedsReview('存在结果未知或尚未收敛的工具操作。');
        }
        Map<dynamic, dynamic>? checkpoint;
        try {
          final progress = jsonDecode(task.progressJson);
          if (progress is Map && progress['checkpoint'] is Map) {
            checkpoint = progress['checkpoint'] as Map;
          }
        } catch (_) {
          // Missing/corrupt checkpoints cannot prove completed effects were kept.
        }
        final context = initialHistory ??
            (inspectPersisted
                ? decodeChatContext(checkpoint?['context'])
                : const <ChatMessage>[]);
        final completed = <String>{};
        final calls = <String>{
          for (final message in context)
            if (message.role == MessageRole.assistant)
              for (final call in message.toolCalls) call.id
        };
        for (final message in context) {
          if (message.role != MessageRole.tool) continue;
          dynamic result;
          try {
            result = jsonDecode(message.text);
          } catch (_) {
            continue;
          }
          if (result is! Map) continue;
          final effect = result['effect'];
          if (effect != null && !const {'none', 'applied'}.contains(effect)) {
            throw const RunRecoveryNeedsReview('断点包含尚待核实的工具结果。');
          }
          if (effect == 'applied' && calls.contains(message.toolCallId)) {
            completed.add(message.toolCallId!);
          }
        }
        final applied =
            rows.where((row) => row.read<String>('effect') == 'applied');
        if (applied.isEmpty) return;
        final head = await RunPlanStore(db).head(taskId);
        if (checkpoint?['version'] != 1 ||
            head == null ||
            checkpoint?['runId'] != head.token.runId ||
            applied.any(
                (row) => !completed.contains(row.read<String>('call_id')))) {
          throw const RunRecoveryNeedsReview('已有生效操作，但缺少匹配且完整的恢复断点。');
        }
      });

  /// Covers regenerate/edit entry points even when the UI activity list was
  /// lost at process death. Explicit new requests are not silently rewritten.
  Future<void> requireReplayFreeConversation(AppDatabase db,
      {required String? conversationId,
      required Iterable<ToolEffect?> visibleEffects,
      required List<ChatMessage> messages}) async {
    if (visibleEffects.any((effect) =>
        effect == ToolEffect.applied || effect == ToolEffect.unknown)) {
      throw const RunRecoveryNeedsReview('本轮已有生效或结果未知的操作。');
    }
    for (final message in messages.reversed) {
      if (message.role == MessageRole.user) break;
      if (message.role != MessageRole.tool) continue;
      dynamic result;
      try {
        result = jsonDecode(message.text);
      } catch (_) {
        continue;
      }
      if (result is Map &&
          result['effect'] != null &&
          result['effect'] != 'none') {
        throw const RunRecoveryNeedsReview('本轮工具记录不支持从原始请求重放。');
      }
    }
    if (conversationId == null) return;
    final rows = await db.customSelect(
      'SELECT 1 FROM run_dispatch_claims c JOIN tasks t ON t.id=c.task_id '
      "WHERE t.conversation_id=? AND (c.state<>'settled' OR c.effect NOT IN ('none','applied') "
      "OR (c.effect='applied' AND c.task_id=(SELECT id FROM tasks WHERE conversation_id=? "
      'ORDER BY created_at DESC,id DESC LIMIT 1))) LIMIT 1',
      variables: [
        Variable<String>(conversationId),
        Variable<String>(conversationId)
      ],
    ).get();
    if (rows.isNotEmpty) {
      throw const RunRecoveryNeedsReview('持久化记录中存在不可盲目重放的操作。');
    }
  }
}
