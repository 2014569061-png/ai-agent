import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/reasoning_block.dart';
import 'package:mobile_agent/presentation/markdown/math_block.dart';

void main() {
  testWidgets('does not build markdown until reasoning is expanded',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReasoningCompactBlock(reasoning: '**reasoning**'),
      ),
    ));

    expect(find.byType(MathMarkdown), findsNothing);
    await tester.tap(find.text('已思考'));
    await tester.pumpAndSettle();
    expect(find.byType(MathMarkdown), findsOneWidget);
  });

  testWidgets('uses plain selectable text while streaming', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReasoningCompactBlock(
          reasoning: '**reasoning**',
          streaming: true,
        ),
      ),
    ));

    await tester.tap(find.text('正在思考…'));
    await tester.pumpAndSettle();
    expect(find.byType(MathMarkdown), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('shows real progress, elapsed time and a stop action',
      (tester) async {
    var stopped = false;
    final started = DateTime.now();
    final progress = ChatRunProgress(
      stage: ChatRunStage.waitingModel,
      label: '正在等待模型响应',
      startedAt: started,
      lastActivityAt: started,
      completedTools: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReasoningCompactBlock(
            reasoning: '',
            streaming: true,
            progress: progress,
            onStop: () => stopped = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('进度'), findsOneWidget);
    expect(find.text('正在等待模型响应'), findsNWidgets(2));
    expect(find.text('已完成 2 项工具调用'), findsOneWidget);
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.text('00:02'), findsOneWidget);

    await tester.tap(find.byTooltip('停止生成'));
    expect(stopped, isTrue);
  });

  testWidgets('shows a slow-response message after eight idle seconds',
      (tester) async {
    final started = DateTime.now();
    final progress = ChatRunProgress(
      stage: ChatRunStage.waitingModel,
      label: '正在等待模型响应',
      startedAt: started,
      lastActivityAt: started,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReasoningCompactBlock(
            reasoning: '',
            streaming: true,
            progress: progress,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 8));

    expect(find.text('响应较慢，仍在继续…'), findsOneWidget);
    expect(find.textContaining('处理时间较长，仍在继续'), findsOneWidget);
  });

  testWidgets('condenses the progress timeline after answer text starts',
      (tester) async {
    final started = DateTime.now();
    final progress = ChatRunProgress(
      stage: ChatRunStage.generating,
      label: '正在生成回答',
      startedAt: started,
      lastActivityAt: started,
      generatedCharacters: 42,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReasoningCompactBlock(
            reasoning: '已收到实际推理内容',
            streaming: true,
            hasStartedAnswer: true,
            progress: progress,
          ),
        ),
      ),
    );

    expect(find.text('已收到请求'), findsNothing);
    expect(find.text('已生成 42 字'), findsNothing);
    expect(find.byTooltip('展开思考过程'), findsOneWidget);
  });

  testWidgets('does not call waiting slow when waiting for user',
      (tester) async {
    final started = DateTime.now();
    final progress = ChatRunProgress(
      stage: ChatRunStage.waitingForUser,
      label: '等待你的确认：delete_file',
      startedAt: started,
      lastActivityAt: started,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReasoningCompactBlock(
            reasoning: '',
            streaming: true,
            progress: progress,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('等待你的确认：delete_file'), findsNWidgets(2));
    expect(find.text('响应较慢，仍在继续…'), findsNothing);
  });
}
