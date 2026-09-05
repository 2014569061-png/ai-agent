import 'dart:convert';

import '../domain/models.dart';

/// 上下文窗口预算：估算消息 token 占用并裁剪较早历史，防止超出模型上下文。
///
/// 裁剪规则：
/// - system 消息始终保留（数量少、体积小，由调用方注入）；
/// - 从最新消息向前累加预算，超出的更早历史被丢弃；
/// - 截断点只允许落在 user 消息上：assistant(tool_calls) 与其 tool 结果
///   必须成组保留，否则 OpenAI / Anthropic / Gemini 都会拒绝请求；
/// - 最后一条 user 消息无论如何都保留（它是当前这轮的提问）；
/// - 单条 tool 结果超长时先就地截断，避免一条结果吃掉整个预算。
class ContextWindow {
  ContextWindow({int? maxTokens, this.maxToolResultChars = 16000})
      : maxTokens = maxTokens ?? defaultMaxTokens;

  /// 默认预算。模型上下文差异很大，这里取当前主流模型的保守下界，
  /// 可通过 ProviderConfig.contextTokens 按配置覆盖。
  static const defaultMaxTokens = 32000;

  final int maxTokens;
  final int maxToolResultChars;

  /// 返回适配预算后的消息列表；不会修改入参。
  List<ChatMessage> apply(List<ChatMessage> messages) {
    if (messages.isEmpty) return messages;
    final system = messages
        .where((message) => message.role == MessageRole.system)
        .toList(growable: false);
    final rest =
        messages.where((message) => message.role != MessageRole.system).toList();
    final capped = rest.map(_capToolResult).toList(growable: false);
    final estimates = capped.map(estimateTokens).toList(growable: false);
    final total = estimates.fold<int>(0, (sum, item) => sum + item);
    if (total <= maxTokens) {
      return [...system, ...capped];
    }

    // 从最新向前保留预算内的消息。
    var used = 0;
    var cut = capped.length;
    for (var i = capped.length - 1; i >= 0; i--) {
      if (used + estimates[i] > maxTokens) break;
      used += estimates[i];
      cut = i;
    }
    // 最后一条 user 消息是当前提问，必须保留。
    var lastUser = -1;
    for (var i = capped.length - 1; i >= 0; i--) {
      if (capped[i].role == MessageRole.user) {
        lastUser = i;
        break;
      }
    }
    if (cut > lastUser) cut = lastUser;
    // 截断点落到 user 消息上，保证 assistant(tool_calls)+tool 结果成组保留。
    while (cut < capped.length && capped[cut].role != MessageRole.user) {
      cut++;
    }
    return [...system, ...capped.sublist(cut)];
  }

  /// 单条消息 token 估算：CJK 字符按 ~1 token/字，其余按 ~4 字符/token，
  /// 另加工具调用参数与每条消息的固定开销。用于预算裁剪，不追求精确。
  static int estimateTokens(ChatMessage message) {
    final text = message.text;
    var cjk = 0;
    for (final rune in text.runes) {
      if (rune >= 0x2E80) cjk++;
    }
    final other = text.length - cjk;
    var tokens = cjk + (other / 4).ceil() + 4;
    for (final call in message.toolCalls) {
      tokens += (jsonEncode(call.arguments).length / 4).ceil();
    }
    return tokens;
  }

  ChatMessage _capToolResult(ChatMessage message) {
    if (message.role != MessageRole.tool) return message;
    if (message.parts.length != 1 || message.parts.first.type != 'text') {
      return message;
    }
    final text = message.parts.first.value;
    if (text.length <= maxToolResultChars) return message;
    return ChatMessage(
      role: message.role,
      toolCallId: message.toolCallId,
      parts: [
        MessagePart.text(
            '${text.substring(0, maxToolResultChars)}\n…[工具结果过长，已截断]')
      ],
    );
  }
}
