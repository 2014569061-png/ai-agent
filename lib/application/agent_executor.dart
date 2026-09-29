import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/context_insights.dart';
import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/providers/provider_config.dart';
import 'context_window.dart';
import '../domain/model_failure.dart';
import 'context_snapshot_builder.dart';
import 'context_compression_applier.dart';
import 'run_controller.dart';
import 'tool_pipeline/execution_interceptors.dart';
import 'tool_pipeline/tool_invocation.dart';
import 'tool_pipeline/tool_pipeline.dart';
import 'tool_pipeline/tool_run_context.dart';

class AgentExecutor {
  AgentExecutor({
    required this.provider,
    required this.tools,
    ToolPipeline? toolPipeline,
  }) : toolPipeline = toolPipeline ?? defaultToolPipeline;
  final LlmProvider provider;
  final ToolRegistry tools;

  /// 本执行器使用的工具调用管线。未指定时使用 [defaultToolPipeline]；
  /// 调用方可在默认拦截器基础上插入审计、网络策略等环节，
  /// 例如 `ToolPipeline([...defaultToolInterceptors(), myInterceptor])`。
  final ToolPipeline toolPipeline;

  /// 默认管线：前置守卫 → 审批 → 检查点 → 执行边界 → 授权 → 超时执行。
  /// 拦截器均为无状态实现，可在所有执行器间共享。
  static final ToolPipeline defaultToolPipeline =
      ToolPipeline(defaultToolInterceptors());

  Stream<AgentEvent> run({
    required List<ChatMessage> history,
    required String model,
    int maxSteps = 8,
    double temperature = 0.7,
    int maxTokens = 2048,
    double topP = 1.0,
    ReasoningEffort reasoningEffort = ReasoningEffort.off,

    /// 读取空闲超时，而非整个响应的总时长；长回答只要持续有新数据就不会被误杀。
    Duration requestTimeout = const Duration(minutes: 5),
    int contextBudgetTokens = ContextWindow.defaultMaxTokens,
    int maxRetries = 3,
    Duration retryBackoff = const Duration(seconds: 2),
    AgentCancellationToken? cancellationToken,
    CancelToken? cancelToken,
    ToolApprovalCallback? approveTool,
    ApprovalMode approvalMode = ApprovalMode.ask,
    bool Function(String toolName, ToolRisk risk)? isToolTrusted,
    String? systemPrompt,
    ModelCapabilities capabilities = const ModelCapabilities(),
    Future<bool> Function(List<ToolCall> calls, String planText)? confirmPlan,
    AgentRunController? runController,

    /// 到达 [maxSteps] 时若最近仍有进展（最近有工具成功、最后 4 次不全失败），
    /// 自动再追加一轮 [maxSteps] 预算的次数上限；0 表示不自动续跑。
    int autoContinueLimit = 0,

    /// 连续多少次工具失败（中间没有任何成功）后提前暂停；0 表示不熔断。
    int failurePauseThreshold = 4,
  }) async* {
    var messages = List<ChatMessage>.of(history);

    // 结算一次工具调用：追加对应的 tool 消息并返回结果事件。
    // 每个调用必须恰好结算一次，且顺序与模型给出的调用顺序一致。
    ToolResultEvent settle(
      ToolCall call,
      ToolResult result, {
      Map<String, dynamic> metadata = const <String, dynamic>{},
    }) {
      messages.add(ChatMessage(
        role: MessageRole.tool,
        toolCallId: call.id,
        parts: [MessagePart.text(result.encode())],
      ));
      return ToolResultEvent(call, result, metadata: metadata);
    }
    // 内置环境规则与业务 system prompt 分开构造，确保调用方未传 prompt 或
    // 历史已带 system 消息时，模型仍然知道当前设备的真实能力边界。
    final builtInRules = <String>[];
    if (Platform.isAndroid &&
        tools.manifests.any((t) => t.name == 'terminal')) {
      builtInRules.add(
        '[运行环境说明] 当前运行在 Android 手机上。terminal 工具优先使用内置 '
        'Alpine Linux（PRoot + ARM64 rootfs），不可用时回退到 Termux，再回退到 Android Shell。'
        '内置 Alpine 默认是精简 rootfs，提供 sh/ash/BusyBox 基础命令；Go/Git/Node/Python 等工具'
        '可能尚未安装，需要先在 Alpine 中执行 apk add，或使用已配置的 Termux 工具链。'
        '不要默认声称环境无法运行 Linux 命令；编译或测试报错时先检查当前 Runtime 和缺失工具，'
        '再安装依赖或切换备用 Runtime。',
      );
      builtInRules.add(
        '[共享存储] 手机共享存储只有在用户授予「所有文件访问权限」后，才会挂载到内置 '
        'Alpine 的 /sdcard 与 /storage/emulated/0。访问这些路径报 No such file 或 '
        'Permission denied 时说明尚未授权：不要换路径反复重试，直接请用户到系统设置 → '
        '应用 → 本应用 → 权限中开启「所有文件访问」，授权后再继续。',
      );
    }
    final builtInSystemText = builtInRules.join('\n\n');
    final requestedSystemText = systemPrompt?.trim() ?? '';
    final systemIndex =
        messages.indexWhere((m) => m.role == MessageRole.system);
    if (systemIndex >= 0) {
      final existing = messages[systemIndex];
      final additions = <String>[];
      if (requestedSystemText.isNotEmpty &&
          !existing.text.contains(requestedSystemText)) {
        additions.add(requestedSystemText);
      }
      if (builtInSystemText.isNotEmpty &&
          !existing.text.contains(builtInSystemText)) {
        additions.add(builtInSystemText);
      }
      if (additions.isNotEmpty) {
        final combined = [existing.text.trim(), ...additions]
            .where((value) => value.isNotEmpty)
            .join('\n\n');
        messages[systemIndex] = existing.copyWith(
          parts: [MessagePart.text(combined)],
        );
      }
    } else {
      final systemText = [requestedSystemText, builtInSystemText]
          .where((value) => value.isNotEmpty)
          .join('\n\n');
      if (systemText.isNotEmpty) {
        messages.insert(
          0,
          ChatMessage(
            role: MessageRole.system,
            parts: [MessagePart.text(systemText)],
          ),
        );
      }
    }
    // 上下文预算：每步请求前裁剪一次，同时约束初始历史与多步工具循环
    // 中持续追加的工具结果。
    // 工具定义也占模型输入窗口；历史裁剪必须先扣除这部分固定成本，
    // 并为本次模型输出预留 maxTokens，避免输入与输出合计超过窗口。
    // 工具目录在下方排序后计算固定成本，保持与快照和实际请求一致。
    // 工具定义数组是 Provider 前缀缓存的一部分（Anthropic 还显式在 tools
    // 段打缓存断点）。目录按装配顺序生成（内置/MCP/插件/工作区），装配顺序
    // 受运行环境影响；这里按名称稳定排序，保证同一份工具目录在整个运行期
    // 的每一步请求中字节级一致，不因装配差异打爆前缀缓存。
    final requestTools = capabilities.tools
        ? (tools.manifests.toList()..sort((a, b) => a.name.compareTo(b.name)))
        : const <UnifiedTool>[];
    final fixedToolTokens =
        ContextSnapshotBuilder.estimateToolTokens(requestTools);
    final reservedOutputTokens = ContextBudget.outputReservationFor(
      contextWindow: contextBudgetTokens,
      requestedOutputTokens: maxTokens,
    );
    final inputBudget = ContextBudget.inputBudgetFor(
      contextWindow: contextBudgetTokens,
      reservedOutputTokens: reservedOutputTokens,
    );
    final contextWindow = ContextWindow(
      maxTokens: inputBudget,
      fixedTokens: fixedToolTokens,
    );
    var totalPromptTokens = 0;
    var totalCompletionTokens = 0;
    var totalCachedTokens = 0;
    var totalCacheWriteTokens = 0;
    var totalReasoningTokens = 0;
    var sawUsageStats = false;
    var sawCacheStats = false;
    ContextSnapshot? previousSnapshot;
    var contextWasCompressed = false;
    bool isCancelled() =>
        (cancellationToken?.isCancelled ?? false) ||
        (runController?.isCancelled ?? false);

    Future<void> checkpoint() async {
      await runController?.checkpoint();
    }

    // 统一的暂停检查点：已暂停时先发出 paused（UI 立即切到「已暂停」并露出
    // 继续/停止按钮），再等待恢复或取消。以前工具调用前的检查点只会静默阻塞，
    // UI 一直停在「运行中」，看起来就像暂停没有生效。
    Stream<AgentEvent> pausePoint() async* {
      if (!(runController?.isPaused ?? false)) return;
      yield const AgentStatusEvent(RunStatus.paused);
      await checkpoint();
    }

    void appendSteering(Iterable<String> instructions) {
      for (final instruction in instructions) {
        messages.add(ChatMessage(
          role: MessageRole.user,
          parts: [
            MessagePart.text(
              '用户补充指令：$instruction\n请继续执行，不要从头重复已完成的步骤。',
            ),
          ],
        ));
      }
    }

    // 失败熔断与进展判断：只统计真正执行过的工具结果。
    final recentOutcomes = <bool>[];
    final failuresByCall = <String, int>{};
    final hintedCalls = <String>{};
    final failureHints = <String>[];
    var consecutiveFailures = 0;

    String callSignature(ToolCall call) {
      try {
        return '${call.name} ${jsonEncode(call.arguments)}';
      } catch (_) {
        return '${call.name} ${call.arguments}';
      }
    }

    void recordToolOutcome(ToolCall call, ToolResult result) {
      recentOutcomes.add(result.ok);
      if (recentOutcomes.length > 12) recentOutcomes.removeAt(0);
      final signature = callSignature(call);
      if (result.ok) {
        consecutiveFailures = 0;
        failuresByCall.remove(signature);
        return;
      }
      consecutiveFailures++;
      final count = (failuresByCall[signature] ?? 0) + 1;
      failuresByCall[signature] = count;
      if (count >= 2 && hintedCalls.add(signature)) {
        failureHints.add(
          '[系统提示] 工具 ${call.name} 以完全相同的参数已经失败 $count 次。不要再原样'
          '重试：先分析失败原因（权限、路径、依赖是否存在）并换一种方法；如果需要'
          '用户授权或补充信息，请直接向用户说明。',
        );
      }
    }

    // 进展判断：最近有工具成功，且最后 4 次不全是失败。
    bool hasRecentProgress() {
      if (!recentOutcomes.contains(true)) return false;
      final tail = recentOutcomes.length > 4
          ? recentOutcomes.sublist(recentOutcomes.length - 4)
          : recentOutcomes;
      return tail.contains(true);
    }

    var budget = maxSteps;
    var autoContinued = 0;
    for (var step = 0;; step++) {
      if (step >= budget) {
        // 预算用完但最近仍有进展：自动再给一轮预算（最多 autoContinueLimit
        // 次），不打断用户；没有进展或次数用完才暂停。
        if (autoContinued >= autoContinueLimit || !hasRecentProgress()) break;
        autoContinued++;
        budget += maxSteps;
        yield AgentBudgetExtendedEvent(
          round: autoContinued,
          limit: autoContinueLimit,
          addedSteps: maxSteps,
        );
      }
      yield* pausePoint();
      if (isCancelled()) {
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      yield const AgentStatusEvent(RunStatus.waitingModel);
      final compressionIds =
          runController?.drainCompressionToolCallIds() ?? const <String>{};
      if (compressionIds.isNotEmpty) {
        final compression = const ContextCompressionApplier()
            .applyToolCallIds(messages, compressionIds);
        messages = List<ChatMessage>.of(compression.messages);
        if (compression.appliedCandidates.isNotEmpty) {
          yield AgentContextCompressionEvent(
            toolCallIds: compression.appliedCandidates
                .map((candidate) => candidate.toolCallId)
                .whereType<String>()
                .toList(growable: false),
            candidateCount: compression.appliedCandidates.length,
            estimatedSavedTokens: compression.savedTokens,
            originalTokens: compression.originalTokens,
            compressedTokens: compression.compressedTokens,
          );
        }
      }
      messages = contextWindow.apply(messages);
      final request = UnifiedRequest(
        model: model,
        messages: messages,
        tools: requestTools,
        temperature: temperature,
        maxTokens: reservedOutputTokens,
        topP: topP,
        reasoningEffort: reasoningEffort,
      );
      final snapshot = ContextSnapshotBuilder.build(
        messages: messages,
        tools: requestTools,
        contextWindow: contextBudgetTokens,
        reservedOutputTokens: reservedOutputTokens,
      );
      final anchorMessageId = messages.reversed
          .where((message) => message.role != MessageRole.system)
          .map((message) => message.id)
          .whereType<String>()
          .firstOrNull;
      yield ContextSnapshotEvent(
        step: step + 1,
        snapshot: snapshot,
        anchorMessageId: anchorMessageId,
      );
      if (snapshot.budgetLevel != ContextBudgetLevel.normal) {
        yield ContextBudgetWarningEvent(
          level: snapshot.budgetLevel,
          usedTokens: snapshot.usedTokens,
          contextWindow: snapshot.contextWindow,
          remainingTokens: snapshot.remainingTokens,
          dominantPart: snapshot.dominantPart?.type.name,
        );
      }
      for (final change in _contextChanges(
        step: step + 1,
        previous: previousSnapshot,
        current: snapshot,
        compressed: messages.any(
            (message) => message.text.contains(ContextWindow.compactionNotice)),
        wasCompressed: contextWasCompressed,
      )) {
        yield change;
      }
      contextWasCompressed = messages.any(
          (message) => message.text.contains(ContextWindow.compactionNotice));
      previousSnapshot = snapshot;
      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      var stepPromptTokens = 0;
      var stepCompletionTokens = 0;
      var stepCachedTokens = 0;
      var stepCacheWriteTokens = 0;
      var stepReasoningTokens = 0;
      var stepUsageReported = false;
      var stepCacheStatsReported = false;
      final pendingCalls = <ToolCall>[];
      var stopReason = StopReason.unknown;
      // 暂停即中断：本轮模型请求使用独立的 CancelToken，并与运行级 token 联动
      // （停止时一并取消）。用户点暂停时，若本轮还没产出工具调用，就立即掐断
      // 流式输出；已输出的半截文字留作上下文，恢复后让模型从中断处接着写。
      final stepCancelToken = CancelToken();
      final runCancelToken = cancelToken;
      if (runCancelToken != null) {
        unawaited(runCancelToken.whenCancel.then<void>((_) {
          if (!stepCancelToken.isCancelled) stepCancelToken.cancel();
        }));
      }
      var pauseInterrupted = false;
      runController?.onPauseInterrupt = () {
        if (pendingCalls.isNotEmpty || stepCancelToken.isCancelled) return;
        pauseInterrupted = true;
        stepCancelToken.cancel('paused');
      };
      // 失败自动重试：本轮尚未产出任何内容（无文本/推理/工具调用）且底层
      // 请求失败时，指数退避后整体重发；已产出内容则不重试，避免文本重复
      // 渲染与工具重复副作用。Dio 层 RetryInterceptor 对流式请求不重试，
      // 这里是 SSE 失败的唯一重试路径。
      var attempts = 0;
      while (true) {
        ProviderErrorEvent? failure;
        try {
          await for (final event in provider
              .stream(request, cancelToken: stepCancelToken)
              .timeout(requestTimeout)) {
            if (isCancelled()) {
              yield const AgentStatusEvent(RunStatus.cancelled);
              return;
            }
            if (pauseInterrupted) break;
            if (event is TextDeltaEvent) {
              textBuffer.write(event.text);
              yield TextEvent(event.text);
            } else if (event is ReasoningDeltaEvent) {
              reasoningBuffer.write(event.text);
              yield ReasoningEvent(event.text);
            } else if (event is ToolCallEvent) {
              pendingCalls.add(event.call);
              yield ToolRequestedEvent(event.call);
            } else if (event is CompletedEvent) {
              stopReason = event.stopReason;
            } else if (event is UsageEvent) {
              totalPromptTokens += event.promptTokens;
              totalCompletionTokens += event.completionTokens;
              totalCachedTokens += event.cachedTokens;
              totalCacheWriteTokens += event.cacheWriteTokens;
              totalReasoningTokens += event.reasoningTokens;
              stepPromptTokens += event.promptTokens;
              stepCompletionTokens += event.completionTokens;
              stepCachedTokens += event.cachedTokens;
              stepCacheWriteTokens += event.cacheWriteTokens;
              stepReasoningTokens += event.reasoningTokens;
              sawUsageStats = sawUsageStats || event.usageReported;
              stepUsageReported = stepUsageReported || event.usageReported;
              if (event.usageReported && event.cacheStatsReported) {
                sawCacheStats = true;
                stepCacheStatsReported = true;
              }
            } else if (event is ProviderErrorEvent) {
              failure = event;
              break;
            }
          }
        } on TimeoutException {
          // 空闲超时属于 transient failure，先让统一重试分类决定是否重试。
          // 只有最终失败时才取消调用方持有的底层 HTTP token。
          failure = ProviderErrorEvent(
            '模型请求超时（${requestTimeout.inSeconds} 秒）',
            failureKind: 'receiveTimeout',
          );
        }
        // 暂停中断时 provider 按约定会静默结束；即便个别实现仍产出错误，也按
        // 中断处理：不重试，也不当作失败。
        if (failure == null || (pauseInterrupted && !isCancelled())) break;
        final classified = ModelFailure.classify(
          failure.message,
          statusCode: failure.statusCode,
          failureKind: failure.failureKind,
        );
        if (!classified.retryable) {
          cancelToken?.cancel();
          yield AgentErrorEvent(
            failure.message,
            retryable: false,
            failureKind: classified.kind,
            statusCode: classified.statusCode,
          );
          return;
        }
        final hasContent = textBuffer.isNotEmpty ||
            reasoningBuffer.isNotEmpty ||
            pendingCalls.isNotEmpty;
        if (hasContent || attempts >= maxRetries) {
          cancelToken?.cancel();
          yield AgentErrorEvent(
            failure.message,
            retryable: true,
            failureKind: classified.kind,
            statusCode: classified.statusCode,
          );
          return;
        }
        attempts++;
        yield AgentRetryEvent(attempts);
        if (isCancelled()) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        // 指数退避：第 1/2/3 次重试分别等待 2/4/8 秒。退避只针对
        // 尚未产生任何模型输出的瞬态失败，避免把已有工具调用重复提交。
        final delay = retryBackoff * (1 << (attempts - 1));
        final cancelled =
            cancellationToken?.whenCancelled ?? runController?.whenCancelled;
        if (cancelled == null) {
          await Future<void>.delayed(delay);
        } else {
          await Future.any<void>([Future<void>.delayed(delay), cancelled]);
        }
        if (isCancelled()) {
          cancelToken?.cancel();
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
      }
      runController?.onPauseInterrupt = null;
      // 流被主动取消（底层 HTTP 已真正中断）时，不产出 completed。
      if (isCancelled()) {
        cancelToken?.cancel();
        yield const AgentStatusEvent(RunStatus.cancelled);
        return;
      }
      if (pauseInterrupted) {
        // 本轮被暂停中断：丢弃可能不完整的工具调用；已输出的半截文字作为
        // assistant 上下文保留，并提示模型恢复后从中断处接着写。回到循环
        // 顶部，由暂停检查点发出 paused，等待继续或停止。
        final partial = textBuffer.toString();
        if (partial.trim().isNotEmpty) {
          messages.add(ChatMessage(
            role: MessageRole.assistant,
            parts: [MessagePart.text(partial)],
          ));
          messages.add(ChatMessage(
            role: MessageRole.user,
            parts: const [
              MessagePart.text(
                '[系统提示] 上一段回复因用户暂停被中断。继续时请从中断处接着完成，'
                '不要重复已经输出的内容。',
              ),
            ],
          ));
        }
        continue;
      }
      yield AgentStepUsageEvent(
        step: step + 1,
        usage: Usage(
          promptTokens: stepPromptTokens,
          completionTokens: stepCompletionTokens,
          cachedTokens: stepCachedTokens,
          cacheWriteTokens: stepCacheWriteTokens,
          reasoningTokens: stepReasoningTokens,
          usageReported: stepUsageReported,
          cacheStatsReported: stepCacheStatsReported,
        ),
      );
      if (pendingCalls.isEmpty) {
        final steering = runController?.pollSteeringOrSeal() ?? const [];
        if (steering.isNotEmpty) {
          appendSteering(steering);
          continue;
        }
        messages.add(ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(textBuffer.toString())],
          reasoning:
              reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        ));
        yield AgentUsageEvent(
            promptTokens: totalPromptTokens,
            completionTokens: totalCompletionTokens,
            cachedTokens: totalCachedTokens,
            cacheWriteTokens: totalCacheWriteTokens,
            reasoningTokens: totalReasoningTokens,
            usageReported: sawUsageStats,
            cacheStatsReported: sawCacheStats);
        yield const AgentStatusEvent(RunStatus.completed);
        return;
      }
      // C3 计划模式门禁：首轮有工具调用时，先产出计划等待用户确认，再执行工具。
      // 只有模型明确以 toolUse 结束本轮时，夹带的调用才具备可执行资格。
      // outputLimit 通常意味着参数可能被截断，其他停因则属于协议矛盾；两者都必须
      // 回灌结构化错误，让模型重新规划，而不是把不完整调用交给真实工具。
      if (stopReason != StopReason.toolUse) {
        messages.add(ChatMessage(
          role: MessageRole.assistant,
          parts: [MessagePart.text(textBuffer.toString())],
          toolCalls: List<ToolCall>.unmodifiable(pendingCalls),
          reasoning:
              reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        ));
        final code = stopReason == StopReason.outputLimit
            ? ToolCodes.truncatedToolCall
            : ToolCodes.unexpectedToolCall;
        final message = stopReason == StopReason.outputLimit
            ? '模型输出达到长度上限，工具参数可能不完整，本次未执行'
            : '模型停因不是工具调用，本次夹带的工具调用未执行';
        for (final pendingCall in pendingCalls) {
          yield settle(
            pendingCall,
            ToolResult.failure(code: code, message: message),
          );
        }
        continue;
      }
      var planApproved = false;
      if (step == 0 && confirmPlan != null && pendingCalls.isNotEmpty) {
        final approved = await confirmPlan(pendingCalls, textBuffer.toString());
        if (!approved) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        planApproved = true;
      }
      messages.add(ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(textBuffer.toString())],
        toolCalls: List<ToolCall>.unmodifiable(pendingCalls),
        reasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
      ));
      for (final pendingCall in pendingCalls) {
        final registration = tools.findRegistration(pendingCall.name);
        final channel = StreamController<_ToolEmission>();
        final context = ToolRunContext(
          approvalMode: approvalMode,
          approveTool: approveTool,
          isToolTrusted: isToolTrusted,
          isCancelled: isCancelled,
          isPaused: () => runController?.isPaused ?? false,
          waitForResume: checkpoint,
          emit: (event) {
            final emission = _ToolEmission(event);
            channel.add(emission);
            return emission.delivered.future;
          },
        );
        ToolResult? pipelineResult;
        Object? pipelineError;
        StackTrace? pipelineTrace;
        final settled = toolPipeline
            .run(
              ToolInvocation(
                call: pendingCall,
                registration: registration,
                context: context,
              ),
              executeWithTimeout,
            )
            .then<void>(
              (result) => pipelineResult = result,
              onError: (Object error, StackTrace trace) {
                pipelineError = error;
                pipelineTrace = trace;
              },
            )
            .whenComplete(channel.close);
        // 管线事件逐个 yield：消费方处理完毕、恢复本生成器后才确认送达，
        // 拦截器随后才继续（例如先落库「等待确认」，再调用 approveTool）。
        await for (final emission in channel.stream) {
          yield emission.event;
          emission.delivered.complete();
        }
        await settled;
        final error = pipelineError;
        if (error is ToolRunCancelled) {
          yield const AgentStatusEvent(RunStatus.cancelled);
          return;
        }
        if (error != null) {
          Error.throwWithStackTrace(error, pipelineTrace ?? StackTrace.current);
        }
        final toolResult = pipelineResult;
        if (toolResult == null) {
          throw StateError('工具管线未产出结果：${pendingCall.name}');
        }
        // 未进入执行边界（守卫短路或审批拒绝）：不附带元数据，也不计入熔断。
        if (!context.executionStarted) {
          yield settle(pendingCall, toolResult);
          continue;
        }
        final metadata = switch (registration?.executor) {
          final ToolExecutionMetadata source => source.lastMetadata,
          _ => const <String, dynamic>{},
        };
        yield settle(pendingCall, toolResult, metadata: metadata);
        recordToolOutcome(pendingCall, toolResult);
      }
      // 同一调用反复失败：在本步全部工具结果之后提醒模型换方法（不能插在
      // 工具结果中间，否则会破坏 assistant tool_calls → tool 的消息顺序）。
      if (failureHints.isNotEmpty) {
        messages.add(ChatMessage(
          role: MessageRole.user,
          parts: [MessagePart.text(failureHints.join('\n'))],
        ));
        failureHints.clear();
      }
      // 计划审批只负责放行首轮工具调用。工具返回后必须显式告诉模型继续
      // 执行已批准的计划，否则模型可能把“计划已提交”误判为本轮任务结束。
      if (planApproved) {
        messages.add(ChatMessage(
          role: MessageRole.user,
          parts: [
            const MessagePart.text(
              '[计划已确认] 用户已批准执行以上计划。请继续按照计划执行剩余步骤；需要工具时直接调用工具，不要只输出计划或提前结束。完成全部步骤后再总结结果。',
            )
          ],
        ));
      }
      appendSteering(runController?.drainSteering() ?? const []);
      // 连续失败熔断：多次失败且中间没有任何成功，提前暂停交给用户决定，
      // 避免模型在没有权限或环境缺失时空转到预算耗尽。
      if (failurePauseThreshold > 0 &&
          consecutiveFailures >= failurePauseThreshold) {
        yield const AgentStatusEvent(RunStatus.paused);
        yield AgentBudgetExhaustedEvent(
          context: messages,
          maxSteps: step + 1,
          reason: AgentPauseReason.repeatedFailures,
          message: '连续 $consecutiveFailures 次工具调用失败，任务已暂停，可继续执行',
        );
        return;
      }
    }
    // 达到 maxSteps 不是业务失败：将其区分为可恢复的"预算暂停"状态，并把
    // 当前完整上下文（含工具结果与已批准的续跑指令）一并交给调用方，便于
    // 从断点续跑，而不是重新提交原始 prompt。
    yield const AgentStatusEvent(RunStatus.paused);
    yield AgentBudgetExhaustedEvent(
      context: messages,
      maxSteps: budget,
    );
  }

  List<AgentContextChangeEvent> _contextChanges({
    required int step,
    required ContextSnapshot? previous,
    required ContextSnapshot current,
    required bool compressed,
    required bool wasCompressed,
  }) {
    if (previous == null) {
      return compressed
          ? [
              AgentContextChangeEvent(
                step: step,
                kind: 'context_compress',
                category: 'history',
                deltaTokens: 0,
              ),
            ]
          : const [];
    }
    final events = <AgentContextChangeEvent>[];
    for (final type in ContextPartType.values) {
      final before = previous.tokensFor(type);
      final after = current.tokensFor(type);
      final delta = after - before;
      if (delta == 0) continue;
      events.add(AgentContextChangeEvent(
        step: step,
        kind: delta > 0 ? 'context_inject' : 'context_prune',
        category: type.name,
        deltaTokens: delta,
      ));
    }
    if (compressed && !wasCompressed) {
      events.add(AgentContextChangeEvent(
        step: step,
        kind: 'context_compress',
        category: 'history',
        deltaTokens: current.usedTokens - previous.usedTokens,
      ));
    }
    return events;
  }
}

class AgentCancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancelCompleter = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelCompleter.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelCompleter.complete();
  }
}

sealed class AgentEvent {
  const AgentEvent();
}

class ContextSnapshotEvent extends AgentEvent {
  const ContextSnapshotEvent({
    required this.step,
    required this.snapshot,
    this.anchorMessageId,
  });

  final int step;
  final ContextSnapshot snapshot;
  final String? anchorMessageId;
}

/// Emitted after the local pre-request estimate and before the provider stream
/// starts, so the caller can persist a visible budget warning without changing
/// the request or silently deleting user history.
class ContextBudgetWarningEvent extends AgentEvent {
  const ContextBudgetWarningEvent({
    required this.level,
    required this.usedTokens,
    required this.contextWindow,
    required this.remainingTokens,
    this.dominantPart,
  });

  final ContextBudgetLevel level;
  final int usedTokens;
  final int contextWindow;
  final int remainingTokens;
  final String? dominantPart;
}

class AgentContextCompressionEvent extends AgentEvent {
  const AgentContextCompressionEvent({
    required this.toolCallIds,
    required this.candidateCount,
    required this.estimatedSavedTokens,
    required this.originalTokens,
    required this.compressedTokens,
  });

  final List<String> toolCallIds;
  final int candidateCount;
  final int estimatedSavedTokens;
  final int originalTokens;
  final int compressedTokens;
}

class AgentContextChangeEvent extends AgentEvent {
  const AgentContextChangeEvent({
    required this.step,
    required this.kind,
    required this.category,
    required this.deltaTokens,
  });

  final int step;
  final String kind;
  final String category;
  final int deltaTokens;
}

class AgentStepUsageEvent extends AgentEvent {
  const AgentStepUsageEvent({required this.step, required this.usage});

  final int step;
  final Usage usage;
}

class AgentStatusEvent extends AgentEvent {
  const AgentStatusEvent(this.status);
  final RunStatus status;
}

class TextEvent extends AgentEvent {
  const TextEvent(this.text);
  final String text;
}

class ReasoningEvent extends AgentEvent {
  const ReasoningEvent(this.text);
  final String text;
}

class ToolRequestedEvent extends AgentEvent {
  const ToolRequestedEvent(this.call);
  final ToolCall call;
}

class ApprovalRequiredEvent extends AgentEvent {
  const ApprovalRequiredEvent(this.call, this.risk);
  final ToolCall call;
  final ToolRisk risk;
}

class AgentErrorEvent extends AgentEvent {
  const AgentErrorEvent(
    this.message, {
    this.retryable = false,
    this.failureKind,
    this.statusCode,
  });
  final String message;
  final bool retryable;
  final String? failureKind;
  final int? statusCode;
}

/// 达到 maxSteps 触发的可恢复预算暂停。携带当前完整上下文，调用方可用它
/// 作为下一次 [AgentExecutor.run] 的 history，从断点续跑而不重新执行工具。
class AgentBudgetExhaustedEvent extends AgentEvent {
  const AgentBudgetExhaustedEvent({
    required this.context,
    required this.maxSteps,
    this.message = '已达到单次执行步数预算，任务已暂停，可继续执行',
    this.reason = AgentPauseReason.budget,
  });
  final List<ChatMessage> context;
  final int maxSteps;
  final String message;
  final AgentPauseReason reason;
}

/// 可恢复暂停的原因。
enum AgentPauseReason {
  /// 达到轮数预算（含自动续跑追加的部分）。
  budget,

  /// 连续多次工具失败，提前熔断。
  repeatedFailures,
}

/// 预算用完但最近仍有进展时，执行器自动追加一轮预算（不打断用户）。
class AgentBudgetExtendedEvent extends AgentEvent {
  const AgentBudgetExtendedEvent({
    required this.round,
    required this.limit,
    required this.addedSteps,
  });

  /// 第几次自动续跑（从 1 开始）。
  final int round;
  final int limit;
  final int addedSteps;
}

class AgentRetryEvent extends AgentEvent {
  const AgentRetryEvent(this.attempt);
  final int attempt;
}

class AgentUsageEvent extends AgentEvent {
  const AgentUsageEvent({
    required this.promptTokens,
    required this.completionTokens,
    this.cachedTokens = 0,
    this.cacheWriteTokens = 0,
    this.reasoningTokens = 0,
    this.usageReported = false,
    this.cacheStatsReported = false,
  });
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;

  /// 缓存写入 token（Anthropic cache_creation_input_tokens）。
  final int cacheWriteTokens;

  /// 推理 token（已包含在 completionTokens 内）。
  final int reasoningTokens;

  /// 本轮是否收到过任何 provider usage 统计。
  final bool usageReported;

  /// usage 中是否出现过缓存统计字段（区别于“返回了 0 命中”）。
  final bool cacheStatsReported;
}

class ToolResultEvent extends AgentEvent {
  const ToolResultEvent(this.call, this.result,
      {this.metadata = const <String, dynamic>{}});
  final ToolCall call;
  final ToolResult result;
  final Map<String, dynamic> metadata;
}

/// 管线发往执行器事件流的一条事件；[delivered] 在消费方处理完毕后完成。
final class _ToolEmission {
  _ToolEmission(this.event);

  final AgentEvent event;
  final delivered = Completer<void>();
}
