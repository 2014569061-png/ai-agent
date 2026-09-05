import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/domain/models.dart';

ChatMessage _user(String text) => ChatMessage(
    role: MessageRole.user, parts: [MessagePart.text(text)]);

ChatMessage _assistant(String text, {List<ToolCall> calls = const []}) =>
    ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(text)],
        toolCalls: calls);

ChatMessage _tool(String callId, String text) => ChatMessage(
    role: MessageRole.tool,
    toolCallId: callId,
    parts: [MessagePart.text(text)]);

void main() {
  test('keeps messages unchanged within budget', () {
    final window = ContextWindow(maxTokens: 1000);
    final messages = [_user('第一条'), _assistant('回复'), _user('第二条')];
    final applied = window.apply(messages);
    expect(applied.map((m) => m.text), messages.map((m) => m.text));
  });

  test('trims old turns and cuts at a user message boundary', () {
    // 各消息估算约 [7,7,7,9,5,7]，预算 30：从最新向前累加到 28 后
    // '回复一' 放不下，截断点恰好落在 '第二问'。
    final window = ContextWindow(maxTokens: 30);
    final messages = [
      _user('第一问'),
      _assistant('回复一'),
      _user('第二问'),
      _assistant('调用工具',
          calls: [ToolCall(id: 't1', name: 'calc', arguments: const {})]),
      _tool('t1', '42'),
      _user('第三问'),
    ];
    final applied = window.apply(messages);
    expect(applied.first.role, MessageRole.user);
    expect(applied.first.text, '第二问');
    expect(applied.last.text, '第三问');
  });

  test('never leaves a dangling tool result or unanswered tool call', () {
    // 各消息估算约 [6,9,6,6]，预算 20：朴素累加会停在 tool 结果上，
    // 裁剪必须推进到下一条 user 消息，保证调用与结果成组。
    final window = ContextWindow(maxTokens: 20);
    final messages = [
      _user('问一'),
      _assistant('执行工具',
          calls: [ToolCall(id: 't1', name: 'calc', arguments: const {})]),
      _tool('t1', '结果'),
      _user('问二'),
    ];
    final applied = window.apply(messages);
    expect(applied.first.role, MessageRole.user);
    for (var i = 0; i < applied.length; i++) {
      final message = applied[i];
      if (message.role == MessageRole.assistant &&
          message.toolCalls.isNotEmpty) {
        for (final call in message.toolCalls) {
          expect(
            applied
                .where((m) =>
                    m.role == MessageRole.tool && m.toolCallId == call.id)
                .length,
            1,
            reason: 'tool call ${call.id} 的结果必须与调用同组保留',
          );
        }
      }
      if (message.role == MessageRole.tool) {
        expect(
          applied.any((m) =>
              m.role == MessageRole.assistant &&
              m.toolCalls.any((call) => call.id == message.toolCallId)),
          isTrue,
          reason: 'tool 结果 ${message.toolCallId} 不能脱离其调用单独出现',
        );
      }
    }
  });

  test('always keeps the last user message even if it alone exceeds budget',
      () {
    final window = ContextWindow(maxTokens: 10);
    final big = '长' * 100;
    final messages = [_user(big)];
    final applied = window.apply(messages);
    expect(applied, hasLength(1));
    expect(applied.single.text, big);
  });

  test('caps oversized tool results in place', () {
    final window = ContextWindow(maxToolResultChars: 100);
    final messages = [
      _user('问'),
      _assistant('调用',
          calls: [ToolCall(id: 't1', name: 'http', arguments: const {})]),
      _tool('t1', 'x' * 1000),
    ];
    final applied = window.apply(messages);
    final toolMessage = applied.last;
    expect(toolMessage.role, MessageRole.tool);
    expect(toolMessage.text.length, lessThan(1000));
    expect(toolMessage.text, contains('[工具结果过长，已截断]'));
    expect(toolMessage.toolCallId, 't1');
  });

  test('estimateTokens treats CJK as ~1 token per char and ASCII as ~4 chars',
      () {
    expect(ContextWindow.estimateTokens(_user('abcd')), 5);
    expect(ContextWindow.estimateTokens(_user('中' * 10)), 14);
    final cjkMessage = _user('中' * 100);
    final asciiMessage = _user('a' * 100);
    expect(
      ContextWindow.estimateTokens(cjkMessage),
      greaterThan(ContextWindow.estimateTokens(asciiMessage)),
    );
  });
}
