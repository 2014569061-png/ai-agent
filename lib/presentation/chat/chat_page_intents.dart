part of 'chat_page.dart';

class _ExternalEntryDeferred implements Exception {
  const _ExternalEntryDeferred();
}

/// 外部入口：深链、通知、可恢复任务、应用锁与系统分享。
extension _ChatIntents on _ChatPageState {
  bool _canConsumeEntry({bool allowRestoring = false}) {
    if (!mounted || !_entryUnlockConfirmed || !_entryForeground) return false;
    final state = ref.read(chatControllerProvider);
    final links = DeepLinkService.instance;
    return AssistantEntrySurface.canConsume(context,
        busy: (state.running && AssistantEntryDelivery.requiresIdle(links)) ||
            state.loading ||
            (!allowRestoring && state.restoringConversation));
  }

  void _scheduleDeepLinkConsumption() {
    if (!mounted || _deepLinkScheduled) return;
    _deepLinkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinkScheduled = false;
      if (mounted) unawaited(_consumeDeepLink());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _consumeDeepLink() async {
    if (!mounted || _handlingDeepLink) return;
    // Initialization must finish first: otherwise its old conversation can
    // overwrite the new one. The state listener retries when restoration ends.
    if (!_canConsumeEntry()) {
      return;
    }
    _handlingDeepLink = true;
    final links = DeepLinkService.instance;
    final entryRevision = links.legacyRevision;
    try {
      final warning = links.takeRejection();
      if (warning != null) {
        FloatingToast.show(context, warning, tone: ToastTone.warning);
      }
      if (!links.consumptionReady) return;
      if (!links.hasLegacyPending) {
        final entry = links.pendingExternal;
        if (entry != null) await _consumeExternalEntry(entry);
        return;
      }
      links
          .drainAssistant(); // Navigation only: no draft replacement or model call.
      final prompt = links.pendingPrompt;
      // Acknowledge only after the existing flow succeeds; failed loading keeps it.
      if (prompt != null) {
        await _startNewConversation(
            initialText: prompt,
            canCommit: () => _canConsumeEntry(allowRestoring: true));
        if (!_canConsumeEntry()) return;
        if (links.pendingPrompt == prompt) links.drainPrompt();
      }
      if (!mounted) return;
      if (links.drainNewAgent()) {
        unawaited(Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => const AgentsPage(autoDescribe: true))));
      }
      if (links.drainMemory()) {
        unawaited(Navigator.of(context)
            .push(NexusPageRoute.detail(builder: (_) => const MemoryPage())));
      }
    } catch (_) {
      // A failed navigation should not crash the page or auto-send the prompt.
      links.markConsumptionFailed(entryRevision);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('入口处理失败，内容已保留；不会自动反复重试'),
            action: SnackBarAction(
                label: '重试',
                onPressed: () {
                  if (mounted &&
                      AssistantEntrySurface.canConsume(context) &&
                      links.retryPending(entryRevision)) {
                    _scheduleDeepLinkConsumption();
                  }
                })));
      }
    } finally {
      _handlingDeepLink = false;
      if (mounted && links.consumptionReady) {
        if (_canConsumeEntry()) {
          _scheduleDeepLinkConsumption();
        }
      }
    }
  }

  Future<void> _consumeExternalEntry(AssistantEntry entry) async {
    final links = DeepLinkService.instance;
    final owner = ref.read(chatControllerProvider.notifier);
    final conversation = ref.read(chatControllerProvider).conversationId;
    final attachmentsRevision = _attachmentsRevision.value;
    final draft = _controller.text;
    final attachments = <AttachmentFile>[];
    final texts = <String>[];
    final page = entry.pageContext;
    try {
      final outcome = await const AssistantEntryDelivery().deliver(links, entry,
          canPresent: _canConsumeEntry,
          contextUnchanged: () =>
              mounted &&
              identical(ref.read(chatControllerProvider.notifier), owner) &&
              ref.read(chatControllerProvider).conversationId == conversation &&
              _controller.text == draft &&
              _attachmentsRevision.value == attachmentsRevision,
          pageContextAllowed: () async {
            final status = await const PlatformAssistantRoleSource()
                .status()
                .timeout(const Duration(seconds: 5));
            return status.connected && !status.locked;
          },
          navigate: _handleNotificationIntent,
          review: () async {
            for (final item in entry.shared) {
              if (item.startsWith('data:image/')) {
                final attachment = _decodeSharedImage(item);
                if (attachment == null) throw const FormatException('分享图片无法读取');
                attachments.add(attachment);
              } else {
                texts.add(item);
              }
            }
            final initialDraft = page?.text ?? texts.join('\n\n');
            String? contextHint;
            final logs = ref.read(logServiceProvider);
            try {
              final db = await ref.read(databaseProvider.future);
              contextHint = await PersonalContextService.forDatabase(db)
                  .describeAssistantEntryHint(initialDraft);
            } catch (error, stackTrace) {
              NexusGuard.degradeCaught(
                  'chat.assistantEntryHint', error, stackTrace,
                  logger: (message, {detail}) => unawaited(logs.warning(message,
                      category: 'assistant_entry', detail: detail)));
            }
            if (!mounted) return null;
            return showModalBottomSheet<AssistantInputDecision>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => AssistantInputReviewSheet(
                    title: page == null ? '检查分享内容' : '检查本次页面文字',
                    initialText: initialDraft,
                    source: page == null
                        ? '来源：系统分享'
                        : '来源：${page.sourceLabel} (${page.sourcePackage})\n采集于 ${page.capturedAt.toLocal()}；两分钟内有效${page.truncated ? "；仅部分文字" : ""}',
                    expiresAt: page?.expiresAt,
                    validFor: page?.remainingLifetime,
                    attachmentCount: attachments.length,
                    warning: contextHint));
          },
          stage: (text) {
            final current = _controller.text;
            final staged = current.trim().isEmpty
                ? text
                : (text.trim().isEmpty ? current : '$current\n\n$text');
            _attachments.addAll(attachments);
            _notifyAttachmentsChanged();
            _controller.value = TextEditingValue(
                text: staged,
                selection: TextSelection.collapsed(offset: staged.length));
            _pendingSourceType = page == null ? 'share' : 'assistant_context';
          });
      if (!mounted) return;
      if (outcome == AssistantEntryOutcome.deferred) {
        throw const _ExternalEntryDeferred();
      }
      if (outcome == AssistantEntryOutcome.expired) {
        FloatingToast.show(context, '页面文字已失效，请重新读取', tone: ToastTone.warning);
      } else if (outcome == AssistantEntryOutcome.staged) {
        FloatingToast.show(context, '已加入草稿，请确认后手动发送', tone: ToastTone.success);
      }
    } catch (error) {
      links.markExternalFailed(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is _ExternalEntryDeferred
                ? '输入已保留，等待你继续处理'
                : '入口处理未完成，内容已保留'),
            action: SnackBarAction(
                label: '继续处理',
                onPressed: () {
                  if (mounted &&
                      _canConsumeEntry() &&
                      links.retryExternal(entry.id)) {
                    _scheduleDeepLinkConsumption();
                  }
                })));
      }
    }
  }

  /// 消费一条通知点击意图，把用户带回通知所指的会话或任务。
  ///
  /// 通知是「尽力而为」的入口：目标可能已被删除（会话被清理、任务被移除），此时
  /// 必须给出明确提示，而不是静默无反应——用户刚在锁屏上点了通知，什么都不发生
  /// 会被理解成「应用坏了」。
  Future<void> _handleNotificationIntent(NotificationIntent intent) async {
    try {
      final database = await ref.read(databaseProvider.future);
      if (!mounted || !_canConsumeEntry()) throw const _ExternalEntryDeferred();
      switch (intent.kind) {
        case NotificationIntentKind.conversation:
          final conversation = await database.findConversation(intent.id);
          if (!mounted || !_canConsumeEntry()) {
            throw const _ExternalEntryDeferred();
          }
          if (conversation == null) {
            FloatingToast.show(context, '该会话已不存在', tone: ToastTone.warning);
            return;
          }
          await _switchConversation(conversation,
              canCommit: () => _canConsumeEntry(allowRestoring: true));
          if (!mounted ||
              !_canConsumeEntry() ||
              ref.read(chatControllerProvider).conversationId !=
                  conversation.id) {
            throw const _ExternalEntryDeferred();
          }
        case NotificationIntentKind.task:
          final task = await database.findTask(intent.id);
          if (!mounted || !_canConsumeEntry()) {
            throw const _ExternalEntryDeferred();
          }
          if (task == null) {
            FloatingToast.show(context, '该任务已不存在', tone: ToastTone.warning);
            return;
          }
          unawaited(Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => TaskDetailsPage(task: TaskService().describe(task)),
          )));
        case NotificationIntentKind.approval:
          // 通知没有授予批准；经过入口应用锁后，用户仍须查看待审批操作。
          // 旧请求、过期请求也不能仅凭通知 payload 恢复授权。
          final state = ref.read(chatControllerProvider);
          if (state.running || state.toolActivities.isNotEmpty) {
            FloatingToast.show(context, '请回到当前会话处理待审批操作');
          }
        case NotificationIntentKind.automation:
          unawaited(Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => DeviceAutomationPage(initialFireId: intent.id),
          )));
        case NotificationIntentKind.reminder:
          unawaited(Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => ScheduledTasksPage(
                initialReminderId: intent.id.split('@').first),
          )));
      }
    } catch (error) {
      rethrow;
    }
  }

  /// 检测可续跑的后台任务（进程被杀遗留的 running + 预算暂停的 paused），提示用户是否继续。
  ///
  /// 用户点过「忽略」的任务会被记录到 SharedPreferences，之后不再反复打扰
  /// （同一任务除非被再次发起，否则只在首次冷启动提示一次）。仪表盘的
  /// 「待我处理」区始终保留这些可恢复任务的常驻入口，因此这里静默忽略不会
  /// 让任务失去发现途径。
  Future<void> _checkRecoverableTask() async {
    try {
      final tasks = await _chat.recoverableTasks();
      if (!mounted || tasks.isEmpty) return;
      final dismissed = await _ChatPageState._dismissedRecoveryTaskIds();
      final candidates =
          tasks.where((task) => !dismissed.contains(task.id)).toList();
      if (candidates.isEmpty) return;
      final info = TaskService().describe(candidates.first);
      final accessible =
          await WorkspaceService().isAccessible(info.workspacePath);
      if (!mounted) return;
      final resume = await showNexusDialog<_RecoveryDecision>(
        context: context,
        builder: (_) => _RecoverableTaskDialog(
          info: info,
          accessible: accessible,
        ),
      );
      if (!mounted) return;
      switch (resume) {
        case _RecoveryDecision.ignore:
          await _ChatPageState._dismissRecoveryTask(candidates.first.id);
        case _RecoveryDecision.rebind:
          await _pickWorkspace();
        case _RecoveryDecision.continueExecuting:
          await _chat.resumeTask(candidates.first.id,
              approveTool: _approveTool);
          await _ChatPageState._dismissRecoveryTask(candidates.first.id);
        case null:
          break;
      }
    } on RunRecoveryNeedsReview catch (error) {
      if (mounted) {
        await showConfirmAction(context,
            title: '恢复前需要核实',
            message: error.toString(),
            confirmLabel: '我知道了',
            cancelLabel: '关闭');
      }
    } on AppliedCheckpointNeedsReview catch (error) {
      if (mounted) {
        FloatingToast.show(context, error.toString(), tone: ToastTone.warning);
      }
    } catch (e, stack) {
      debugPrint('恢复检测失败: $e\n$stack');
    }
  }

  /// 生物识别锁：开启且设备支持时，启动/回前台需验证身份。
  Future<void> _maybeLock() async {
    if (_entryUnlockInFlight || _entryUnlockConfirmed || !mounted) return;
    _entryUnlockInFlight = true;
    final epoch = _entryUnlockEpoch;
    final lock = ref.read(appLockServiceProvider);
    var retry = false;
    try {
      final enabled = await lock.isEnabled();
      final ok = !enabled ||
          (await lock.canUseBiometrics() && await lock.authenticate());
      if (!mounted || epoch != _entryUnlockEpoch) return;
      _entryUnlockConfirmed = ok;
      if (ok) {
        _scheduleDeepLinkConsumption();
      } else {
        retry = await _showLockFailed(lock);
      }
    } catch (_) {
      if (mounted) {
        FloatingToast.show(context, '应用锁状态未能核实，外部输入已保留',
            tone: ToastTone.warning);
      }
    } finally {
      _entryUnlockInFlight = false;
      if (mounted &&
          _entryForeground &&
          (retry || epoch != _entryUnlockEpoch)) {
        unawaited(_maybeLock());
      }
    }
  }

  Future<bool> _showLockFailed(AppLockService lock) async {
    final retry = await showConfirmAction(
      context,
      barrierDismissible: false,
      title: '身份验证失败',
      message: '可重试，或退出应用。',
      confirmLabel: '重试',
      cancelLabel: '退出',
      isDanger: false,
    );
    if (!mounted) return false;
    if (retry) {
      return true;
    } else {
      unawaited(SystemNavigator.pop());
    }
    return false;
  }
}
