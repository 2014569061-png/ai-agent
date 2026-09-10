import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/run_controller.dart';
import 'package:mobile_agent/application/run_coordinator.dart';
import 'package:mobile_agent/domain/models.dart';

/// `RunCoordinator` 的独立单元测试：它决定"一次运行还能不能写回状态"，
/// 是并发安全的核心，因此不依赖 ChatController 也能单独验证。
void main() {
  RunCoordinator build([String? Function()? conversation]) => RunCoordinator(
      currentConversationId: conversation ?? () => 'c1');

  test('beginRun 自增代次并解除该代次的取消标记', () {
    final runs = build();
    final first = runs.beginRun();
    runs.invalidateActiveRun();
    expect(runs.wasCancelled(first), isTrue);

    final second = runs.beginRun();
    expect(second, greaterThan(first));
    expect(runs.wasCancelled(second), isFalse);
    expect(runs.generation, second);
  });

  test('ownsRun 同时要求代次有效、未取消、会话未切走', () {
    var conversationId = 'c1';
    final runs = build(() => conversationId);
    final generation = runs.beginRun();
    expect(runs.ownsRun(generation, 'c1'), isTrue);

    // 会话被切走 → 旧代次失去写回权。
    conversationId = 'c2';
    expect(runs.ownsRun(generation, 'c1'), isFalse);

    // 新的代次在正确的会话里恢复写回权。
    final next = runs.beginRun();
    expect(runs.ownsRun(next, 'c2'), isTrue);
    // 旧代次即使会话对得上也已过期。
    expect(runs.ownsRun(generation, 'c2'), isFalse);
  });

  test('cancel 标记单独就能让 running 失权（无需切会话）', () {
    final runs = build();
    final generation = runs.beginRun();
    runs.invalidateActiveRun();
    expect(runs.ownsRun(generation, 'c1'), isFalse);
    expect(runs.ownsRunUnbound(generation, null), isFalse);
  });

  test('ownsRunUnbound 在会话为空时跳过归属校验', () {
    var conversationId = 'c1';
    final runs = build(() => conversationId);
    final generation = runs.beginRun();
    expect(runs.ownsRunUnbound(generation, null), isTrue);

    conversationId = 'c2';
    expect(runs.ownsRunUnbound(generation, 'c1'), isFalse);
    expect(runs.ownsRunUnbound(generation, 'c2'), isTrue);
  });

  test('invalidateActiveRun 取消三个取消源、清空预算断点并作废旧代次', () {
    final runs = build();
    final generation = runs.beginRun();
    final token = AgentCancellationToken();
    final dioToken = CancelToken();
    final controller = AgentRunController();
    runs.cancellationToken = token;
    runs.dioCancelToken = dioToken;
    runs.runController = controller;
    runs.budgetPauseContext = [
      ChatMessage(role: MessageRole.user, parts: [MessagePart.text('预算暂停上下文')])
    ];

    runs.invalidateActiveRun();

    expect(token.isCancelled, isTrue);
    expect(dioToken.isCancelled, isTrue);
    expect(controller.isCancelled, isTrue);
    expect(runs.budgetPauseContext, isNull);
    expect(runs.generation, isNot(generation));
    expect(runs.wasCancelled(generation), isTrue);
  });

  test('clearXxxIf 只清空同一实例，避免误清新一轮的令牌', () {
    final runs = build();
    final stale = AgentCancellationToken();
    final current = AgentCancellationToken();
    runs.cancellationToken = current;
    runs.clearCancellationTokenIf(stale);
    expect(runs.cancellationToken, same(current));
    runs.clearCancellationTokenIf(current);
    expect(runs.cancellationToken, isNull);

    final staleDio = CancelToken();
    final currentDio = CancelToken();
    runs.dioCancelToken = currentDio;
    runs.clearDioCancelTokenIf(staleDio);
    expect(runs.dioCancelToken, same(currentDio));
    runs.clearDioCancelTokenIf(currentDio);
    expect(runs.dioCancelToken, isNull);

    final staleRun = AgentRunController();
    final currentRun = AgentRunController();
    runs.runController = currentRun;
    runs.clearRunControllerIf(staleRun);
    expect(runs.runController, same(currentRun));
    runs.clearRunControllerIf(currentRun);
    expect(runs.runController, isNull);
  });

  test('forget 收尾后不再把该代次当作已取消', () {
    final runs = build();
    final generation = runs.beginRun();
    runs.invalidateActiveRun();
    expect(runs.wasCancelled(generation), isTrue);
    runs.forget(generation);
    expect(runs.wasCancelled(generation), isFalse);
  });
}
