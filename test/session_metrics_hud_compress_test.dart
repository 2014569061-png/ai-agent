import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/context_insights.dart';
import 'package:mobile_agent/domain/session_metrics.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_bar.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// C3：预算达到 warning 及以上时，指标条直接给出「压缩上下文」快捷入口。
///
/// 覆盖点：
/// * warning / critical 出现，normal 不出现；
/// * 没有快照或没有回调时不出现（避免出现永远点不动的操作）；
/// * 点击真的回调到调用方（而不是被外层「打开指标面板」的 InkWell 抢走）；
/// * 360x800 + textScale 1.3 下不溢出——这是入口出现时的主要布局风险。
void main() {
  const metrics = SessionMetrics(
    rounds: 3,
    steps: 4,
    llmTime: Duration(seconds: 12),
    toolTime: Duration(seconds: 3),
    avgTtft: Duration(seconds: 1),
    tokensPerSecond: 42,
    cacheHitRate: .3,
    promptTokens: 26000,
    completionTokens: 1000,
  );

  const window = 32000;
  const reserved = 2048;

  ContextSnapshot snapshot(int usedTokens) => ContextSnapshot(
        parts: [ContextPart(type: ContextPartType.user, tokens: usedTokens)],
        usedTokens: usedTokens,
        contextWindow: window,
        reservedOutputTokens: reserved,
        updatedAt: DateTime(2026),
      );

  Future<void> pumpBar(
    WidgetTester tester, {
    required ContextSnapshot? contextSnapshot,
    required VoidCallback? onCompress,
    double textScale = 1.0,
  }) async {
    const size = Size(360, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: size)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SessionMetricsBar(
            metrics: metrics,
            onTap: () {},
            onCompress: onCompress,
            contextSnapshot: contextSnapshot,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('预算达到 warning 时出现快捷压缩入口并可点击', (tester) async {
    // (26000 + 2048) / 32000 ≈ 87.7% → warning
    var pressed = 0;
    await pumpBar(
      tester,
      contextSnapshot: snapshot(26000),
      onCompress: () => pressed++,
    );

    expect(find.text('压缩上下文'), findsOneWidget);
    await tester.tap(find.text('压缩上下文'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('预算进入 critical 时入口仍然可用', (tester) async {
    // (29000 + 2048) / 32000 ≈ 97.0% → critical
    var pressed = 0;
    await pumpBar(
      tester,
      contextSnapshot: snapshot(29000),
      onCompress: () => pressed++,
    );

    expect(find.text('压缩上下文'), findsOneWidget);
    await tester.tap(find.text('压缩上下文'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('预算正常时不出现快捷压缩入口', (tester) async {
    await pumpBar(
      tester,
      contextSnapshot: snapshot(10000),
      onCompress: () {},
    );

    expect(find.text('压缩上下文'), findsNothing);
  });

  testWidgets('没有回调时不出现快捷压缩入口', (tester) async {
    await pumpBar(
      tester,
      contextSnapshot: snapshot(29000),
      onCompress: null,
    );

    expect(find.text('压缩上下文'), findsNothing);
  });

  testWidgets('没有上下文快照时不出现快捷压缩入口', (tester) async {
    await pumpBar(
      tester,
      contextSnapshot: null,
      onCompress: () {},
    );

    expect(find.text('压缩上下文'), findsNothing);
  });

  testWidgets('360x800 大字模式下入口与预算条不溢出', (tester) async {
    var pressed = 0;
    await pumpBar(
      tester,
      contextSnapshot: snapshot(29000),
      onCompress: () => pressed++,
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('压缩上下文'), findsOneWidget);
    await tester.tap(find.text('压缩上下文'));
    await tester.pump();
    expect(pressed, 1);
    expect(tester.takeException(), isNull);
  });
}
