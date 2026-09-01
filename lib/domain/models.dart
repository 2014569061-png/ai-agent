enum MessageRole { system, user, assistant, tool }

enum RunStatus {
  created,
  sendingRequest,
  waitingModel,
  approvalRequired,
  executingTool,
  completed,
  failed,
  cancelled,
}

enum ToolRisk { safe, requiresConfirmation, dangerous }

class MessagePart {
  const MessagePart.text(this.value) : type = 'text', mimeType = null;
  const MessagePart.file(this.value, {this.mimeType}) : type = 'file';
  const MessagePart.image(this.value, {this.mimeType}) : type = 'image';

  final String type;
  final String value;
  final String? mimeType;
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.parts,
    this.toolCallId,
    this.toolCalls = const [],
    this.modelName,
    this.usage,
    this.elapsed,
  });

  final MessageRole role;
  final List<MessagePart> parts;
  final String? toolCallId;
  final List<ToolCall> toolCalls;
  final String? modelName;
  final Usage? usage;
  final Duration? elapsed;

  /// 纯文本视图：图片/文件附件以占位符呈现，避免把 base64 data URI
  /// 当作文本拼进 UI、导出或复制内容（历史 bug：导入图片显示一长串乱码）。
  String get text => parts.map((part) {
        if (part.type == 'image') return '[图片]';
        if (part.type == 'file') return '[文件]';
        return part.value;
      }).join();
}

/// 一次请求的 Token 用量统计。
class Usage {
  const Usage({this.promptTokens = 0, this.completionTokens = 0});

  final int promptTokens;
  final int completionTokens;

  int get totalTokens => promptTokens + completionTokens;
}

class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class UnifiedTool {
  const UnifiedTool({
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.risk,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final ToolRisk risk;

  Map<String, dynamic> toOpenAiSchema() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parametersSchema,
        },
      };
}

class UnifiedRequest {
  const UnifiedRequest({
    required this.model,
    required this.messages,
    this.tools = const [],
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.topP = 1.0,
  });

  final String model;
  final List<ChatMessage> messages;
  final List<UnifiedTool> tools;
  final double temperature;
  final int maxTokens;
  final double topP;
}

sealed class UnifiedEvent {
  const UnifiedEvent();
}

class TextDeltaEvent extends UnifiedEvent {
  const TextDeltaEvent(this.text);
  final String text;
}

class ToolCallEvent extends UnifiedEvent {
  const ToolCallEvent(this.call);
  final ToolCall call;
}

class CompletedEvent extends UnifiedEvent {
  const CompletedEvent();
}

class UsageEvent extends UnifiedEvent {
  const UsageEvent({required this.promptTokens, required this.completionTokens});
  final int promptTokens;
  final int completionTokens;
}

class ProviderErrorEvent extends UnifiedEvent {
  const ProviderErrorEvent(this.message);
  final String message;
}
