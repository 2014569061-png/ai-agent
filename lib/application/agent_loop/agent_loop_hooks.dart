import '../../domain/models.dart';
import '../../domain/tool_result.dart';
import '../agent_executor.dart' show AgentEvent;

/// 一次模型请求的上下文信息。
class RequestContext {
  const RequestContext({required this.step, required this.model});

  /// 从 1 开始的步号。
  final int step;
  final String model;
}

/// [RequestTransform] 的输出：新的消息列表，以及需要发给调用方的事件。
class RequestTransformResult {
  const RequestTransformResult(this.messages,
      [this.events = const <AgentEvent>[]]);

  /// 返回输入列表本身表示未改动；返回其他列表时执行器会复制一份自有列表。
  final List<ChatMessage> messages;
  final List<AgentEvent> events;
}

/// `request` 阶段钩子：在每次模型请求前改写消息（Harness `agent/request`）。
///
/// 执行顺序：已排队的工具结果压缩 → 外部 transform（按注册顺序）→ 上下文
/// 窗口裁剪。外部 transform 放在裁剪之前，注入的内容同样受预算约束。
/// 改写后的内容会进入 onRequest 快照，因此会被会话日志记录。
abstract interface class RequestTransform {
  String get id;
  RequestTransformResult apply(RequestContext context, List<ChatMessage> messages);
}

/// 请求观察者：收到发送时刻的不可变快照（会话日志即是其中之一）。
typedef RequestObserver = void Function(int step, UnifiedRequest request);

/// `tools/post-execute` 观察者：只会收到真正进入执行边界的工具结果；
/// 守卫短路和审批拒绝不会通知。
abstract interface class ToolOutcomeObserver {
  void onToolOutcome(ToolCall call, ToolResult result);
}

/// 模型准备结束本轮（没有工具调用）时的上下文。
class TurnStoppingContext {
  const TurnStoppingContext({required this.step, required this.finalText});
  final int step;
  final String finalText;
}

/// [TurnStoppingHandler] 要求继续运行时的指令。
class TurnContinuation {
  const TurnContinuation(this.messages, {this.keepAssistantText = true});

  /// 追加给模型的消息（通常是 user 角色的提示），不能为空。
  final List<ChatMessage> messages;

  /// 是否先把本步的 assistant 回复写入上下文。steering 为 false（现状行为：
  /// 被插话打断的那一步回复不进入下一次请求）。
  final bool keepAssistantText;
}

/// `turn-stopping` 阶段钩子：可以否决“本轮结束”并让运行继续
/// （Harness `agent/turn-stopping`）。按注册顺序询问，第一个返回非 null 的生效。
abstract interface class TurnStoppingHandler {
  String get id;
  TurnContinuation? onTurnStopping(TurnStoppingContext context);
}

/// 执行器级的阶段钩子集合，由组合层（阶段 3 的 ModuleHost）装配。
class AgentLoopHooks {
  const AgentLoopHooks({
    this.requestTransforms = const [],
    this.requestObservers = const [],
    this.toolOutcomeObservers = const [],
    this.turnStopping = const [],
  });

  static const empty = AgentLoopHooks();

  final List<RequestTransform> requestTransforms;
  final List<RequestObserver> requestObservers;
  final List<ToolOutcomeObserver> toolOutcomeObservers;
  final List<TurnStoppingHandler> turnStopping;

  /// 合并两组钩子，[other] 的各项排在后面。
  AgentLoopHooks merge(AgentLoopHooks other) => AgentLoopHooks(
        requestTransforms: [...requestTransforms, ...other.requestTransforms],
        requestObservers: [...requestObservers, ...other.requestObservers],
        toolOutcomeObservers: [
          ...toolOutcomeObservers,
          ...other.toolOutcomeObservers,
        ],
        turnStopping: [...turnStopping, ...other.turnStopping],
      );
}
