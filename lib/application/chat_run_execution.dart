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
    // Capture the run's anchor before any await or conversation switch.
    final assistantMessageId = assistantIndex < _currentState.messages.length
        ? _currentState.messages[assistantIndex].id ??
            UniqueId.generate('message')
        : UniqueId.generate('message');
    final deviceAuditUserRequest =
        assistantIndex >= 0 && assistantIndex <= _currentState.messages.length
            ? _lastUserText(assistantIndex)
            : '';
    _activePlanGeneration = runGeneration;
    var runHistory = resumeContext ??
        List<ChatMessage>.of(_currentState.messages.take(assistantIndex));
    final runPlanMode = _currentState.planMode;
    final runApprovalMode = _currentState.approvalMode;
    final runSystemPrompt = _currentState.systemPrompt;
    final sessionSkillInstructions = _currentState.sessionSkillInstructions;
    bool ownsRun() => _runs.ownsRun(runGeneration, runConversationId);
    bool visible() => _runs.isVisible(runConversationId);
    final runId = UniqueId.generate('run');
    _runs.activeRunId = runId;
    _runs.boundConversationId ??= runConversationId;
    if (visible()) {
      _currentState = _currentState.copyWith(currentRunId: runId);
    }
    final logService = _ref.read(logServiceProvider);
    final runStartedAt = DateTime.now();
    _setRunProgress(
      runGeneration: runGeneration,
      conversationId: runConversationId,
      stage: ChatRunStage.preparing,
      label: '正在准备任务',
    );
    var eventSequence = 0;
    var runStatus = 'running';
    Map<String, dynamic>? runCheckpoint;
    var retryCount = 0;
    var foregroundStarted = false;
    RunEventTracker? tracker;
    SessionRecorder? sessionRecorder;
    try {
      final database = await _ref.read(databaseProvider.future);
      await database.insertRunRecord(RunRecordsCompanion.insert(
        runId: runId,
        conversationId: runConversationId ?? 'unknown',
        taskId: Value(taskId),
        projectId: Value(_currentState.currentProjectId),
        model: Value(model),
        status: const Value('running'),
        startedAt: runStartedAt,
      ));
      tracker = RunEventTracker(database: database, runId: runId);
      // 会话日志（阶段 1 双写）：记录模型每次请求真正看到的消息，
      // 失败只降级上报，不影响本轮运行。
      if (SessionLogSettings.dualWrite && runConversationId != null) {
        sessionRecorder = SessionRecorder(
          store: DriftSessionEventStore(database),
          conversationId: runConversationId,
          runId: runId,
          model: model,
          onError: (error, stackTrace) => NexusGuard.degradeCaught(
              'chat.sessionLog', error, stackTrace,
              logger: _logDegrade),
        )..start();
      }
    } catch (_) {
      unawaited(logService.warning(
        'Run record initialization failed',
        runId: runId,
        category: 'run_persistence',
      ));
    }
    RunEventHandle? modelEvent;
    final toolEvents = <String, RunEventHandle?>{};
    // 设备操作审计需要执行耗时；按工具调用 ID 记录开始时间。
    final toolStartedAt = <String, DateTime>{};
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
      foregroundStarted =
          await ForegroundService.instance.start(text: 'Agent 任务执行中');
    } catch (error) {
      // 前台服务不可用时仍允许当前回合继续，但不宣称锁屏可靠。
      unawaited(logService.warning(
        'Foreground execution service unavailable',
        runId: runId,
        category: 'run_lifecycle',
        detail: {'errorType': error.runtimeType.toString()},
      ));
    }
    await logService.info('Agent 开始执行',
        runId: runId, category: 'system', detail: {'model': model});
    final provider =
        config.isConfigured ? createLlmProvider(config) : DemoProvider();
    final executor = AgentExecutor(
      provider: provider,
      tools: registry,
      // 写/改/删/移文件前按任务保存原始内容，供任务变更集精确回退。
      toolPipeline: fileBaselinePipeline(
        taskId: taskId,
        workspacePath: _currentState.currentWorkspacePath,
        onError: (error, stackTrace) => NexusGuard.degradeCaught(
            'chat.fileBaseline', error, stackTrace,
            logger: _logDegrade),
      ),
    );
    final retrySettings = _ref.read(agentRetrySettingsProvider);
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
    var timing = TimingSnapshot.empty;
    DateTime? modelStartedAt;
    DateTime? firstModelTokenAt;
    DateTime? timingReasoningStartedAt;
    DateTime? firstTextStartedAt;
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
    var lastProgressCharacters = 0;
    var lastProgressReportAt = DateTime.fromMillisecondsSinceEpoch(0);
    Timer? flushTimer;

    void publishTiming() {
      if (!ownsRun() || !visible()) return;
      _currentState = _currentState.copyWith(
        timingSnapshot: timing.copyWith(wallMs: stopwatch.elapsedMilliseconds),
      );
    }

    void finishModelTiming([DateTime? endedAt]) {
      final startedAt = modelStartedAt;
      if (startedAt == null) return;
      final ended = endedAt ?? DateTime.now();
      final firstToken = firstModelTokenAt;
      final waitMs = firstToken == null
          ? ended.difference(startedAt).inMilliseconds
          : firstToken.difference(startedAt).inMilliseconds;
      final reasoningStarted = timingReasoningStartedAt;
      final firstText = firstTextStartedAt;
      final reasoningEnd = firstText ?? ended;
      final reasoningMs = reasoningStarted == null
          ? 0
          : reasoningEnd.difference(reasoningStarted).inMilliseconds;
      final outputMs =
          firstText == null ? 0 : ended.difference(firstText).inMilliseconds;
      timing = timing.copyWith(
        modelWaitMs: timing.modelWaitMs + (waitMs < 0 ? 0 : waitMs),
        reasoningMs: timing.reasoningMs + (reasoningMs < 0 ? 0 : reasoningMs),
        outputMs: timing.outputMs + (outputMs < 0 ? 0 : outputMs),
      );
      modelStartedAt = null;
      firstModelTokenAt = null;
      timingReasoningStartedAt = null;
      firstTextStartedAt = null;
      publishTiming();
    }

    void beginModelTiming() {
      finishModelTiming();
      modelStartedAt = DateTime.now();
      timing = timing.copyWith(modelCalls: timing.modelCalls + 1);
      publishTiming();
    }

    void reportGeneratedProgress({
      required ChatRunStage stage,
      required String label,
    }) {
      final totalCharacters = answer.length + reasoning.length;
      final now = DateTime.now();
      if (totalCharacters == lastProgressCharacters &&
          now.difference(lastProgressReportAt) < const Duration(seconds: 1)) {
        return;
      }
      if (totalCharacters - lastProgressCharacters < 24 &&
          now.difference(lastProgressReportAt) < const Duration(seconds: 1)) {
        return;
      }
      lastProgressCharacters = totalCharacters;
      lastProgressReportAt = now;
      _setRunProgress(
        runGeneration: runGeneration,
        conversationId: runConversationId,
        stage: stage,
        label: label,
        generatedCharacters: totalCharacters,
      );
    }

    void flushAnswer({bool force = false}) {
      if (!ownsRun() ||
          !visible() ||
          assistantIndex >= _currentState.messages.length) {
        return;
      }
      final now = DateTime.now();
      lastFlush = now;
      lastFlushedUnits = answer.length + reasoning.length;
      // StringBuffer.toString() copies the accumulated text. Keep one snapshot
      // per buffer and only build ChatMessage when the context estimate is due.
      final answerText = answer.toString();
      final reasoningText = reasoning.isEmpty ? '' : reasoning.toString();
      final estimateContext = force ||
          now.difference(lastContextEstimate) >= contextEstimateInterval;
      if (estimateContext) lastContextEstimate = now;
      final message = estimateContext
          ? ChatMessage(
              role: MessageRole.assistant,
              parts: [MessagePart.text(answerText)],
              reasoning: reasoningText.isEmpty ? null : reasoningText,
              reasoningDuration: reasoningDuration,
            )
          : null;
      final liveReply = LiveReply(
        messageIndex: assistantIndex,
        text: answerText,
        reasoning: reasoningText.isEmpty ? null : reasoningText,
      );
      _currentState = _currentState.copyWith(
        liveReply: liveReply,
        liveContextTokens: estimateContext
            ? _estimateLiveContextTokens(assistantIndex, message!)
            : _currentState.liveContextTokens,
      );
    }

    void requestFlush({bool force = false}) {
      if (!ownsRun() || !visible()) return;
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
        if (ownsRun() &&
            visible() &&
            answer.length + reasoning.length > lastFlushedUnits) {
          flushAnswer();
        }
      });
    }

    // 注入长期记忆与知识库片段，让交互式聊天也能享受记忆/RAG 能力（与
    // HeadlessExecutor 的后台路径保持一致）。注入失败不阻断执行。
    // 拼装顺序由 assembleAgentSystemPrompt 固定为“稳定前缀在前、动态内容
    // 垫底”：知识库片段按当前问题检索、记忆带 revision，若排在人格/技能
    // 规则之前，每轮请求的前缀都会变化，Provider 的前缀缓存会全部失效。
    var skillIndexBlock = '';
    final sessionSkillTexts = <String>[];
    var memoryBlock = '';
    var knowledgeBlock = '';
    try {
      final database = await _ref.read(databaseProvider.future);
      // 普通聊天模式不装配工具；Agent 权限也可能明确关闭 Skill 工具。
      // 只有存在匹配的读取工具时才注入索引，避免提示词与能力不一致。
      if (_currentState.mode != ChatMode.chat &&
          registry.findExecutor('skills_read') != null) {
        skillIndexBlock = await SkillStore().buildInjectionBlock(database);
      }
      for (final instruction in sessionSkillInstructions) {
        final content = instruction.content.trim();
        if (content.isNotEmpty) sessionSkillTexts.add(content);
      }
      memoryBlock = await MemoryService().buildInjectionBlock(
        database,
        contextTokens: config.contextTokens,
        projectId: _currentState.currentProjectId,
      );
      knowledgeBlock = await KnowledgeService()
          .buildInjectionBlock(database, _lastUserText(assistantIndex));
    } catch (error) {
      unawaited(logService.warning(
        'Run context injection partially failed',
        runId: runId,
        category: 'run_context',
        detail: {'errorType': error.runtimeType.toString()},
      ));
    }

    // 委派规则：向主 Agent 注入使用 sub_agent 的边界与预算约束。
    var delegationRules = '';
    try {
      final autonomousDelegation =
          await AutonomousDelegationService().isEnabled();
      delegationRules = ChatController._delegationRules(autonomousDelegation);
    } catch (error) {
      unawaited(logService.warning(
        'Autonomous delegation settings unavailable',
        runId: runId,
        category: 'run_context',
        detail: {'errorType': error.runtimeType.toString()},
      ));
    }

    // 工作区与工具可用性：注册表是按工作区绑定动态装配的，模型必须知道自己
    // 有没有文件/终端能力；缺失时引导用户开启，而不是声称设备无法完成。
    final workspaceRules = ChatController.workspaceToolRules(
      workspacePath: _currentState.currentWorkspacePath,
      fileToolsAvailable: registry.findRegistration('write_file') != null,
      terminalAvailable: registry.findRegistration('terminal') != null,
      mode: _currentState.mode,
    );

    var taskTemplateRules = '';
    var projectContextBlock = '';
    PromptBudgetPlan? budgetPlan;
    try {
      final requestTaskType = taskId == null
          ? null
          : await () async {
              try {
                final database = await _ref.read(databaseProvider.future);
                final task = await database.findTask(taskId);
                if (task == null) return null;
                return TaskService().describe(task).type;
              } catch (_) {
                // 可忽略：任务类型只用于挑选提示词模板，取不到就退化成
                // 通用模板。外层 catch 已在整体失败时写 warning。
                return null;
              }
            }();
      ProjectKindDetection? project;
      final workspacePath = _currentState.currentWorkspacePath;
      if (workspacePath != null && workspacePath.trim().isNotEmpty) {
        project = await const ProjectKindDetector().detect(workspacePath);
      }
      taskTemplateRules = TaskTemplateService().promptBlock(
        taskType: requestTaskType,
        project: project,
      );
      final projectId = _currentState.currentProjectId;
      if (projectId != null &&
          workspacePath != null &&
          workspacePath.trim().isNotEmpty) {
        ProjectSettings settings = const ProjectSettings();
        TaskSummary? summary;
        try {
          final database = await _ref.read(databaseProvider.future);
          final row = await database.findProject(projectId);
          if (row != null) {
            settings = ProjectSettings.decode(row.settingsJson);
          }
          if (taskId != null) {
            final progress = await TaskService().progress(database, taskId);
            if (progress['taskSummary'] is Map) {
              summary = TaskSummary.fromJson(
                  Map<String, dynamic>.from(progress['taskSummary'] as Map));
            }
          }
        } catch (_) {
          // 可忽略（有意降级）：项目设置 / 任务摘要读失败时沿用默认
          // ProjectSettings 继续组装上下文，不阻断本轮对话。
          // 外层 catch（见下方 assemble 段）负责把整体失败记为 warning。
        }
        final query = _lastUserText(assistantIndex);
        var context = await const ProjectContextService().assemble(
          projectId: projectId,
          workspacePath: workspacePath,
          settings: settings,
          taskSummary: summary,
          citations: _currentState.pendingCitations,
          query: query,
        );
        budgetPlan = const PromptBudgetAllocator().allocate(
          contextTokens: config.contextTokens,
          systemPrompt: [
            runSystemPrompt,
            if (taskTemplateRules.isNotEmpty) taskTemplateRules,
            workspaceRules,
            memoryBlock,
            knowledgeBlock,
          ].join('\n\n'),
          tools: registry.manifests,
          history: _currentState.messages.take(assistantIndex).toList(),
          projectContext: context,
          reservedOutputTokens: maxTokens,
        );
        context = budgetPlan.projectContext;
        projectContextBlock = context.toPromptBlock();
        if (budgetPlan.omitted.isNotEmpty && visible()) {
          _currentState = _currentState.copyWith(
            omittedContext: budgetPlan.omitted,
            pendingCitations: context.citations,
          );
        }
      }
    } catch (error) {
      unawaited(logService.warning(
        'Project context assembly partially failed',
        runId: runId,
        category: 'run_context',
        detail: {'errorType': error.runtimeType.toString()},
      ));
    }

    _setRunProgress(
      runGeneration: runGeneration,
      conversationId: runConversationId,
      stage: ChatRunStage.analyzing,
      label: '正在分析需求',
    );
    final baseSystemPrompt = assembleAgentSystemPrompt(
      personaPrompt: [
        runSystemPrompt,
        if (taskTemplateRules.isNotEmpty) taskTemplateRules,
      ].where((section) => section.trim().isNotEmpty).join('\n\n'),
      skillIndexBlock: skillIndexBlock,
      sessionSkillBlocks: sessionSkillTexts,
      delegationRules: delegationRules,
      workspaceRules: workspaceRules,
      projectContextBlock: projectContextBlock,
      memoryBlock: memoryBlock,
      knowledgeBlock: knowledgeBlock,
    );

    try {
      final trustStore = await _ref.read(toolTrustStoreProvider.future);
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
        // 默认聊天：40 轮预算，最近有进展时自动续跑 2 次；选了 Agent 时尊重
        // 它自己设定的最大步数上限，不自动续跑。
        autoContinueLimit: _currentState.agentId == null ? 2 : 0,
        onRequest: sessionRecorder?.onRequest,
      )) {
        sessionRecorder?.observe(event);
        if (event is ContextSnapshotEvent) {
          final record = ContextStepRecord(
            step: event.step,
            snapshot: event.snapshot,
            startedAt: DateTime.now(),
            anchorMessageId: event.anchorMessageId,
          );
          if (ownsRun() && visible()) {
            _currentState = _currentState.copyWith(
              contextSnapshot: event.snapshot,
              contextSteps: [..._currentState.contextSteps, record],
              liveContextTokens: event.snapshot.usedTokens,
            );
          }
          await recordRunEvent(
            type: 'context_snapshot',
            name: '上下文快照',
            status: 'recorded',
            metadata: record.toJson(),
          );
        } else if (event is AgentContextCompressionEvent) {
          if (ownsRun()) {
            await _persistCompressionMarkers(
              runConversationId,
              event.toolCallIds,
            );
          }
          if (ownsRun() && visible()) {
            final ids = event.toolCallIds.toSet();
            _currentState = _currentState.copyWith(
              toolActivities: _currentState.toolActivities.map((activity) {
                if (!ids.contains(activity.call.id)) return activity;
                return activity.copyWith(
                  compressed: true,
                  originalResult: activity.result,
                );
              }).toList(growable: false),
            );
          }
          await recordRunEvent(
            type: 'context_compress',
            name: '用户确认压缩工具结果',
            status: 'success',
            metadata: {
              'approved': true,
              'toolCallIds': event.toolCallIds,
              'candidateCount': event.candidateCount,
              'estimatedSavedTokens': event.estimatedSavedTokens,
              'originalTokens': event.originalTokens,
              'compressedTokens': event.compressedTokens,
            },
          );
        } else if (event is ContextBudgetWarningEvent) {
          await recordRunEvent(
            type: 'context_budget',
            name: '上下文预算${event.level.label}',
            status: event.level.name,
            metadata: {
              'level': event.level.name,
              'usedTokens': event.usedTokens,
              'contextWindow': event.contextWindow,
              'remainingTokens': event.remainingTokens,
              if (event.dominantPart != null)
                'dominantPart': event.dominantPart,
            },
          );
        } else if (event is AgentContextChangeEvent) {
          await recordRunEvent(
            type: event.kind,
            name: _contextChangeName(event),
            status: 'recorded',
            metadata: {
              'step': event.step,
              'category': event.category,
              'deltaTokens': event.deltaTokens,
              'estimated': true,
            },
          );
        } else if (event is AgentStepUsageEvent) {
          if (ownsRun() && visible()) {
            final steps = _currentState.contextSteps.map((record) {
              return record.step == event.step
                  ? record.withUsage(event.usage)
                  : record;
            }).toList(growable: false);
            _currentState = _currentState.copyWith(
              contextSteps: steps,
              contextSnapshot:
                  _currentState.contextSnapshot?.withProviderUsage(event.usage),
            );
          }
          await recordRunEvent(
            type: 'context_usage',
            name: '上下文使用量',
            status: 'recorded',
            metadata: {
              'step': event.step,
              'promptTokens': event.usage.promptTokens,
              'completionTokens': event.usage.completionTokens,
              'cachedTokens': event.usage.cachedTokens,
              'cacheWriteTokens': event.usage.cacheWriteTokens,
              'reasoningTokens': event.usage.reasoningTokens,
              'usageReported': event.usage.usageReported,
              'cacheStatsReported': event.usage.cacheStatsReported,
            },
          );
        } else if (event is AgentStatusEvent &&
            event.status == RunStatus.waitingModel) {
          beginModelTiming();
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.waitingModel,
            label: '正在等待模型响应',
          );
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
          if (ownsRun() && visible()) {
            // agent 循环每迭代一步都会先进入 waitingModel，这里累计步数。
            _currentState = _currentState.copyWith(
                totalSteps: _currentState.totalSteps + 1);
          }
        } else if (event is TextEvent) {
          if (ownsRun() && visible()) {
            _currentState = _currentState.copyWith(
              modelServiceStatus: ModelServiceStatus.online,
            );
          }
          if (reasoningStartedAt != null && reasoningDuration == null) {
            reasoningDuration = DateTime.now().difference(reasoningStartedAt);
          }
          final firstTokenElapsed = stopwatch.elapsed;
          ttft ??= firstTokenElapsed;
          firstTokenDurationMs ??= firstTokenElapsed.inMilliseconds;
          final now = DateTime.now();
          firstModelTokenAt ??= now;
          firstTextStartedAt ??= now;
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
          reportGeneratedProgress(
            stage: ChatRunStage.generating,
            label: '正在生成回答',
          );
          requestFlush();
        } else if (event is ReasoningEvent) {
          if (ownsRun() && visible()) {
            _currentState = _currentState.copyWith(
              modelServiceStatus: ModelServiceStatus.online,
            );
          }
          reasoningStartedAt ??= DateTime.now();
          final firstTokenElapsed = stopwatch.elapsed;
          ttft ??= firstTokenElapsed;
          firstTokenDurationMs ??= firstTokenElapsed.inMilliseconds;
          final now = DateTime.now();
          firstModelTokenAt ??= now;
          timingReasoningStartedAt ??= now;
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
          reportGeneratedProgress(
            stage: ChatRunStage.reasoning,
            label: '正在整理思路',
          );
          requestFlush();
        } else if (event is AgentUsageEvent) {
          usage = Usage(
              promptTokens: event.promptTokens,
              completionTokens: event.completionTokens,
              cachedTokens: event.cachedTokens,
              cacheWriteTokens: event.cacheWriteTokens,
              reasoningTokens: event.reasoningTokens,
              usageReported: event.usageReported,
              cacheStatsReported: event.cacheStatsReported);
          if (ownsRun() &&
              visible() &&
              assistantIndex < _currentState.messages.length) {
            final current = _currentState.messages[assistantIndex];
            final snapshot = _currentState.contextSnapshot;
            _currentState = _withMessageAt(
              _currentState,
              assistantIndex,
              current.copyWith(usage: usage),
            ).copyWith(
              liveContextTokens:
                  snapshot?.usedTokens ?? _currentState.liveContextTokens,
            );
          }
          final estimate = _estimateUsageCost(config, usage);
          estimatedCostCents = estimate.costCents;
          savedCostCents = estimate.savedCostCents;
        } else if (event is AgentErrorEvent) {
          finishModelTiming();
          runStatus = 'failed';
          final failure = ModelFailure.classify(
            event.message,
            statusCode: event.statusCode,
            failureKind: event.failureKind,
          );
          if (ownsRun() && visible()) {
            _currentState = _currentState.copyWith(
              modelServiceStatus: failure.serviceStatus,
            );
          }
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
          answer.write(
            '\n\n${formatErrorForMessage(
              event.message,
              statusCode: event.statusCode,
              failureKind: event.failureKind,
            )}',
          );
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
                'errorType': event.failureKind ?? 'provider_error',
                'serviceStatus': failure.serviceStatus.name,
                if (event.statusCode != null) 'statusCode': event.statusCode,
              });
        } else if (event is AgentBudgetExhaustedEvent) {
          finishModelTiming();
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
          // 写入可续跑暂停提示（不是错误）：气泡据此显示暂停卡，提供
          // 继续执行 / 从头重试 / 切换模型，而不是「未知错误」。
          final pausedForFailures =
              event.reason == AgentPauseReason.repeatedFailures;
          final pauseNotice = formatRunPauseForMessage(
            kind: pausedForFailures
                ? RunPauseKind.repeatedFailures
                : RunPauseKind.budget,
            maxSteps: event.maxSteps,
            runId: runId,
          );
          answer.write('\n\n$pauseNotice');
          await recordRunEvent(
              type: 'budget',
              name: pausedForFailures ? '连续失败已暂停' : '执行预算已耗尽',
              status: 'paused',
              outputSummary: event.message,
              metadata: {
                'maxSteps': event.maxSteps,
                'reason': event.reason.name,
              });
          await logService.warning(
              pausedForFailures
                  ? 'Agent 连续工具失败，已暂停可续跑'
                  : 'Agent 达到执行步数预算，已暂停可续跑',
              runId: runId,
              category: 'budget',
              detail: {'maxSteps': event.maxSteps});
        } else if (event is AgentBudgetExtendedEvent) {
          // 预算用完但仍有进展：执行器已自动追加一轮预算，只记录、不打断。
          await recordRunEvent(
              type: 'budget',
              name: '自动续跑',
              status: 'success',
              outputSummary: '已自动续跑（${event.round}/${event.limit}），'
                  '再执行 ${event.addedSteps} 轮',
              metadata: {
                'round': event.round,
                'limit': event.limit,
                'addedSteps': event.addedSteps,
              });
          if (ownsRun() && visible()) {
            _currentState = _currentState.copyWith(activityLog: [
              ..._currentState.activityLog,
              '已自动续跑（${event.round}/${event.limit}）',
            ]);
          }
        } else if (event is AgentRetryEvent) {
          finishModelTiming();
          beginModelTiming();
          retryCount = event.attempt;
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.waitingModel,
            label: '连接波动，正在重试第 ${event.attempt + 1} 次',
          );
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
          finishModelTiming();
          if (!ownsRun()) continue;
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.waitingForTool,
            label: '准备处理：${event.call.name}',
          );
          final risk = _riskFor(registry, event.call.name);
          // The provider response is complete once tool calls are emitted;
          // keep network latency separate from the tool execution duration.
          await tracker?.finish(activeNetworkEvent, status: 'success');
          await tracker?.finish(modelEvent, status: 'success');
          activeNetworkEvent = null;
          modelEvent = null;
          toolStartedAt[event.call.id] = DateTime.now();
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
          if (ownsRun()) {
            await _persistToolCall(event.call, risk,
                conversationId: runConversationId);
          }
          if (!ownsRun() || !visible()) continue;
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.waitingForTool,
            label: '等待工具开始执行：${event.call.name}',
          );
          _currentState = _currentState.copyWith(
            activityLog: [
              ..._currentState.activityLog,
              '准备执行：${event.call.name}',
            ],
            toolActivities: [
              ..._currentState.toolActivities,
              ToolActivity(
                call: event.call,
                risk: risk,
                sensitive: registry
                        .findRegistration(event.call.name)
                        ?.spec
                        .sensitive ??
                    false,
              )
            ],
          );
        } else if (event is AgentStatusEvent &&
            event.status == RunStatus.executingTool) {
          if (!ownsRun()) continue;
          final currentTool = _currentState.toolActivities.lastOrNull;
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.executingTool,
            label: currentTool == null
                ? '正在执行工具'
                : '正在执行：${currentTool.call.name}',
          );
          if (_currentState.toolActivities.isEmpty ||
              _currentState.toolActivities.last.call.name != 'manage_plan') {
            _updatePlanStepStatus('running');
          }
          _currentState = _currentState.copyWith(
            activityLog: [
              ..._currentState.activityLog,
              currentTool == null ? '正在执行工具' : '正在执行：${currentTool.call.name}',
            ],
            toolActivities: _updateLastToolActivity(
                _currentState.toolActivities,
                status: '执行中'),
          );
        } else if (event is ApprovalRequiredEvent) {
          if (!ownsRun()) continue;
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.waitingForUser,
            label: '等待你的确认：${event.call.name}',
          );
          _currentState = _currentState.copyWith(
            activityLog: [
              ..._currentState.activityLog,
              '等待你的确认：${event.call.name}',
            ],
            toolActivities: _updateToolActivity(
                _currentState.toolActivities, event.call.id,
                status: '等待确认'),
          );
          if (taskId != null) {
            final taskDb = await _ref.read(databaseProvider.future);
            await TaskService()
                .updateStatus(taskDb, taskId, 'waiting_approval');
          }
          // 这里刻意不再发通知：
          // * 应用在前台时，用户直接看得到审批弹窗，弹通知纯属噪音；
          // * 应用在后台时，promptToolApproval 会转走 ApprovalBridge，由它发出
          //   带「批准 / 拒绝」动作的通知。
          // 此前这里额外发一条不带动作的「开发任务等待审批」，于是后台审批会在
          // 通知栏出现两条指向同一次审批的通知，其中一条点了没有任何裁决能力。
        } else if (event is ToolResultEvent) {
          if (!ownsRun()) continue;
          final toolFailed = !event.result.ok;
          if (event.call.name == 'android_device' ||
              event.call.name == 'android_device_preview' ||
              event.call.name == 'android_app_private_data' ||
              event.call.name == 'android_app_private_data_preview') {
            try {
              final auditDb = await _ref.read(databaseProvider.future);
              final privateDataPreview =
                  event.call.name == 'android_app_private_data_preview';
              final devicePreview = event.call.name == 'android_device_preview';
              final executedDeviceCall = event.call.name == 'android_device';
              await _ref.read(auditServiceProvider).logAndroidDeviceOperation(
                    auditDb,
                    userRequest: deviceAuditUserRequest,
                    arguments: event.call.arguments,
                    resultOk: event.result.ok,
                    resultCode: event.result.code,
                    resultEffect: event.result.effect.name,
                    risk: privateDataPreview || devicePreview
                        ? 'safe'
                        : event.call.name == 'android_app_private_data'
                            ? 'dangerous'
                            : event.call.name == 'android_device'
                                ? AndroidDeviceTool.auditRiskForArguments(
                                        event.call.arguments)
                                    .name
                                : 'requiresConfirmation',
                    previewOnly: privateDataPreview || devicePreview,
                    conversationId: runConversationId,
                    toolName: event.call.name,
                    execution: executedDeviceCall || devicePreview
                        ? AndroidDeviceTool.auditExecutionFor(
                            event.call.arguments)
                        : null,
                    startedAt: toolStartedAt.remove(event.call.id),
                  );
            } catch (error, stackTrace) {
              NexusGuard.degradeCaught(
                'audit.androidDeviceOperation.database',
                error,
                stackTrace,
                logger: logService.warning,
                runId: runId,
              );
            }
          }
          if (event.call.name == 'android_automation' &&
              const {'create_rule', 'set_rule_enabled', 'delete_rule'}
                  .contains(event.call.arguments['action'])) {
            // 规则变更与用户原话关联入审计；规则服务自身另记一条生命周期事件。
            try {
              final auditDb = await _ref.read(databaseProvider.future);
              final args = event.call.arguments;
              final trigger = AutomationTrigger.fromJson(args['trigger']);
              final actions = args['actions'] is List
                  ? (args['actions'] as List)
                      .map(AutomationAction.fromJson)
                      .whereType<AutomationAction>()
                      .toList()
                  : const <AutomationAction>[];
              await _ref.read(auditServiceProvider).logDeviceAutomationEvent(
                    auditDb,
                    event:
                        'agent_${args['action']}_${event.result.ok ? 'ok' : event.result.code}',
                    ruleId:
                        (event.result.data?['ruleId'] ?? args['ruleId'] ?? '')
                            .toString(),
                    ruleName: args['name']?.toString() ?? '',
                    trigger: trigger?.describe() ?? '',
                    actions:
                        actions.map((action) => action.describe()).toList(),
                    requiresRoot: actions.any((action) => action.requiresRoot),
                    irreversible: actions.any((action) => action.irreversible),
                    userRequest: deviceAuditUserRequest,
                  );
            } catch (error, stackTrace) {
              NexusGuard.degradeCaught(
                'audit.deviceAutomation.database',
                error,
                stackTrace,
                logger: logService.warning,
                runId: runId,
              );
            }
          }
          if (taskId != null) {
            final taskDb = await _ref.read(databaseProvider.future);
            await TaskService().updateStatus(taskDb, taskId, 'running');
          }
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
          toolStartedAt.remove(event.call.id);
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
                toolResult: event.result,
                conversationId: runConversationId);
          }
          if (!visible()) continue;
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
          final toolExecutionMs = _currentState.toolActivities.fold<int>(
            0,
            (total, activity) => total + activity.executionMs,
          );
          timing = timing.copyWith(
            toolExecutionMs: toolExecutionMs,
            toolCalls: timing.toolCalls + 1,
          );
          publishTiming();
          final completedTools = _currentState.toolActivities
              .where((activity) =>
                  activity.status == '已完成' || activity.status == '执行失败')
              .length;
          _setRunProgress(
            runGeneration: runGeneration,
            conversationId: runConversationId,
            stage: ChatRunStage.waitingModel,
            label: toolFailed ? '工具未完成，正在重新规划' : '工具已完成，正在继续处理',
            completedTools: completedTools,
          );
        }
        if (event is AgentStatusEvent) {
          if (event.status == RunStatus.paused && ownsRun()) {
            finishModelTiming();
            runStatus = 'paused';
            _setRunProgress(
              runGeneration: runGeneration,
              conversationId: runConversationId,
              stage: ChatRunStage.paused,
              label: '已暂停，可继续或追加指令',
            );
            if (visible()) {
              _currentState = _currentState.copyWith(
                paused: true,
                activityLog: [
                  ..._currentState.activityLog,
                  '已暂停，可继续或追加指令',
                ],
              );
            }
          }
          if (event.status == RunStatus.cancelled) {
            finishModelTiming();
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
            finishModelTiming();
            runStatus = 'success';
            if (ownsRun() && visible()) {
              _currentState = _currentState.copyWith(
                modelServiceStatus: ModelServiceStatus.online,
              );
            }
            final usageMetadata = {
              'promptTokens': usage.promptTokens,
              'completionTokens': usage.completionTokens,
              'cachedTokens': usage.cachedTokens,
              'cacheWriteTokens': usage.cacheWriteTokens,
              'reasoningTokens': usage.reasoningTokens,
              'cacheHit': usage.cachedTokens > 0,
              // hit=命中；miss=未命中；no-cache-stats=usage 里没有缓存字段；
              // no-usage=整轮没收到 usage。区分后两类，避免把“统计缺失”
              // 当成“未命中”展示。
              'cacheStatus': usage.cachedTokens > 0
                  ? 'hit'
                  : usage.cacheStatsReported
                      ? 'miss'
                      : usage.usageReported
                          ? 'no-cache-stats'
                          : 'no-usage',
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
      sessionRecorder?.abort('unexpected_error');
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
      // 事件流未给出终态就结束（提前跳出、外部取消）时封口；已结束则无操作。
      sessionRecorder?.abort('stream_ended_without_status');
      final pendingSessionLog = sessionRecorder?.flush();
      if (pendingSessionLog != null) unawaited(pendingSessionLog);
      flushTimer?.cancel();
      flushTimer = null;
      finishModelTiming();
      stopwatch.stop();
      publishTiming();
      try {
        final runDb = await _ref.read(databaseProvider.future);
        if (_runs.wasCancelled(runGeneration)) {
          runStatus = 'cancelled';
        }
        if (runStatus == 'running') runStatus = 'failed';
        if (runStatus == 'success' &&
            answer.toString().trim().isEmpty &&
            reasoning.toString().trim().isEmpty) {
          runStatus = 'failed';
          answer.write('模型未返回可显示内容，请检查 Provider/模型配置后重试。');
          await logService.error(
            '模型返回空响应',
            runId: runId,
            category: 'model',
            errorCode: 'EMPTY_MODEL_RESPONSE',
          );
        }
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
        } catch (_) {
          // 可忽略（有意降级）：运行收尾（finish/flush）失败不改变本轮
          // 结果——用户已经拿到回答，此处再抛会把成功回合显示成失败。
          // 落库失败会在下方 insertRunRecord 的重试与最外层 catch 中被记录。
        }
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
        } catch (_) {
          // 可忽略：运行记录清理失败只影响历史表体积，不影响本轮结果。
          // 下次启动或后续运行会再次尝试。
        }
        // 任务变更集与保存的原始文件：保留 30 天内、最近 50 个任务；
        // 刚结束的任务始终保留。不阻塞收尾，失败下次再试。
        unawaited(pruneChangeSets(protect: {if (taskId != null) taskId})
            .catchError((Object _) => 0));
      } catch (_) {
        // 可忽略（有意降级）：运行指标持久化整体失败时不改变控制流——
        // 到此为止用户回答已生成完毕。指标缺失只影响统计面板的完整度。
      }
    }
    // 运行事件已完成落库；让下一次打开指标面板重新读取历史，避免在运行中
    // 预加载过一次之后继续展示缺少本轮结果的旧缓存。
    _invalidateContextRuns();
    final finalAnswerText = answer.toString();
    final finalReasoningText = reasoning.isEmpty ? '' : reasoning.toString();
    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      role: MessageRole.assistant,
      parts: [MessagePart.text(finalAnswerText)],
      reasoning: finalReasoningText.isEmpty ? null : finalReasoningText,
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
    if (visible()) {
      _convergePlanToTerminal(runStatus: runStatus, cancelled: runCancelled);
    }
    final runSucceeded = !runCancelled && runStatus == 'success';
    if (ownsRun()) {
      try {
        await _persistMessage(assistantMessage,
            conversationId: runConversationId);
      } catch (error, stack) {
        // 持久化失败不阻断 UI 恢复。
        unawaited(logService.error(
          'Final assistant message persistence failed',
          error: error,
          stackTrace: stack,
          runId: runId,
          category: 'run_persistence',
        ));
      }
      if (visible()) {
        if (assistantIndex < _currentState.messages.length) {
          _currentState =
              _withMessageAt(_currentState, assistantIndex, assistantMessage)
                  .copyWith(
            running: false,
            clearLiveReply: true,
            clearRunProgress: true,
            successfulRunCount:
                runSucceeded ? _currentState.successfulRunCount + 1 : null,
            liveContextTokens: usage.totalTokens > 0
                ? usage.totalTokens
                : _estimateLiveContextTokens(assistantIndex, assistantMessage),
          );
        } else {
          _currentState = _currentState.copyWith(
              running: false,
              paused: false,
              clearLiveReply: true,
              clearRunProgress: true,
              successfulRunCount:
                  runSucceeded ? _currentState.successfulRunCount + 1 : null);
        }
      }
    }
    if (taskId != null) {
      try {
        final taskDb = await _ref.read(databaseProvider.future);
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
        final workspacePath = _currentState.currentWorkspacePath;
        if (workspacePath != null &&
            workspacePath.trim().isNotEmpty &&
            status != 'cancelled') {
          try {
            await DevelopmentLoopFinalizer().finalize(
              db: taskDb,
              taskId: taskId,
              runId: runId,
              workspacePath: workspacePath,
              terminal: null,
              runVerification: false,
            );
          } catch (_) {
            // 可忽略（有意降级）：开发任务收尾失败不影响本轮对话结果；
            // 任务状态会在下次执行或用户手动刷新时重新收敛。
          }
        }
        await NotificationService.instance.init();
        await NotificationService.instance.show(
          id: taskId.hashCode & 0x7fffffff,
          title: status == 'completed'
              ? '开发任务已完成'
              : (status == 'paused' ? '开发任务已暂停' : '开发任务未完成'),
          body: _notificationPreview(answer.toString(), status),
          payload: 'task:$taskId',
        );
      } catch (_) {
        // 可忽略（有意降级）：任务通知是「锦上添花」通道，通知权限被拒或
        // 初始化失败不应影响已经在 UI 上呈现的运行结果。
      }
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

  String _contextChangeName(AgentContextChangeEvent event) {
    final category = ContextPartType.values
        .where((type) => type.name == event.category)
        .map((type) => type.label)
        .firstOrNull;
    final label = category ?? event.category;
    return switch (event.kind) {
      'context_inject' => '$label 注入',
      'context_prune' => '$label 剪枝',
      'context_compress' => '历史上下文压缩',
      _ => '上下文变化',
    };
  }
}
