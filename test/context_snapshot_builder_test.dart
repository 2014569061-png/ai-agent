import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/application/context_snapshot_builder.dart';
import 'package:mobile_agent/domain/context_insights.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  group('ContextSnapshotBuilder', () {
    test('uses the same estimator as the request budget', () {
      final snapshot = ContextSnapshotBuilder.build(
        contextWindow: 32000,
        reservedOutputTokens: 2048,
        tools: const [
          UnifiedTool(
            name: 'search_files',
            description: 'Search project files',
            parametersSchema: {'type': 'object'},
            risk: ToolRisk.safe,
          ),
        ],
        messages: [
          ChatMessage(
            role: MessageRole.system,
            parts: const [MessagePart.text('You are a coding agent.')],
          ),
          ChatMessage(
            role: MessageRole.system,
            parts: const [MessagePart.text('## 长期记忆\n- Prefer Dart')],
          ),
          ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('Please inspect this project.')],
          ),
          ChatMessage(
            role: MessageRole.assistant,
            parts: const [MessagePart.text('I will inspect it.')],
          ),
          ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'call-1',
            parts: const [MessagePart.text('lib/main.dart')],
          ),
        ],
      );

      expect(snapshot.contextWindow, 32000);
      expect(snapshot.reservedOutputTokens, 2048);
      expect(snapshot.usedTokens, greaterThan(0));
      expect(
        snapshot.parts
            .firstWhere((part) => part.type == ContextPartType.system)
            .tokens,
        greaterThan(0),
      );
      expect(
        snapshot.parts
            .firstWhere((part) => part.type == ContextPartType.inject)
            .tokens,
        greaterThan(0),
      );
      expect(
        snapshot.parts
            .firstWhere((part) => part.type == ContextPartType.tools)
            .tokens,
        greaterThan(0),
      );
      expect(
        snapshot.parts
            .firstWhere((part) => part.type == ContextPartType.toolResult)
            .tokens,
        greaterThan(0),
      );
    });

    test('keeps provider usage separate from estimated context composition',
        () {
      final snapshot = ContextSnapshotBuilder.build(
        contextWindow: 128000,
        reservedOutputTokens: 4096,
        tools: const [],
        messages: [
          ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('hello')],
          ),
        ],
      ).withProviderUsage(const Usage(
        promptTokens: 120,
        completionTokens: 30,
        usageReported: true,
      ));

      expect(snapshot.usedTokens, isNot(150));
      expect(snapshot.providerTotalTokens, 150);
      expect(
        snapshot.parts
            .firstWhere((part) => part.type == ContextPartType.user)
            .estimated,
        isTrue,
      );
    });

    test('reports omitted and truncated context content', () {
      final snapshot = ContextSnapshotBuilder.build(
        contextWindow: 32000,
        reservedOutputTokens: 2048,
        tools: const [],
        messages: [
          ChatMessage(
            role: MessageRole.system,
            parts: const [MessagePart.text(ContextWindow.compactionNotice)],
          ),
          ChatMessage(
            role: MessageRole.assistant,
            parts: const [MessagePart.text('调用工具')],
            toolCalls: [
              const ToolCall(
                id: 'call-1',
                name: 'read_file',
                arguments: {ContextWindow.truncatedArgumentMark: true},
              ),
            ],
          ),
          ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'call-1',
            parts: const [
              MessagePart.text(
                '结果\n${ContextWindow.toolResultTruncatedMark}',
              ),
            ],
          ),
        ],
      );

      expect(snapshot.omittedParts, contains('较早对话历史'));
      expect(snapshot.truncatedParts, contains('工具结果'));
      expect(snapshot.truncatedParts, contains('工具参数'));
    });
  });
}
