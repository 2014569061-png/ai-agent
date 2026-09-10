import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/domain/models.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]);

ChatMessage _assistant(String text, {List<ToolCall> calls = const []}) =>
    ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(text)],
        toolCalls: calls);

ChatMessage _assistantWithImage(String payload) => ChatMessage(
    role: MessageRole.assistant,
    parts: [MessagePart.image('data:image/png;base64,$payload')]);

ChatMessage _tool(String callId, String text) => ChatMessage(
    role: MessageRole.tool,
    toolCallId: callId,
    parts: [MessagePart.text(text)]);

/// 把短文本放大到真实会话量级。压缩告示本身约 50 token，夹具若只有几十字符，
/// 告示成本会盖过整段对话，裁剪逻辑根本不会被触发。
String _repeat(String text) => text * 20;

/// 裁剪后保留的对话历史（排除 system 消息：调用方自带的设定 + 插入的告示）。
List<ChatMessage> _retained(List<ChatMessage> applied) => applied
    .where((message) => message.role != MessageRole.system)
    .toList(growable: false);

/// 压缩告示自身占用的 token。裁剪时可用预算 = maxTokens - 告示成本，
/// 所以用例按“可用预算”反推 maxTokens，避免告示文案一改测试就失效。
int _noticeTokens() => ContextWindow.estimateTokens(ChatMessage(
    role: MessageRole.system,
    parts: const [MessagePart.text(ContextWindow.compactionNotice)]));

/// 构造一个“可用预算恰好为 [available]”的窗口。
ContextWindow _windowWithBudget(int available, {int? maxToolResultChars}) =>
    ContextWindow(
      maxTokens: _noticeTokens() + available,
      maxToolResultChars: maxToolResultChars ?? 16000,
    );

void main() {
  test('keeps messages unchanged within budget', () {
    final window = ContextWindow(maxTokens: 1000);
    final messages = [_user('第一条'), _assistant('回复'), _user('第二条')];
    final applied = window.apply(messages);
    expect(applied.map((m) => m.text), messages.map((m) => m.text));
  });

  test('trims old turns and cuts at a user message boundary', () {
    // 各消息估算约 [64,64,64,88,14,64]（总 358）。可用预算 250：从最新向前
    // 累加 64+14+88+64=230 后，'回复一' 的 64 放不下（294>250），
    // 截断点恰好落在 '第二问'。
    final window = _windowWithBudget(250);
    final messages = [
      _user(_repeat('第一问')),
      _assistant(_repeat('回复一')),
      _user(_repeat('第二问')),
      _assistant(_repeat('调用工具'),
          calls: [ToolCall(id: 't1', name: 'calc', arguments: const {})]),
      _tool('t1', _repeat('42')),
      _user(_repeat('第三问')),
    ];
    final applied = window.apply(messages);
    final retained = _retained(applied);
    expect(retained.first.role, MessageRole.user);
    expect(retained.first.text, _repeat('第二问'));
    expect(retained.last.text, _repeat('第三问'));
    // 工具调用与其结果必须同组保留。
    expect(retained.any((m) => m.role == MessageRole.tool), isTrue);
  });

  test('never leaves a dangling tool result or unanswered tool call', () {
    // 各消息估算约 [44,88,44,44]（总 220）。可用预算 100：朴素累加会停在
    // tool 结果上（44+44=88≤100），裁剪必须推进到下一条 user 消息。
    final window = _windowWithBudget(100);
    final messages = [
      _user(_repeat('问一')),
      _assistant(_repeat('执行工具'),
          calls: [ToolCall(id: 't1', name: 'calc', arguments: const {})]),
      _tool('t1', _repeat('结果')),
      _user(_repeat('问二')),
    ];
    final applied = window.apply(messages);
    final retained = _retained(applied);
    expect(retained.first.role, MessageRole.user);
    for (var i = 0; i < retained.length; i++) {
      final message = retained[i];
      if (message.role == MessageRole.assistant &&
          message.toolCalls.isNotEmpty) {
        for (final call in message.toolCalls) {
          expect(
            retained
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
          retained.any((m) =>
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

  group('compaction notice', () {
    test('is inserted before retained history when trimming happens', () {
      // 三条消息各约 64 token（总 192）；可用预算 70 只装得下最后一条。
      final window = _windowWithBudget(70);
      final applied = window.apply([
        _user(_repeat('第一问')),
        _assistant(_repeat('回复一')),
        _user(_repeat('第二问')),
      ]);
      expect(applied.first.role, MessageRole.system);
      expect(applied.first.text, ContextWindow.compactionNotice);
      expect(applied.first.text, contains('请勿假定其中步骤未执行'));
      expect(_retained(applied).map((m) => m.text), [_repeat('第二问')]);
    });

    test('is omitted when nothing is trimmed', () {
      final window = ContextWindow(maxTokens: 1000);
      final applied = window.apply([_user('第一问'), _user('第二问')]);
      expect(
        applied.any((m) => m.text == ContextWindow.compactionNotice),
        isFalse,
      );
    });

    test('keeps caller-supplied system messages ahead of the notice', () {
      final window = _windowWithBudget(70);
      final applied = window.apply([
        ChatMessage(
            role: MessageRole.system, parts: [MessagePart.text('身份设定')]),
        _user(_repeat('第一问')),
        _assistant(_repeat('回复一')),
        _user(_repeat('第二问')),
      ]);
      expect(applied[0].text, '身份设定');
      expect(applied[1].text, ContextWindow.compactionNotice);
      expect(_retained(applied).map((m) => m.text), [_repeat('第二问')]);
    });
  });

  group('binary attachment budgeting', () {
    test('image parts are no longer estimated as ~0 tokens', () {
      final small = ContextWindow.estimateTokens(_assistantWithImage('A' * 40));
      final large =
          ContextWindow.estimateTokens(_assistantWithImage('A' * 1000000));
      expect(small, greaterThanOrEqualTo(ContextWindow.minBinaryPartTokens));
      expect(large, greaterThan(small));
    });

    test('an oversized image forces trimming instead of passing unnoticed', () {
      // 1_000_000 字符 base64 ≈ 750KB ≈ 1000 token 估算。旧实现把图片渲染成
      // '[图片]' 只算 4 token，这一轮根本不会触发裁剪，请求会被服务商 400。
      final window = _windowWithBudget(100);
      final applied = window.apply([
        _user('问'),
        _assistantWithImage('A' * 1000000),
        _user('最新'),
      ]);
      expect(_retained(applied).map((m) => m.text), ['最新']);
      expect(applied.first.text, ContextWindow.compactionNotice);
    });
  });

  group('tool call gates', () {
    test('oversized arguments are replaced by a parseable placeholder', () {
      final window = ContextWindow(maxToolArgumentChars: 50);
      final applied = window.apply([
        _user('问'),
        _assistant('调用', calls: [
          ToolCall(
              id: 't1', name: 'write_file', arguments: {'body': 'x' * 500}),
        ]),
      ]);
      final call = applied.last.toolCalls.single;
      expect(call.id, 't1');
      expect(call.arguments[ContextWindow.truncatedArgumentMark], isTrue);
      expect(call.arguments['originalChars'], greaterThan(50));
      expect(call.arguments.containsKey('body'), isFalse);
    });

    test('arguments within the cap are left untouched', () {
      final window = ContextWindow(maxToolArgumentChars: 5000);
      final applied = window.apply([
        _user('问'),
        _assistant('调用', calls: [
          ToolCall(id: 't1', name: 'calc', arguments: const {'a': 1}),
        ]),
      ]);
      expect(applied.last.toolCalls.single.arguments, {'a': 1});
    });

    test('tool_calls over the per-message cap drop their orphan results', () {
      final window = ContextWindow(maxToolCallsPerMessage: 2);
      final applied = window.apply([
        _user('问'),
        _assistant('批量调用', calls: [
          ToolCall(id: 't1', name: 'calc', arguments: const {}),
          ToolCall(id: 't2', name: 'calc', arguments: const {}),
          ToolCall(id: 't3', name: 'calc', arguments: const {}),
        ]),
        _tool('t1', '1'),
        _tool('t2', '2'),
        _tool('t3', '3'),
        _user('继续'),
      ]);
      final assistant = applied.firstWhere((m) => m.toolCalls.isNotEmpty);
      expect(assistant.toolCalls.map((c) => c.id), ['t1', 't2']);
      final toolIds = applied
          .where((m) => m.role == MessageRole.tool)
          .map((m) => m.toolCallId)
          .toList();
      expect(toolIds, ['t1', 't2'], reason: 't3 的结果必须随调用一起被裁掉');
    });
  });

  test('tolerates history without any user message', () {
    // 回归：旧实现在这种输入下会把 cut 推到 -1 并触发 RangeError。
    final window = ContextWindow(maxTokens: 5);
    expect(
      () => window.apply([_assistant('回复一'), _assistant('回复二')]),
      returnsNormally,
    );
  });

  test('never mutates the caller-supplied list', () {
    final window = _windowWithBudget(70);
    final messages = [
      _user(_repeat('第一问')),
      _assistant(_repeat('回复一')),
      _user(_repeat('第二问')),
    ];
    final before = messages.map((m) => m.text).toList();
    final applied = window.apply(messages);
    expect(applied, isNot(same(messages)));
    expect(messages.map((m) => m.text), before);
    expect(messages, hasLength(3), reason: '不得在原列表上插入告示');
  });
}
