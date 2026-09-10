import 'package:dio/dio.dart' show CancelToken;

import '../domain/models.dart';
import 'agent_executor.dart';
import 'run_controller.dart';

/// 单次 Agent 运行的「代次 / 取消 / 预算断点」状态机。
///
/// 这一组字段彼此强耦合 —— 代次、取消标记与会话归属共同决定"这次运行是否还
/// 拥有写回状态的权力"，而它们并不依赖 UI 状态本身，因此从 `ChatController`
/// 抽出后可以独立测试（见 `test/run_coordinator_test.dart`）。
///
/// 约定：本类**不**读写 `ChatState`。状态复位仍由 `ChatController` 负责，
/// 保证"谁拥有状态谁写状态"，也让本类的行为完全由入参决定。
class RunCoordinator {
  RunCoordinator({required this.currentConversationId});

  /// 读取当前会话 id 的回调。由宿主注入，避免本类反向依赖控制器。
  final String? Function() currentConversationId;

  int _generation = 0;
  final Set<int> _cancelledGenerations = <int>{};

  /// 当前运行的模型层取消令牌（Agent 循环读取它判断是否中止）。
  AgentCancellationToken? cancellationToken;

  /// 当前运行的 Dio 层取消令牌（真正中断底层 HTTP 流）。
  CancelToken? dioCancelToken;

  /// 当前运行的生命周期控制器（pause / steer / cancel）。
  AgentRunController? runController;

  /// 预算暂停时保存的 Agent 内部上下文；用于断点续跑而非重提原始 prompt。
  List<ChatMessage>? budgetPauseContext;

  /// 当前运行代次；[beginRun] 与 [invalidateActiveRun] 都会使其自增。
  int get generation => _generation;

  /// 开始新一轮运行：代次自增，并解除该代次的取消标记。
  int beginRun() {
    final generation = ++_generation;
    _cancelledGenerations.remove(generation);
    return generation;
  }

  /// 该代次是否已被显式取消（切换会话 / 新建会话 / 停止都会标记）。
  bool wasCancelled(int generation) =>
      _cancelledGenerations.contains(generation);

  /// 该代次结束收尾后忘掉取消标记，避免集合无界增长。
  void forget(int generation) => _cancelledGenerations.remove(generation);

  /// 该代次的运行是否仍拥有状态写回权：代次未过期、未被取消、会话未被切走。
  bool ownsRun(int generation, String? conversationId) =>
      generation == _generation &&
      currentConversationId() == conversationId &&
      !_cancelledGenerations.contains(generation);

  /// 与 [ownsRun] 同义，但当 [conversationId] 为空时不校验会话归属
  /// （任务恢复时可能没有可切换的会话，此时只校验代次与取消标记）。
  bool ownsRunUnbound(int generation, String? conversationId) =>
      generation == _generation &&
      !_cancelledGenerations.contains(generation) &&
      (conversationId == null || currentConversationId() == conversationId);

  /// 让当前运行失效：标记取消、清空预算断点、自增代次，并取消三个取消源。
  void invalidateActiveRun() {
    final generation = _generation;
    _cancelledGenerations.add(generation);
    budgetPauseContext = null;
    _generation++;
    runController?.cancel();
    cancellationToken?.cancel();
    dioCancelToken?.cancel();
  }

  /// 仅当当前令牌仍是同一个实例时才清空，避免误清新一轮运行的令牌。
  void clearCancellationTokenIf(AgentCancellationToken token) {
    if (identical(cancellationToken, token)) cancellationToken = null;
  }

  void clearDioCancelTokenIf(CancelToken token) {
    if (identical(dioCancelToken, token)) dioCancelToken = null;
  }

  void clearRunControllerIf(AgentRunController controller) {
    if (identical(runController, controller)) runController = null;
  }
}
