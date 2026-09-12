part of 'chat_controller.dart';

/// 「一次运行」的执行实现 —— 从 ChatController 整块搬出的主体（A-1 第 1 步）。
///
/// 为什么用 extension + part 而不是独立类：Dart 的私有性是**库级**的，part 文件
/// 与宿主同属一个库，因此主体里对 `_currentState`、`_persistMessage`、`_withMessageAt`
/// 等宿主私有成员的引用**无需任何改写**，搬迁前后是可审的整块移动（`git diff
/// --color-moved` 可见），不会把"搬家"变成"重写 700 行"。
///
/// 升级路径：等 A-1 后续步骤把宿主私有成员抽象成显式端口后，本 extension 可以
/// 再提升为持有 `RunHost` 的独立类；届时才需要引入接口与适配层。
/// 流式节流（70ms / 24 字符）与预算暂停上下文同样在这里消费。
extension ChatRunExecution on ChatController {
  Future<void> _runAgent(
    int assistantIndex,
    String model,
    ProviderConfig config,
    ToolRegistry registry,
    int maxSteps,
    double temperature,
    int maxTokens,
    double topP,
    ReasoningEffort reasoningEffort,
    ToolApprovalCallback approveTool,
    String? taskId,
    int runGeneration,
    String? runConversationId, {
    /// 预算暂停后从断点续跑时传入的 Agent 内部上下文；为空则沿用会话消息。
    List<ChatMessage>? resumeContext,
  }) async {
    if (!_runs.ownsRun(runGeneration, runConversationId)) return;
    _activePlanGeneration = runGeneration;
    final runHistory = resumeContext ??
        List<ChatMessage>.of(_currentState.messages.take(assistantIndex));
    final runPlanMode = _currentState.planMode;
    final runApprovalMode = _currentState.approvalMode;
    final runSystemPrompt = _currentState.systemPrompt;
    final sessionSkillInstructions = _currentState.sessionSkillInstructions;
    bool ownsRun() => _runs.ownsRun(runGeneration, runConversationId);
    final runId = UniqueId.generate('run');
    final logService = ref.read(logServiceProvider);
    final runStartedAt = DateTime.now();
    var eventSequence = 0;
    var runStatus = 'running';
    Map<String, dynamic>? runCheckpoint;
    var retryCount = 0;
    var foregroundStarted = false;
    RunEventTracker? tracker;
    try {
      final database = await ref.read(databaseProvider.future);
      await database.insertRunRecord(RunRecordsCompanion.insert(
        runId: runId,
        conversationId: runConversationId ?? 'unknown',
        model: Value(model),
        status: const Value('running'),
        startedAt: runStartedAt,
      ));
      tracker = RunEventTracker(database: database, runId: runId);
    } catch (_) {}
    RunEventHandle? modelEvent;
    final toolEvents = <String, RunEventHandle?>{};
    RunEventHandle? activeNetworkEvent;
    var networkSequence = 0;
    void syncEventCount() {
      final currentTracker = tracker;
      if (currentTracker != null) eventSequence = currentTracker.nextSequence;
    }

    Future<void> recordRunEvent({
      required String type,
      required String name,
      required String status,
      String? outputSummary,
      Map<String, dynamic>? metadata,
    }) async {
      final currentTracker = tracker;
      if (currentTracker == null) return;
      if (type == 'model_request' && status == 'started') {
        modelEvent = await currentTracker.start(
            type: type, name: name, metadata: metadata);
      } else if (type == 'tool_call' && outputSummary != null) {
        // Tool calls are started on ToolRequestedEvent and completed on
        // ToolResultEvent so their duration covers the actual execution.
        return;
      } else {
        await currentTracker.record(
          type: type,
          name: name,
          status: status,
          outputSummary: outputSummary,
          metadata: metadata,
        );
      }
      eventSequence = currentTracker.nextSequence;
    }

    try {
      foregroundStarted = await ForegroundService.instance
          .start(text: 'Agent 任务执行中')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // 前台服务不可用时仍允许当前回合继续，但不宣称锁屏可靠。
    }
    await logService.info('Agent 开始执行',
        runId: runId, category: 'system', detail: {'model': model});
    final provider =
        config.isConfigured ? _buildProvider(config) : DemoProvider();
    final executor = AgentExecutor(provider: provider, tools: registry);
    final retrySettings = ref.read(agentRetrySettingsProvider);
    final cancellationToken = AgentCancellationToken();
    final dioCancelToken = CancelToken();
    final runController = AgentRunController(
      onCancel: () => dioCancelToken.cancel(),
    );
    _runs.cancellationToken = cancellationToken;
    _runs.dioCancelToken = dioCancelToken;
    _runs.runController = runController;
    final answer = StringBuffer();
    final reasoning = StringBuffer();
    var usage = const Usage();
    int? estimatedCostCents;
    int? savedCostCents;
    final stopwatch = Stopwatch()..start();
    Duration? ttft;
    int? firstTokenDurationMs;
    // 思考过程计时：首个 ReasoningEvent → 首个 TextEvent。
    DateTime? reasoningStartedAt;
    Duration? reasoningDuration;
    DateTime? firstOutputAt;
    DateTime? lastOutputAt;
    var maxStallDurationMs = 0;
    var stallCount = 0;
    // 流式节流：文本和 reasoning 共用一个刷新调度器，避免推理模型的
    // reasoning 增量绕过节流、频繁重建整个消息列表。
    const flushInterval = Duration(milliseconds: 70);
    const flushMinUnits = 24;
    const contextEstimateInterval = Duration(milliseconds: 250);
    var lastFlush = DateTime.now();
    var lastFlushedUnits = 0;
    var lastContextEstimate = DateTime.fromMillisecondsSinceEpoch(0);
    Timer? flushTimer;

    void flushAnswer({bool force = false}) {
      if (!ownsRun() || assistantIndex >= _currentState.messages.length) return;
      final now = DateTime.now();
      lastFlush = now;
      lastFlushedUnits = answer.length + reasoning.length;
      final message = ChatMessage(
        role: MessageRole.assistant,
        parts: [MessagePart.text(answer.toString())],
        reasoning: reasoning.isEmpty ? null : reasoning.toString(),
        reasoningDuration: reasoningDuration,
      );
      final liveReply = LiveReply(
        messageIndex: assistantIndex,
        text: answer.toString(),
        reasoning: reasoning.isEmpty ? null : reasoning.toString(),
      );
      final estimateContext = force ||
          now.difference(lastContextEstimate) >= contextEstimateInterval;
      if (estimateContext) lastContextEstimate = now;
      _currentState = _currentState.copyWith(
        liveReply: liveReply,
        liveContextTokens: estimateContext
            ? _estimateLiveContextTokens(assistantIndex, message)
            : _currentState.liveContextTokens,
      );
    }

    void requestFlush({bool force = false}) {
      if (!ownsRun()) return;
      final now = DateTime.now();
      final elapsed = now.difference(lastFlush);
      final pendingUnits = answer.length + reasoning.length - lastFlushedUnits;
      if (force ||
          (elapsed >= flushInterval && pendingUnits >= flushMinUnits)) {
        flushTimer?.cancel();
        flushTimer = null;
        flushAnswer(force: force);
        return;
      }
      if (flushTimer != null) return;
      final remaining =
          elapsed >= flushInterval ? Duration.zero : flushInterval - elapsed;
      flushTimer = Timer(remaining, () {
        flushTimer = null;
        if (ownsRun() && answer.length + reasoning.length > lastFlushedUnits) {
          flushAnswer();
        }
      });
    }

    // 注入长期记忆与知识库片段，让交互式聊天也能享受记忆/RAG 能力（与
    // HeadlessExecutor 的后台路径保持一致）。注入失败不阻断执行。
    String baseSystemPrompt = runSystemPrompt;
    try {
      final database = await ref.read(databaseProvider.future);
      final memoryBlock = await MemoryService()
          .buildInjectionBlock(database, contextTokens: config.contextTokens);
      if (memoryBlock.isNotEmpty) {
        baseSystemPrompt = '$memoryBlock\n$baseSystemPrompt';
      }
      final userQuery = _lastUserText(assistantIndex);
      final knowledgeBlock =
          await KnowledgeService().buildInjectionBlock(database, userQuery);
      if (knowledgeBlock.isNotEmpty) {
        baseSystemPrompt = '$knowledgeBlock\n$baseSystemPrompt';
      }
      final skillBlock = await SkillStore().buildInjectionBlock(database);
      if (skillBlock.isNotEmpty) {
        baseSystemPrompt = '$skillBlock\n$baseSystemPrompt';
      }
      if (sessionSkillInstructions.isNotEmpty) {
        baseSystemPrompt =
            '${sessionSkillInstructions.map((item) => item.content).join('\n\n')}\n$baseSystemPrompt';
      }
    } catch (_) {}

    // 委派规则：向主 Agent 注入使用 sub_agent 的边界与预算约束。
    try {
      final autonomousDelegation =
          await AutonomousDelegationService().isEnabled();
      baseSystemPrompt =
          '$baseSystemPrompt\n\n${ChatController._delegationRules(autonomousDelegation)}';
    } catch (_) {}

    try {
      final trustStore = await ref.read(toolTrustStoreProvider.future);
      await for (final event in executor.run(
        history: runHistory,
        model: model,
        confirmPlan: runPlanMode ? _confirmPlan : null,
        approveTool: approveTool,
        approvalMode: runApprovalMode,
        isToolTrusted: trustStore.isTrusted,
        systemPrompt: runPlanMode
            ? '$baseSystemPrompt\n\n[计划模式] 你的首个回复必须调用 manage_plan 工具来生成详细的 JSON 分步执行计划。在用户确认计划之前，不要调用其他工具。'
            : baseSystemPrompt,
        capabilities: ModelCapabilities.infer(model),
        maxSteps: maxSteps,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        reasoningEffort: reasoningEffort,
        contextBudgetTokens: config.contextTokens,
        maxRetries: retrySettings.maxRetries,
        retryBackoff: retrySettings.retryBackoff,
        cancellationToken: cancellationToken,
        cancelToken: dioCancelToken,
        runController: runController,
      )) {
        if (event is AgentStatusEvent &&
            event.status == RunStatus.waitingModel) {
          await tracker?.finish(modelEvent, status: 'success');
          modelEvent = await tracker?.start(
            type: 'model_request',
            name: '模型请求',
            metadata: {'attempt': networkSequence + 1},
          );
          networkSequence++;
          activeNetworkEvent = await tracker?.start(
            type: 'network',
            name: '模型网络请求',
            metadata: {'attempt': networkSequence},
          );
          syncEventCount();
          if (ownsRun()) {
            // agent 循环每迭代一步都会先进入 waitingModel，这里累计步数。
            _currentState = _currentState.copyWith(
                totalSteps: _currentState.totalSteps + 1);
          }
        } else if (event is TextEvent) {
          if (reasoningStartedAt != null && reasoningDuration == null) {
            reasoningDuration = DateTime.now().difference(reasoningStartedAt);
          }
          final firstTokenElapsed = stopwatch.elapsed;
          ttft ??= firstTokenElapsed;
          firstTokenDurationMs ??= firstTokenElapsed.inMilliseconds;
          final now = DateTime.now();
          firstOutputAt ??= now;
          if (lastOutputAt != null) {
            final stallMs = now.difference(lastOutputAt).inMilliseconds;
            if (stallMs > 300) {
              stallCount++;
              maxStallDurationMs = math.max(maxStallDurationMs, stallMs);
            }
          }
          lastOutputAt = now;
          answer.write(event.text);
          requestFlush();
        } else if (event is ReasoningEvent) {
          reasoningStartedAt ??= DateTime.now();
          final firstTokenElapsed = stopwatch.elapsed;
          ttft ??= firstTokenElapsed;
          firstTokenDurationMs ??= firstTokenElapsed.inMilliseconds;
          final now = DateTime.now();
          firstOutputAt ??= now;
          if (lastOutputAt != null) {
            final stallMs = now.difference(lastOutputAt).inMilliseconds;
            if (stallMs > 300) {
              stallCount++;
              maxStallDurationMs = math.max(maxStallDurationMs, stallMs);
            }
          }
          lastOutputAt = now;
          reasoning.write(event.text);
          requestFlush();
        } else if (event is AgentUsageEvent) {
          usage = Usage(
              promptTokens: event.promptTokens,
              completionTokens: event.completionTokens,
              cachedTokens: event.cachedTokens);
          if (ownsRun() && assistantIndex < _currentState.messages.length) {
            final current = _currentState.messages[assistantIndex];
            _currentState = _withMessageAt(
              _currentState,
              assistantIndex,
              current.copyWith(usage: usage),
            ).copyWith(
                liveContextTokens: usage.promptTokens + usage.completionTokens);
          }
          final estimate = _estimateUsageCost(config, usage);
          estimatedCostCents = estimate.costCents;
          savedCostCents = estimate.savedCostCents;
        } else if (event is AgentErrorEvent) {
          runStatus = 'failed';
          await tracker?.finish(activeNetworkEvent,
              status: 'failed', outputSummary: event.message);
          await tracker?.finish(modelEvent,
              status: 'failed', outputSummary: event.message);
          activeNetworkEvent = null;
          modelEvent = null;
          for (final handle in toolEvents.values) {
            await tracker?.finish(handle,
                status: 'failed', outputSummary: event.message);
          }
          toolEvents.clear();
          answer.write('\n\n${formatErrorForMessage(event.message)}');
          await recordRunEvent(
              type: 'error',
              name: 'Agent 错误',
              status: 'failed',
              outputSummary: event.message);
          await logService.error('Agent 执行失败',
              runId: runId,
              category: 'model',
              errorCode: 'AGENT_EXECUTION_FAILED',
              retryable: event.retryable,
              detail: {
                'message': event.message,
                if (event.failureKind != null) 'failureKind': event.failureKind,
                if (event.statusCode != null) 'statusCode': event.statusCode,
              });
        } else if (event is AgentBudgetExhaustedEvent) {
          // 达到 maxSteps：可恢复的预算暂停，不是失败。保存续跑上下文与原因。
          runStatus = 'paused';
          _runs.budgetPauseContext = List<ChatMessage>.of(event.context);
          runCheckpoint = {
            'version': 1,
            'runId': runId,
            'context': encodeChatContextForPersistence(event.context),
            'maxSteps': event.maxSteps,
            'reason': event.message,
          };
          await tracker?.finish(activeNetworkEvent,
              status: 'success', outputSummary: event.message);
          await tracker?.finish(modelEvent,
              status: 'success', outputSummary: event.message);
          activeNetworkEvent = null;
          modelEvent = null;
          answer.write('\n\n${formatErrorForMessage(event.message)}');
          await recordRunEvent(
              type: 'budget',
              name: '执行预算已耗尽',
              status: 'paused',
              outputSummary: event.message,
              metadata: {'maxSteps': event.maxSteps});
          await logService.warning('Agent 达到执行步数预算，已暂停可续跑',
              runId: runId,
              category: 'budget',
              detail: {'maxSteps': event.maxSteps});
        } else if (event is AgentRetryEvent) {
          retryCount = event.attempt;
          await tracker?.finish(activeNetworkEvent,
              status: 'failed', metadata: {'attempt': event.attempt});
          await tracker?.finish(modelEvent,
              status: 'failed', metadata: {'attempt': event.attempt});
          activeNetworkEvent = null;
          modelEvent = null;
          networkSequence++;
          modelEvent = await tracker?.start(
            type: 'model_request',
            name: '模型请求重试',
            metadata: {'attempt': event.attempt + 1},
          );
          activeNetworkEvent = await tracker?.start(
            type: 'network',
            name: '模型网络请求重试',
            metadata: {'attempt': event.attempt + 1},
          );
          syncEventCount();
          await logService.warning('模型请求将重试',
              runId: runId,
              category: 'network',
              detail: {'attempt': event.attempt});
        } else if (event is ToolRequestedEvent) {
          if (!ownsRun()) continue;
          final risk = _riskFor(registry, event.call.name);
          // The provider response is complete once tool calls are emitted;
          // keep network latency separate from the tool execution duration.
          await tracker?.finish(activeNetworkEvent, status: 'success');
          await tracker?.finish(modelEvent, status: 'success');
          activeNetworkEvent = null;
          modelEvent = null;
          toolEvents[event.call.id] = await tracker?.start(
            type: _isFileOperationTool(event.call.name)
                ? 'file_operation'
                : 'tool_call',
            name: event.call.name,
            inputSummary: jsonEncode(SensitiveToolPolicy.redactArguments(
                event.call.name, event.call.arguments)),
            metadata: {
              'tool': event.call.name,
              // path / newPath 是**参数**，参数敏感时不落审计。
              if (!SensitiveToolPolicy.isArgumentSensitive(event.call.name))
                'path': event.call.arguments['path'],
              if (!SensitiveToolPolicy.isArgumentSensitive(event.call.name) &&
                  event.call.arguments['newPath'] != null)
                'newPath': event.call.arguments['newPath'],
            },
          );
          syncEventCount();
          if (ownsRun()) await _persistToolCall(event.call, risk);
          if (!ownsRun()) continue;
          _currentState = _currentState.copyWith(
            activityLog: [..._currentState.activityLog, '等待确认'],
            toolActivities: [
              ..._currentState.toolActivities,
              ToolActivity(call: event.call, risk: risk)
            ],
          );
        } else if (event is AgentStatusEvent &&
            event.status == RunStatus.executingTool) {
          if (!ownsRun()) continue;
          if (_currentState.toolActivities.isEmpty ||
              _currentState.toolActivities.last.call.name != 'manage_plan') {
            _updatePlanStepStatus('running');
          }
          _currentState = _currentState.copyWith(
            activityLog: [..._currentState.activityLog, '等待确认'],
            toolActivities: _updateLastToolActivity(
                _currentState.toolActivities,
                status: '执行中'),
          );
        } else if (event is ApprovalRequiredEvent) {
          if (!ownsRun()) continue;
          _currentState = _currentState.copyWith(
            activityLog: [..._currentState.activityLog, '等待确认'],
            toolActivities: _updateToolActivity(
                _currentState.toolActivities, event.call.id,
                status: '等待确认'),
          );
          if (taskId != null) {
            final taskDb = await ref.read(databaseProvider.future);
            await TaskService()
                .updateStatus(taskDb, taskId, 'waiting_approval');
          }
          await NotificationService.instance.init();
          await NotificationService.instance.show(
            id: event.call.id.hashCode & 0x7fffffff,
            title: '开发任务等待审批',
            body: '需要确认工具：${event.call.name}',
            payload: 'conversation:${_currentState.conversationId ?? ''}',
          );
        } else if (event is ToolResultEvent) {
          if (!ownsRun()) continue;
          if (taskId != null) {
            final taskDb = await ref.read(databaseProvider.future);
            await TaskService().updateStatus(taskDb, taskId, 'running');
          }
          final toolFailed = !event.result.ok;
          final auditMetadata = <String, dynamic>{
            ...event.metadata,
            'tool': event.call.name,
            'effect': event.result.effect.name,
            'toolCode': event.result.code,
            'fileOperation': _isFileOperationTool(event.call.name),
            if (!SensitiveToolPolicy.isArgumentSensitive(event.call.name) &&
                event.call.arguments['path'] != null)
              'path': event.call.arguments['path'],
            if (_isFileOperationTool(event.call.name) &&
                !event.metadata.containsKey('operation'))
              'operation': event.call.name,
          };
          final toolHandle = toolEvents.remove(event.call.id);
          await tracker?.finish(
            toolHandle,
            status: toolFailed ? 'failed' : 'success',
            outputSummary: SensitiveToolPolicy.redactResultText(
                event.call.name, event.result.display),
            metadata: auditMetadata,
          );
          // 正常路径只有一条 started→finished 事件，避免审计页把同一次
          // 工具调用显示成两条。若启动事件因数据库瞬态失败而不存在，
          // 才补写一条完整记录，保证审计仍然可见。
          if (toolHandle == null) {
            await recordRunEvent(
              type: _isFileOperationTool(event.call.name)
                  ? 'file_operation'
                  : 'tool_call',
              name: event.call.name,
              status: toolFailed ? 'failed' : 'success',
              outputSummary: SensitiveToolPolicy.redactResultText(
                  event.call.name, event.result.display),
              metadata: auditMetadata,
            );
          }
          await logService
              .info('工具执行完成', runId: runId, category: 'tool', detail: {
            'tool': event.call.name,
            'success': !toolFailed,
          });
          if (event.call.name != 'manage_plan') {
            _updatePlanStepStatus(toolFailed ? 'failed' : 'completed');
          }
          if (ownsRun()) {
            await _persistMessage(
                ChatMessage(
                    role: MessageRole.tool,
                    toolCallId: event.call.id,
                    parts: [MessagePart.text(event.result.encode())]),
                toolName: event.call.name,
                toolResult: event.result);
          }
          _currentState = _currentState.copyWith(
            toolActivities: _updateToolActivity(
              _currentState.toolActivities,
              event.call.id,
              status: toolFailed ? '执行失败' : '已完成',
              result: event.result.display,
              ok: event.result.ok,
              code: event.result.code,
              effect: event.result.effect,
            ),
          );
        }
        if (event is AgentStatusEvent) {
          if (event.status == RunStatus.paused && ownsRun()) {
            runStatus = 'paused';
            _currentState = _currentState.copyWith(paused: true);
          }
          if (event.status == RunStatus.cancelled) {
            runStatus = 'cancelled';
            await tracker?.finish(activeNetworkEvent, status: 'cancelled');
            await tracker?.finish(modelEvent, status: 'cancelled');
            activeNetworkEvent = null;
            modelEvent = null;
            for (final handle in toolEvents.values) {
              await tracker?.finish(handle, status: 'cancelled');
            }
            toolEvents.clear();
          }
          if (event.status == RunStatus.completed) {
            runStatus = 'success';
            final usageMetadata = {
              'promptTokens': usage.promptTokens,
              'completionTokens': usage.completionTokens,
              'cachedTokens': usage.cachedTokens,
              'cacheHit': usage.cachedTokens > 0,
              'cacheSource': usage.cachedTokens > 0 ? 'provider-usage' : null,
              'savedTokens': usage.cachedTokens,
              'savedCostCents': savedCostCents,
              'estimatedCostCents': estimatedCostCents,
            };
            await tracker?.finish(activeNetworkEvent,
                status: 'success', metadata: usageMetadata);
            await tracker?.finish(modelEvent,
                status: 'success', metadata: usageMetadata);
            activeNetworkEvent = null;
            modelEvent = null;
          }
        }
      }
    } catch (error) {
      // 兜底：任何未预期异常（DB 写入失败、附件解析、审批回调等）都不能让
      // UI 永久停留在"运行中"。写入错误信息并恢复可交互状态。
      runStatus = 'failed';
      await tracker?.finish(activeNetworkEvent,
          status: 'failed', outputSummary: error.toString());
      await tracker?.finish(modelEvent,
          status: 'failed', outputSummary: error.toString());
      for (final handle in toolEvents.values) {
        await tracker?.finish(handle,
            status: 'failed', outputSummary: error.toString());
      }
      activeNetworkEvent = null;
      modelEvent = null;
      toolEvents.clear();
      answer.write('\n\n${formatErrorForMessage(error.toString())}');
      await logService.error('Agent 未预期异常',
          runId: runId,
          category: 'system',
          errorCode: 'AGENT_UNEXPECTED_ERROR',
          error: error,
          stackTrace: StackTrace.current);
    } finally {
      flushTimer?.cancel();
      flushTimer = null;
      stopwatch.stop();
      try {
        final runDb = await ref.read(databaseProvider.future);
        if (_runs.wasCancelled(runGeneration)) {
          runStatus = 'cancelled';
        }
        if (runStatus == 'running') runStatus = 'failed';
        try {
          if (activeNetworkEvent != null) {
            await tracker?.finish(activeNetworkEvent,
                status: runStatus == 'cancelled' ? 'cancelled' : 'failed');
            activeNetworkEvent = null;
          }
          if (modelEvent != null) {
            await tracker?.finish(modelEvent,
                status: runStatus == 'cancelled' ? 'cancelled' : 'failed');
            modelEvent = null;
          }
          if (toolEvents.isNotEmpty) {
            final status = runStatus == 'cancelled' ? 'cancelled' : 'failed';
            for (final handle in toolEvents.values) {
              await tracker?.finish(handle, status: status);
            }
            toolEvents.clear();
          }
          await tracker?.flush();
          await logService.flush();
        } catch (_) {}
        final cancelDurationMs =
            runStatus == 'cancelled' && _cancelRequestedAt != null
                ? DateTime.now().difference(_cancelRequestedAt!).inMilliseconds
                : null;
        final outputRateMilli =
            usage.completionTokens > 0 && firstOutputAt != null
                ? (usage.completionTokens *
                        1000000 /
                        math.max(
                            1,
                            DateTime.now()
                                .difference(firstOutputAt)
                                .inMilliseconds))
                    .round()
                : null;
        final terminalRecord = RunRecordsCompanion.insert(
          runId: runId,
          conversationId: runConversationId ?? 'unknown',
          model: Value(model),
          status: Value(runStatus),
          startedAt: runStartedAt,
          endedAt: Value(DateTime.now()),
          inputTokens: Value(usage.promptTokens),
          outputTokens: Value(usage.completionTokens),
          cachedTokens: Value(usage.cachedTokens),
          estimatedCostCents: Value(estimatedCostCents),
          eventCount: Value(eventSequence),
          totalDurationMs: Value(stopwatch.elapsedMilliseconds),
          retryCount: Value(retryCount),
          firstTokenDurationMs: Value(firstTokenDurationMs),
          outputRateMilli: Value(outputRateMilli),
          maxStallDurationMs: Value(maxStallDurationMs),
          stallCount: Value(stallCount),
          cancelDurationMs: Value(cancelDurationMs),
        );
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            await runDb.insertRunRecord(terminalRecord);
            break;
          } catch (_) {
            if (attempt == 2) rethrow;
            await Future<void>.delayed(Duration(milliseconds: 20 << attempt));
          }
        }
        try {
          await runDb.pruneRunRecords();
        } catch (_) {}
      } catch (_) {}
    }
    final assistantMessage = ChatMessage(
      role: MessageRole.assistant,
      parts: [MessagePart.text(answer.toString())],
      reasoning: reasoning.isEmpty ? null : reasoning.toString(),
      modelName: config.isConfigured ? config.model : '演示模型',
      usage: usage.totalTokens > 0 ? usage : null,
      elapsed: stopwatch.elapsed,
      ttft: ttft,
    );
    final runCancelled =
        _runs.wasCancelled(runGeneration) || runStatus == 'cancelled';
    // 计划收敛不依赖 ownsRun()：即使运行代次已失效（会话切换 / 中断 / 取消），
    // 也要对当前会话 planState 执行一次终态收敛与步骤归一化，
    // 避免 plan.status 残留 executing 导致“计划一直显示正在运行”。
    // 切换会话时 planState 会被清空（newConversation / switchConversation 均带
    // clearPlanState: true），因此外提不会污染其他会话的计划状态。
    _convergePlanToTerminal(runStatus: runStatus, cancelled: runCancelled);
    if (ownsRun()) {
      if (assistantIndex < _currentState.messages.length) {
        _currentState =
            _withMessageAt(_currentState, assistantIndex, assistantMessage)
                .copyWith(
          running: false,
          clearLiveReply: true,
          liveContextTokens: usage.totalTokens > 0
              ? usage.totalTokens
              : _estimateLiveContextTokens(assistantIndex, assistantMessage),
        );
      } else {
        _currentState = _currentState.copyWith(
            running: false, paused: false, clearLiveReply: true);
      }
      try {
        await _persistMessage(assistantMessage);
      } catch (_) {
        // 持久化失败不阻断 UI 恢复。
      }
    }
    if (taskId != null) {
      try {
        final taskDb = await ref.read(databaseProvider.future);
        final taskService = TaskService();
        final status = runCancelled
            ? 'cancelled'
            : runStatus == 'success'
                ? 'completed'
                : runStatus == 'paused'
                    ? 'paused'
                    : 'failed';
        await taskService.complete(
          taskDb,
          taskId,
          status: status,
          summary: answer.toString(),
          runId: runId,
          checkpoint: status == 'paused' ? runCheckpoint : null,
        );
        await NotificationService.instance.init();
        await NotificationService.instance.show(
          id: taskId.hashCode & 0x7fffffff,
          title: status == 'completed'
              ? '开发任务已完成'
              : (status == 'paused' ? '开发任务已暂停' : '开发任务未完成'),
          body: _notificationPreview(answer.toString(), status),
          payload: 'task:$taskId',
        );
      } catch (_) {}
    }
    if (foregroundStarted) {
      await ForegroundService.instance.stop();
    }
    if (_activePlanGeneration == runGeneration) {
      _activePlanGeneration = null;
    }
    _runs.clearCancellationTokenIf(cancellationToken);
    _runs.clearDioCancelTokenIf(dioCancelToken);
    runController.seal();
    _runs.clearRunControllerIf(runController);
    _runs.forget(runGeneration);
    _cancelRequestedAt = null;
    // 完成或取消后清除续跑上下文，避免残留一个旧的暂停快照。
    if (runStatus == 'success' || runStatus == 'cancelled') {
      _runs.budgetPauseContext = null;
    }
  }
}
