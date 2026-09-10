import 'dart:convert';

import '../domain/models.dart';

/// 上下文窗口预算：估算消息 token 占用并裁剪较早历史，防止超出模型上下文。
///
/// 裁剪规则：
/// - system 消息始终保留（数量少、体积小，由调用方注入）；
/// - 从最新消息向前累加预算，超出的更早历史被丢弃；
/// - 一旦真的丢弃了历史，就在保留部分之前插入一条压缩告示，避免模型把
///   “记录缺失”误读成“那一步没执行过”从而重做已完成的工作；
/// - 截断点只允许落在 user 消息上：assistant(tool_calls) 与其 tool 结果
///   必须成组保留，否则 OpenAI / Anthropic / Gemini 都会拒绝请求；
/// - 最后一条 user 消息无论如何都保留（它是当前这轮的提问）；
/// - 单条 tool 结果、单个 tool_call 参数、单条消息的 tool_calls 数量各有上限，
///   超限的 tool_calls 被裁掉时会同步删除其孤儿 tool 结果，保持配对完整。
class ContextWindow {
  ContextWindow({
    int? maxTokens,
    this.maxToolResultChars = defaultMaxToolResultChars,
    this.maxToolArgumentChars = defaultMaxToolArgumentChars,
    this.maxToolCallsPerMessage = defaultMaxToolCallsPerMessage,
  }) : maxTokens = maxTokens ?? defaultMaxTokens;

  /// 默认预算。模型上下文差异很大，这里取当前主流模型的保守下界，
  /// 可通过 ProviderConfig.contextTokens 按配置覆盖。
  static const defaultMaxTokens = 32000;

  /// 单条 tool 结果回灌上限。
  static const defaultMaxToolResultChars = 16000;

  /// 单个 tool_call 参数上限。模型幻觉出超长 arguments 时不能原样发给
  /// 服务商，否则一次调用就能吃掉整个预算。
  static const defaultMaxToolArgumentChars = 32000;

  /// 单条 assistant 消息允许的 tool_calls 上限。
  static const defaultMaxToolCallsPerMessage = 64;

  /// 二进制附件（图片/音频/视频/文件）token 估算下限：再小的附件也不能
  /// 估成 0，否则预算形同虚设。
  static const minBinaryPartTokens = 256;

  /// 二进制附件按“每 N 字节 1 token”折算。视觉模型实际按分辨率计费，
  /// 这里只需要一个保守的量级代理值用于预算裁剪，不追求精确。
  static const binaryBytesPerToken = 750;

  /// 头部历史被丢弃时插入的告示。
  static const compactionNotice = '[上下文提示：更早的 assistant/tool 记录因容量上限'
      '已被压缩，请勿假定其中步骤未执行；需要确认时重新读取文件或重跑检查。]';

  /// 单条 tool 结果被截断时追加的标记。
  static const toolResultTruncatedMark = '…[工具结果过长，已截断]';

  /// 单个 tool_call 参数被截断后的替身，保持 JSON 可解析。
  static const truncatedArgumentMark = '_truncated';

  final int maxTokens;
  final int maxToolResultChars;
  final int maxToolArgumentChars;
  final int maxToolCallsPerMessage;

  /// 返回适配预算后的消息列表；不会修改入参。
  List<ChatMessage> apply(List<ChatMessage> messages) {
    if (messages.isEmpty) return messages;
    final system = messages
        .where((message) => message.role == MessageRole.system)
        .toList(growable: false);
    final rest = messages
        .where((message) => message.role != MessageRole.system)
        .toList(growable: false);
    final capped = _capMessages(rest);
    final estimates = capped.map(estimateTokens).toList(growable: false);
    final total = estimates.fold<int>(0, (sum, item) => sum + item);
    if (total <= maxTokens) {
      return [...system, ...capped];
    }

    // 确定要裁剪：先给告示留出预算，免得告示本身把上下文重新顶超。
    final budget =
        (maxTokens - estimateTokens(_noticeMessage())).clamp(0, maxTokens);

    // 从最新向前保留预算内的消息。
    var used = 0;
    var cut = capped.length;
    for (var i = capped.length - 1; i >= 0; i--) {
      if (used + estimates[i] > budget) break;
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
    if (lastUser >= 0 && cut > lastUser) cut = lastUser;
    // 截断点落到 user 消息上，保证 assistant(tool_calls)+tool 结果成组保留。
    while (cut < capped.length && capped[cut].role != MessageRole.user) {
      cut++;
    }
    // 历史里没有任何 user 消息时 cut 会停在 0，此时不裁剪也不插告示。
    if (cut <= 0) {
      return [...system, ...capped];
    }
    return [...system, _noticeMessage(), ...capped.sublist(cut)];
  }

  /// 单条消息 token 估算：文本按 CJK ~1 token/字、其余 ~4 字符/token 计；
  /// 二进制附件按字节折算并设下限；推理内容与工具调用参数单独计入。
  /// 用于预算裁剪，不追求精确。
  static int estimateTokens(ChatMessage message) {
    // 每条消息的固定开销（角色、分隔符等）。
    var tokens = 4;
    for (final part in message.parts) {
      tokens += switch (part.type) {
        'image' ||
        'file' ||
        'audio' ||
        'video' =>
          _estimateBinaryPartTokens(part.value),
        _ => _estimateTextTokens(part.value),
      };
    }
    final reasoning = message.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      tokens += _estimateTextTokens(reasoning);
    }
    for (final call in message.toolCalls) {
      tokens += (call.name.length / 4).ceil() + 2;
      tokens += (jsonEncode(call.arguments).length / 4).ceil();
    }
    return tokens;
  }

  static int _estimateTextTokens(String text) {
    var cjk = 0;
    for (final rune in text.runes) {
      if (rune >= 0x2E80) cjk++;
    }
    final other = text.length - cjk;
    return cjk + (other / 4).ceil();
  }

  /// data URL 形如 `data:image/png;base64,<payload>`，只按 payload 估字节。
  static int _estimateBinaryPartTokens(String value) {
    final comma = value.indexOf(',');
    final payload = comma >= 0 ? value.substring(comma + 1) : value;
    final bytes = (payload.length * 3) ~/ 4;
    final tokens = (bytes / binaryBytesPerToken).ceil();
    return tokens < minBinaryPartTokens ? minBinaryPartTokens : tokens;
  }

  static ChatMessage _noticeMessage() => ChatMessage(
        role: MessageRole.system,
        parts: const [MessagePart.text(compactionNotice)],
      );

  List<ChatMessage> _capMessages(List<ChatMessage> messages) {
    var capped = messages.map(_capToolResult).toList(growable: false);
    capped = _capToolArguments(capped);
    return _capToolCallCount(capped);
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
            '${text.substring(0, maxToolResultChars)}\n$toolResultTruncatedMark')
      ],
    );
  }

  /// 超长参数替换为可解析的替身对象，保留原始长度供排查。
  List<ChatMessage> _capToolArguments(List<ChatMessage> messages) {
    if (!messages.any((message) => message.toolCalls.isNotEmpty)) {
      return messages;
    }
    return messages.map((message) {
      if (message.toolCalls.isEmpty) return message;
      var changed = false;
      final calls = message.toolCalls.map((call) {
        final encoded = jsonEncode(call.arguments);
        if (encoded.length <= maxToolArgumentChars) return call;
        changed = true;
        return ToolCall(
          id: call.id,
          name: call.name,
          arguments: {
            truncatedArgumentMark: true,
            'originalChars': encoded.length,
          },
        );
      }).toList(growable: false);
      return changed ? message.copyWith(toolCalls: calls) : message;
    }).toList(growable: false);
  }

  /// 超出数量上限的 tool_calls 被裁掉时，必须同步删除对应的孤儿 tool 结果，
  /// 否则“有结果无调用”会被 Provider 直接拒绝。
  List<ChatMessage> _capToolCallCount(List<ChatMessage> messages) {
    if (!messages
        .any((message) => message.toolCalls.length > maxToolCallsPerMessage)) {
      return messages;
    }
    final droppedIds = <String>{};
    final trimmed = <ChatMessage>[];
    for (final message in messages) {
      if (message.toolCalls.length <= maxToolCallsPerMessage) {
        trimmed.add(message);
        continue;
      }
      for (final call in message.toolCalls.sublist(maxToolCallsPerMessage)) {
        droppedIds.add(call.id);
      }
      trimmed.add(message.copyWith(
        toolCalls: message.toolCalls.sublist(0, maxToolCallsPerMessage),
      ));
    }
    if (droppedIds.isEmpty) return trimmed;
    return trimmed
        .where((message) =>
            message.role != MessageRole.tool ||
            !droppedIds.contains(message.toolCallId))
        .toList(growable: false);
  }
}
