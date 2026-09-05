enum MessageRole { system, user, assistant, tool }

enum ReasoningEffort { off, low, medium, high }

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

/// 工具审批决策：拒绝 / 仅本次 / 本会话内 / 始终允许（全局信任）。
enum ToolApproval { reject, allowOnce, allowSession, allowAlways }

class MessagePart {
  const MessagePart.text(this.value)
      : type = 'text',
        mimeType = null;
  const MessagePart.file(this.value, {this.mimeType}) : type = 'file';
  const MessagePart.image(this.value, {this.mimeType}) : type = 'image';
  const MessagePart.audio(this.value, {this.mimeType}) : type = 'audio';
  const MessagePart.video(this.value, {this.mimeType}) : type = 'video';

  final String type;
  final String value;
  final String? mimeType;
}

class PlanStep {
  const PlanStep(
      {required this.id, required this.description, this.status = 'pending'});
  final String id;
  final String description;
  final String status;

  PlanStep copyWith({String? description, String? status}) => PlanStep(
      id: id,
      description: description ?? this.description,
      status: status ?? this.status);
}

class PlanState {
  const PlanState({required this.steps, this.status = 'draft'});
  final List<PlanStep> steps;
  final String status;

  PlanState copyWith({List<PlanStep>? steps, String? status}) =>
      PlanState(steps: steps ?? this.steps, status: status ?? this.status);

  bool get isConfirmed => status != 'draft' && status != 'cancelled';
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
    this.ttft,
    this.reasoning,
  });

  final MessageRole role;
  final List<MessagePart> parts;
  final String? toolCallId;
  final List<ToolCall> toolCalls;
  final String? modelName;
  final Usage? usage;
  final Duration? elapsed;
  final Duration? ttft;
  final String? reasoning;

  String get text => parts.map((part) {
        if (part.type == 'image') return '[图片]';
        if (part.type == 'file') return '[文件]';
        if (part.type == 'audio') return '[音频]';
        if (part.type == 'video') return '[视频]';
        return part.value;
      }).join();
}

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
    this.reasoningEffort = ReasoningEffort.off,
  });

  final String model;
  final List<ChatMessage> messages;
  final List<UnifiedTool> tools;
  final double temperature;
  final int maxTokens;
  final double topP;
  final ReasoningEffort reasoningEffort;
}

sealed class UnifiedEvent {
  const UnifiedEvent();
}

class TextDeltaEvent extends UnifiedEvent {
  const TextDeltaEvent(this.text);
  final String text;
}

class ReasoningDeltaEvent extends UnifiedEvent {
  const ReasoningDeltaEvent(this.text);
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
  const UsageEvent(
      {required this.promptTokens, required this.completionTokens});
  final int promptTokens;
  final int completionTokens;
}

class ProviderErrorEvent extends UnifiedEvent {
  const ProviderErrorEvent(this.message);
  final String message;
}
