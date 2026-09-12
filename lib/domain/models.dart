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

  /// 预算耗尽（达到 maxSteps）：不是真实失败，可携带上下文续跑。
  paused,
}

enum ToolRisk { safe, requiresConfirmation, dangerous }

/// 模型结束本轮的权威原因。
///
/// 这是“能否执行工具调用”的唯一判据：只有 [toolUse] 代表模型确实以工具调用
/// 结束本轮。[outputLimit] 意味着参数可能被截断，[contentFilter] 与 [unknown]
/// 里夹带的调用属于协议矛盾——三者都不得执行，只能回错误码让模型重新规划。
enum StopReason {
  toolUse,
  endOfTurn,
  outputLimit,
  contentFilter,
  unknown;

  /// 把 OpenAI / Anthropic / Gemini 三家的结束原因归一。
  /// 未识别的值一律落到 [unknown]（保守：不执行任何夹带的工具调用）。
  static StopReason parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'tool_calls':
      case 'tool_use':
        return StopReason.toolUse;
      case 'stop':
      case 'end_turn':
      case 'stop_sequence':
      case 'pause_turn':
        return StopReason.endOfTurn;
      case 'length':
      case 'max_tokens':
        return StopReason.outputLimit;
      case 'content_filter':
      case 'refusal':
      case 'safety':
      case 'recitation':
      case 'blocklist':
      case 'prohibited_content':
      case 'spii':
      case 'image_safety':
        return StopReason.contentFilter;
      default:
        return StopReason.unknown;
    }
  }
}

/// Session-level policy for deciding whether a tool call needs a user prompt.
enum ApprovalMode { ask, autoSafe, fullAccess }

/// 工具审批决策：拒绝 / 仅本次 / 本会话内 / 始终允许（全局信任）。
enum ToolApproval { reject, allowOnce, allowSession, allowAlways }

typedef ToolApprovalCallback = Future<ToolApproval> Function(
  ToolCall call,
  ToolRisk risk,
  bool sensitive,
);

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
    this.reasoningDuration,
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

  /// 思考过程耗时：首个思考 token → 首个正文 token。
  ///
  /// 不要用 [ttft] 代替——[ttft] 是「首个 token」的耗时，而思考流本身
  /// 就产出 token，所以 TTFT 落在思考的**开始**处，而不是思考结束处。
  final Duration? reasoningDuration;

  ChatMessage copyWith({
    MessageRole? role,
    List<MessagePart>? parts,
    String? toolCallId,
    List<ToolCall>? toolCalls,
    String? modelName,
    Usage? usage,
    Duration? elapsed,
    Duration? ttft,
    String? reasoning,
  }) =>
      ChatMessage(
        role: role ?? this.role,
        parts: parts ?? this.parts,
        toolCallId: toolCallId ?? this.toolCallId,
        toolCalls: toolCalls ?? this.toolCalls,
        modelName: modelName ?? this.modelName,
        usage: usage ?? this.usage,
        elapsed: elapsed ?? this.elapsed,
        ttft: ttft ?? this.ttft,
        reasoning: reasoning ?? this.reasoning,
      );

  String get text => parts.map((part) {
        if (part.type == 'image') return '[图片]';
        if (part.type == 'file') return '[文件]';
        if (part.type == 'audio') return '[音频]';
        if (part.type == 'video') return '[视频]';
        return part.value;
      }).join();
}

/// Ephemeral assistant content shown while a response is still streaming.
/// It is intentionally kept outside the persisted message list so each
/// incremental update does not copy the entire conversation history.
class LiveReply {
  const LiveReply({
    required this.messageIndex,
    required this.text,
    this.reasoning,
  });

  final int messageIndex;
  final String text;
  final String? reasoning;
}

class Usage {
  const Usage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cachedTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;

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
    this.sensitive = false,
    this.timeout = defaultTimeout,
  });

  /// 单次工具执行的默认超时上限。
  ///
  /// 单个工具可在自己的 manifest 里覆盖（例如 terminal 的命令可能长时间运行）。
  /// 超时由 AgentExecutor 统一包装：到点即返回 TIMEOUT 失败信封并继续回合，
  /// 避免一个卡死的工具无限期挂住整个 Agent 回合。
  static const Duration defaultTimeout = Duration(seconds: 120);

  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final ToolRisk risk;

  /// 敏感操作标记：无论审批模式或信任状态如何，都强制要求用户显式审批，
  /// 不允许通过 fullAccess / 全局信任等渠道自动放行。
  ///
  /// 注意：它与「持久化脱敏」（`SensitiveToolPolicy`）是两条独立的线，
  /// 判定口径不同，切勿互相驱动。
  final bool sensitive;

  /// 单次执行的超时上限，默认 [defaultTimeout]。
  final Duration timeout;

  /// 返回只包含新容器的声明副本，避免能力投影改写下一轮共用的 schema。
  UnifiedTool copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? parametersSchema,
    ToolRisk? risk,
    bool? sensitive,
    Duration? timeout,
  }) =>
      UnifiedTool(
        name: name ?? this.name,
        description: description ?? this.description,
        parametersSchema:
            deepCopyJsonMap(parametersSchema ?? this.parametersSchema),
        risk: risk ?? this.risk,
        sensitive: sensitive ?? this.sensitive,
        timeout: timeout ?? this.timeout,
      );

  Map<String, dynamic> toOpenAiSchema() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parametersSchema,
        },
      };
}

/// 深拷贝工具 schema / JSON 数据。工具目录会按回合投影，不能共享嵌套
/// Map/List，否则模型适配器修改 enum 时会污染注册表原始声明。
Map<String, dynamic> deepCopyJsonMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.fromEntries(value.entries.map(
      (entry) => MapEntry(entry.key, deepCopyJsonValue(entry.value)),
    ));

dynamic deepCopyJsonValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(value.entries.map((entry) =>
        MapEntry(entry.key.toString(), deepCopyJsonValue(entry.value))));
  }
  if (value is List) {
    return value.map(deepCopyJsonValue).toList(growable: true);
  }
  return value;
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
  const CompletedEvent({this.stopReason = StopReason.unknown});

  /// 本轮结束的权威原因。服务商未提供时为 [StopReason.unknown]，
  /// 此时调用方不得执行任何夹带的工具调用。
  final StopReason stopReason;
}

class UsageEvent extends UnifiedEvent {
  const UsageEvent(
      {required this.promptTokens,
      required this.completionTokens,
      this.cachedTokens = 0});
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
}

class ProviderErrorEvent extends UnifiedEvent {
  const ProviderErrorEvent(
    this.message, {
    this.statusCode,
    this.failureKind,
  });
  final String message;
  final int? statusCode;
  final String? failureKind;
}
