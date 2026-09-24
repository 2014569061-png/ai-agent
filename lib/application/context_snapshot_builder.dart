import '../domain/context_insights.dart';
import '../domain/models.dart';
import 'context_window.dart';

/// Derives a request-shaped context breakdown from the exact messages and tool
/// definitions sent to a provider. These figures deliberately use the same
/// estimator as [ContextWindow], so budget decisions and the UI do not drift.
class ContextSnapshotBuilder {
  const ContextSnapshotBuilder._();

  static ContextSnapshot build({
    required List<ChatMessage> messages,
    required List<UnifiedTool> tools,
    required int contextWindow,
    required int reservedOutputTokens,
  }) {
    final totals = <ContextPartType, int>{
      for (final type in ContextPartType.values) type: 0,
    };
    final omittedParts = <String>{};
    final truncatedParts = <String>{};

    for (final message in messages) {
      if (message.text.contains(ContextWindow.compactionNotice)) {
        omittedParts.add('较早对话历史');
      }
      if (message.role == MessageRole.tool &&
          message.text.contains(ContextWindow.toolResultTruncatedMark)) {
        truncatedParts.add('工具结果');
      }
      if (message.role == MessageRole.tool &&
          message.text.contains(ContextWindow.compressedToolResultMark)) {
        omittedParts.add('工具结果');
      }
      if (message.toolCalls.any((call) =>
          call.arguments.containsKey(ContextWindow.truncatedArgumentMark))) {
        truncatedParts.add('工具参数');
      }
      if (message.role == MessageRole.system) {
        _addSystemMessage(totals, message);
      } else {
        final type = _typeForMessage(message);
        totals[type] = totals[type]! + ContextWindow.estimateTokens(message);
      }
    }
    totals[ContextPartType.tools] = estimateToolTokens(tools);

    final parts = ContextPartType.values
        .map(
          (type) => ContextPart(
            type: type,
            tokens: totals[type] ?? 0,
          ),
        )
        .toList(growable: false);
    final usedTokens = parts.fold<int>(0, (total, part) => total + part.tokens);

    return ContextSnapshot(
      parts: parts,
      usedTokens: usedTokens,
      contextWindow: contextWindow,
      reservedOutputTokens: reservedOutputTokens,
      updatedAt: DateTime.now(),
      omittedParts: List.unmodifiable(omittedParts),
      truncatedParts: List.unmodifiable(truncatedParts),
    );
  }

  static void _addSystemMessage(
    Map<ContextPartType, int> totals,
    ChatMessage message,
  ) {
    final sections = _splitSystemSections(message.text);
    if (sections.length <= 1) {
      final type = _typeForSystemText(message.text);
      totals[type] = totals[type]! + ContextWindow.estimateTokens(message);
      return;
    }

    final fullTokens = ContextWindow.estimateTokens(message);
    final weights = sections
        .map((section) => ContextWindow.estimateTokens(
              ChatMessage(
                role: MessageRole.system,
                parts: [MessagePart.text(section.$2)],
              ),
            ))
        .toList(growable: false);
    final weightTotal = weights.fold<int>(0, (total, weight) => total + weight);
    var assigned = 0;
    for (var index = 0; index < sections.length; index++) {
      final tokens = index == sections.length - 1
          ? fullTokens - assigned
          : (fullTokens * weights[index] / weightTotal).round();
      totals[sections[index].$1] = totals[sections[index].$1]! + tokens;
      assigned += tokens;
    }
  }

  static List<(ContextPartType, String)> _splitSystemSections(String text) {
    final lines = text.split('\n');
    final sections = <(ContextPartType, String)>[];
    var type = ContextPartType.system;
    final buffer = StringBuffer();

    void commit() {
      final content = buffer.toString().trim();
      if (content.isNotEmpty) sections.add((type, content));
      buffer.clear();
    }

    for (final line in lines) {
      final nextType = _explicitSystemSectionType(line);
      if (nextType != null) {
        commit();
        type = nextType;
      }
      buffer.writeln(line);
    }
    commit();
    return sections;
  }

  static ContextPartType _typeForMessage(ChatMessage message) {
    return switch (message.role) {
      MessageRole.user => ContextPartType.user,
      MessageRole.assistant => ContextPartType.assistant,
      MessageRole.tool => ContextPartType.toolResult,
      MessageRole.system => _typeForSystemText(message.text),
    };
  }

  static ContextPartType _typeForSystemText(String text) =>
      _explicitSystemSectionType(text) ?? ContextPartType.system;

  static ContextPartType? _explicitSystemSectionType(String text) {
    final normalized = text.trimLeft();
    if (normalized.startsWith('## 可用 Skill') ||
        normalized.startsWith('## 会话 Skill')) {
      return ContextPartType.skill;
    }
    if (normalized.startsWith('## 长期记忆') ||
        normalized.startsWith('## 知识库') ||
        normalized.startsWith('[项目上下文]')) {
      return ContextPartType.inject;
    }
    if (normalized.startsWith('[委派规则]') ||
        normalized.startsWith('[自主委派规则]') ||
        normalized.startsWith('[运行环境]') ||
        normalized.startsWith('[计划模式]')) {
      return ContextPartType.system;
    }
    return null;
  }

  /// Estimates serialized tool-definition cost. The same helper is used by
  /// the request budget and the snapshot so the UI cannot under-report tools.
  static int estimateToolTokens(List<UnifiedTool> tools) {
    return tools.fold<int>(0, (total, tool) {
      final description =
          '${tool.name} ${tool.description} ${tool.parametersSchema}';
      return total +
          ContextWindow.estimateTokens(
            ChatMessage(
              role: MessageRole.system,
              parts: [MessagePart.text(description)],
            ),
          );
    });
  }
}
