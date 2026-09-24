import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/context_insights.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/session_metrics.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_sheet.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('session telemetry workspace renders snapshots and tabs',
      (tester) async {
    String? jumpedTo;
    final snapshot = ContextSnapshot(
      contextWindow: 128000,
      reservedOutputTokens: 4096,
      usedTokens: 32000,
      updatedAt: DateTime(2026),
      parts: const [
        ContextPart(type: ContextPartType.system, tokens: 2000),
        ContextPart(type: ContextPartType.tools, tokens: 4000),
        ContextPart(type: ContextPartType.user, tokens: 1000),
        ContextPart(type: ContextPartType.toolResult, tokens: 25000),
      ],
      providerUsage: const Usage(
        promptTokens: 33000,
        completionTokens: 800,
        cachedTokens: 12000,
        usageReported: true,
        cacheStatsReported: true,
      ),
      omittedParts: ['较早对话历史'],
      truncatedParts: ['工具结果'],
    );

    await tester.pumpWidget(wrap(SessionMetricsSheet(
      metrics: const SessionMetrics(
        rounds: 2,
        steps: 3,
        llmTime: Duration(seconds: 12),
        toolTime: Duration(seconds: 3),
        avgTtft: Duration(seconds: 1),
        tokensPerSecond: 42,
        cacheHitRate: 0.36,
        promptTokens: 33000,
        completionTokens: 800,
      ),
      liveContextTokens: 32000,
      contextLimit: 128000,
      contextSnapshot: snapshot,
      contextRuns: [
        ContextRunHistory(
          runId: 'history-run',
          startedAt: DateTime(2026, 1, 1, 12),
          status: 'success',
          steps: [
            ContextStepRecord(
              step: 1,
              snapshot: snapshot,
              startedAt: DateTime(2026, 1, 1, 12),
              anchorMessageId: 'message-1',
              usage: snapshot.providerUsage,
            ),
          ],
          events: [
            ContextRunEvent(
              type: 'file_operation',
              name: 'read_file',
              status: 'success',
              createdAt: DateTime.utc(2026),
              metadata: {'path': 'lib/main.dart'},
            ),
          ],
        ),
      ],
      timing: const TimingSnapshot(
        wallMs: 18000,
        modelWaitMs: 6000,
        reasoningMs: 3000,
        outputMs: 6000,
        toolExecutionMs: 3000,
        modelCalls: 3,
        toolCalls: 1,
      ),
      toolActivities: const [
        ToolActivity(
          call: ToolCall(id: 'read-1', name: 'read_file', arguments: {}),
          risk: ToolRisk.safe,
          status: '已完成',
          executionMs: 3000,
        ),
      ],
      onJumpToMessage: (id) => jumpedTo = id,
    )));

    await tester.tap(find.byKey(const ValueKey('metrics-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('当前上下文'), findsOneWidget);
    expect(find.text('32.0k'), findsOneWidget);
    expect(find.textContaining('主要占用：工具结果'), findsOneWidget);
    expect(find.textContaining('已压缩较早对话历史'), findsOneWidget);
    expect(find.textContaining('已截断工具结果'), findsOneWidget);
    expect(find.text('Token 构成'), findsOneWidget);
    expect(find.text('运行记录'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('历史运行 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('步骤'));
    await tester.pumpAndSettle();
    expect(find.text('上下文趋势'), findsOneWidget);
    expect(find.text('估算 ≈32.0k'), findsOneWidget);
    await tester.tap(find.text('估算 ≈32.0k'));
    expect(jumpedTo, 'message-1');

    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    expect(find.text('上下文浏览器'), findsOneWidget);
    expect(find.text('工具结果'), findsOneWidget);

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('文件活动'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);

    await tester.tap(find.text('网络'));
    await tester.pumpAndSettle();
    expect(find.text('Agent 网络'), findsOneWidget);
    expect(find.text('运行 Agent'), findsOneWidget);
  });

  testWidgets(
      'shows a review-only compression suggestion for large tool results',
      (tester) async {
    var applied = false;
    final snapshot = ContextSnapshot(
      contextWindow: 1000,
      reservedOutputTokens: 100,
      usedTokens: 1200,
      updatedAt: DateTime(2026),
      parts: const [
        ContextPart(type: ContextPartType.toolResult, tokens: 1200),
      ],
    );

    await tester.pumpWidget(wrap(SessionMetricsSheet(
      metrics: const SessionMetrics(
        rounds: 1,
        steps: 1,
        llmTime: Duration.zero,
        toolTime: Duration.zero,
        avgTtft: null,
        tokensPerSecond: 0,
        cacheHitRate: null,
        promptTokens: 0,
        completionTokens: 0,
      ),
      messages: [
        ChatMessage(
          role: MessageRole.user,
          parts: const [MessagePart.text('分析结果')],
        ),
        ChatMessage(
          role: MessageRole.tool,
          toolCallId: 'large-result',
          parts: [MessagePart.text('x' * 4000)],
        ),
      ],
      onCompress: (_) => applied = true,
      liveContextTokens: 1200,
      contextLimit: 1000,
      contextSnapshot: snapshot,
    )));

    expect(find.text('建议压缩工具结果'), findsOneWidget);
    expect(find.textContaining('预计释放'), findsOneWidget);
    expect(find.text('仅提供建议，不会自动修改会话内容'), findsOneWidget);
    await tester.tap(find.text('应用建议'));
    expect(applied, isTrue);
  });

  testWidgets(
      'context bar separates output reservation from remaining capacity',
      (tester) async {
    Widget sheet({required int reservedOutputTokens}) {
      final snapshot = ContextSnapshot(
        contextWindow: 32000,
        reservedOutputTokens: reservedOutputTokens,
        usedTokens: 20000,
        updatedAt: DateTime(2026),
        parts: const [
          ContextPart(type: ContextPartType.toolResult, tokens: 20000),
        ],
      );
      return SessionMetricsSheet(
        metrics: const SessionMetrics(
          rounds: 1,
          steps: 1,
          llmTime: Duration.zero,
          toolTime: Duration.zero,
          avgTtft: null,
          tokensPerSecond: 0,
          cacheHitRate: null,
          promptTokens: 0,
          completionTokens: 0,
        ),
        liveContextTokens: 20000,
        contextLimit: 32000,
        contextSnapshot: snapshot,
      );
    }

    await tester.pumpWidget(wrap(sheet(reservedOutputTokens: 2048)));

    await tester.tap(find.byKey(const ValueKey('metrics-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('69%'), findsOneWidget);
    expect(find.text('/ 输入上限 30.0k tok'), findsOneWidget);
    expect(find.text('含输出预留 ≈2.0k tok'), findsOneWidget);
    expect(find.text('输出预留'), findsOneWidget);
    expect(find.text('≈2.0k'), findsOneWidget);
    expect(find.byKey(const ValueKey('context-output-reserved-segment')),
        findsOneWidget);

    await tester.pumpWidget(wrap(sheet(reservedOutputTokens: 0)));
    await tester.pump();

    expect(find.text('63%'), findsOneWidget);
    expect(find.text('/ 输入上限 32.0k tok'), findsOneWidget);
    expect(find.textContaining('含输出预留'), findsNothing);
    expect(find.text('输出预留'), findsNothing);
    expect(find.byKey(const ValueKey('context-output-reserved-segment')),
        findsNothing);
  });
}
