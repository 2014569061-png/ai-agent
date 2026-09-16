import '../domain/models.dart';
import 'context_window.dart';
import 'file_citation.dart';
import 'project_context_service.dart';

class PromptBudgetPlan {
  const PromptBudgetPlan({
    required this.totalTokens,
    required this.systemTokens,
    required this.toolTokens,
    required this.reservedOutputTokens,
    required this.historyTokens,
    required this.fileTokens,
    required this.omitted,
    required this.messages,
    required this.projectContext,
  });

  final int totalTokens;
  final int systemTokens;
  final int toolTokens;
  final int reservedOutputTokens;
  final int historyTokens;
  final int fileTokens;
  final List<String> omitted;
  final List<ChatMessage> messages;
  final ProjectContext projectContext;
}

class PromptBudgetAllocator {
  const PromptBudgetAllocator();

  static const defaultReservedOutput = 2048;

  PromptBudgetPlan allocate({
    required int contextTokens,
    required String systemPrompt,
    required List<UnifiedTool> tools,
    required List<ChatMessage> history,
    required ProjectContext projectContext,
    int reservedOutputTokens = defaultReservedOutput,
  }) {
    final systemTokens = ContextWindow.estimateTokens(ChatMessage(
      role: MessageRole.system,
      parts: [MessagePart.text(systemPrompt)],
    ));
    final toolTokens = tools.fold<int>(0, (sum, tool) {
      final encoded =
          '${tool.name} ${tool.description} ${tool.parametersSchema}';
      return sum + ContextWindow.estimateTokens(ChatMessage(
        role: MessageRole.system,
        parts: [MessagePart.text(encoded)],
      ));
    });
    final remaining = (contextTokens - systemTokens - toolTokens - reservedOutputTokens)
        .clamp(0, contextTokens);
    final historyBudget = (remaining * 0.7).floor();
    final fileBudget = remaining - historyBudget;
    final compacted = ContextWindow(maxTokens: historyBudget).apply(history);
    final omitted = <String>[];
    if (compacted.length < history.length) {
      omitted.add('较早对话历史');
    }
    var fileTokens = 0;
    final keptCitations = <FileCitation>[];
    final keptSnippets = <String>[];
    for (final citation in projectContext.citations) {
      final cost = ContextWindow.estimateTokens(ChatMessage(
        role: MessageRole.user,
        parts: [MessagePart.text(citation.excerpt)],
      ));
      if (fileTokens + cost > fileBudget) {
        omitted.add(citation.displayLabel);
        continue;
      }
      fileTokens += cost;
      keptCitations.add(citation);
    }
    for (final snippet in projectContext.relatedSnippets) {
      final cost = ContextWindow.estimateTokens(ChatMessage(
        role: MessageRole.user,
        parts: [MessagePart.text(snippet)],
      ));
      if (fileTokens + cost > fileBudget) {
        omitted.add('相关片段');
        continue;
      }
      fileTokens += cost;
      keptSnippets.add(snippet);
    }
    final allocatedContext = ProjectContext(
      projectId: projectContext.projectId,
      workspacePath: projectContext.workspacePath,
      goal: projectContext.goal,
      constraints: projectContext.constraints,
      rules: projectContext.rules,
      taskSummary: projectContext.taskSummary,
      citations: keptCitations,
      relatedSnippets: keptSnippets,
      omitted: omitted,
    );
    return PromptBudgetPlan(
      totalTokens: contextTokens,
      systemTokens: systemTokens,
      toolTokens: toolTokens,
      reservedOutputTokens: reservedOutputTokens,
      historyTokens: compacted.fold<int>(
          0, (sum, message) => sum + ContextWindow.estimateTokens(message)),
      fileTokens: fileTokens,
      omitted: omitted,
      messages: compacted,
      projectContext: allocatedContext,
    );
  }
}
