part of 'chat_page.dart';

/// 外部入口：深链、通知、可恢复任务、应用锁与系统分享。
extension _ChatIntents on _ChatPageState {
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
    final state = ref.read(chatControllerProvider);
    // Initialization must finish first: otherwise its old conversation can
    // overwrite the new one. The state listener retries when restoration ends.
    if (state.loading || state.restoringConversation) return;
    _handlingDeepLink = true;
    final links = DeepLinkService.instance;
    try {
      final prompt = links.drainPrompt();
      // An empty string is an explicit new-chat request, not "no request".
      if (prompt != null) await _startNewConversation(initialText: prompt);
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
      if (mounted) FloatingToast.show(context, '无法打开深链接，请重试');
    } finally {
      _handlingDeepLink = false;
      if (mounted && links.hasPending) _scheduleDeepLinkConsumption();
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
      if (!mounted) return;
      switch (intent.kind) {
        case NotificationIntentKind.conversation:
          final conversation = await database.findConversation(intent.id);
          if (!mounted) return;
          if (conversation == null) {
            FloatingToast.show(context, '该会话已不存在', tone: ToastTone.warning);
            return;
          }
          await _switchConversation(conversation);
        case NotificationIntentKind.task:
          final task = await database.findTask(intent.id);
          if (!mounted) return;
          if (task == null) {
            FloatingToast.show(context, '该任务已不存在', tone: ToastTone.warning);
            return;
          }
          await Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => TaskDetailsPage(task: TaskService().describe(task)),
          ));
        case NotificationIntentKind.approval:
          // 锁屏审批的裁决已由后台 isolate 写入数据库，这里只需把用户带回应用，
          // 待处理入口就在当前会话页。已在前台时给一句提示，避免"点了没反应"。
          final state = ref.read(chatControllerProvider);
          if (state.running || state.toolActivities.isNotEmpty) {
            FloatingToast.show(context, '请回到当前会话处理待审批操作');
          }
        case NotificationIntentKind.automation:
          await Navigator.of(context).push(NexusPageRoute.detail(
            builder: (_) => DeviceAutomationPage(initialFireId: intent.id),
          ));
      }
    } catch (error) {
      if (mounted) {
        FloatingToast.error(context, '无法打开通知目标', rawDetail: error.toString());
      }
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
          await _ChatPageState._dismissRecoveryTask(candidates.first.id);
          await _chat.resumeTask(candidates.first.id,
              approveTool: _approveTool);
        case null:
          break;
      }
    } catch (e, stack) {
      debugPrint('恢复检测失败: $e\n$stack');
    }
  }

  /// 生物识别锁：开启且设备支持时，启动/回前台需验证身份。
  Future<void> _maybeLock() async {
    final lock = ref.read(appLockServiceProvider);
    if (!await lock.isEnabled()) return;
    if (!await lock.canUseBiometrics()) return;
    if (!mounted) return;
    final ok = await lock.authenticate();
    if (!ok && mounted) {
      await _showLockFailed(lock);
    }
  }

  Future<void> _showLockFailed(AppLockService lock) async {
    final retry = await showConfirmAction(
      context,
      barrierDismissible: false,
      title: '身份验证失败',
      message: '可重试，或退出应用。',
      confirmLabel: '重试',
      cancelLabel: '退出',
      isDanger: false,
    );
    if (!mounted) return;
    if (retry) {
      unawaited(_maybeLock());
    } else {
      unawaited(SystemNavigator.pop());
    }
  }

  /// 处理系统分享内容：图片转附件，文本/URL 预填输入框；均自动新建会话。
  /// 把一批分享内容合并进同一个新会话。
  ///
  /// 系统分享可以一次带上多张图（相册多选分享）。此前对每条内容各调一次
  /// `_startNewConversation`，分享 3 张图会演出 3 个会话，而且都是异步的，
  /// 前面的会被后面的覆盖，用户最终只看得到最后一张。
  Future<void> _onSharedTexts(List<String> shared) async {
    if (!mounted) return;
    final items = shared.where(SharingService.isShareableText).toList();
    if (items.isEmpty) return;
    _pendingSourceType = 'share';

    final attachments = <AttachmentFile>[];
    final texts = <String>[];
    for (final item in items) {
      if (item.startsWith('data:image/')) {
        final attachment = _decodeSharedImage(item);
        if (attachment != null) attachments.add(attachment);
      } else {
        texts.add(item);
      }
    }
    if (attachments.isEmpty && texts.isEmpty) return;

    await _startNewConversation();
    if (!mounted) return;
    if (attachments.isNotEmpty) {
      _attachments.addAll(attachments);
      _notifyAttachmentsChanged();
    }
    final merged = texts.join('\n\n');
    if (merged.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
    }
    if (attachments.isNotEmpty) {
      FloatingToast.show(
        context,
        attachments.length > 1
            ? '已接收 ${attachments.length} 张图片，可点击发送'
            : '已接收图片，可点击发送',
        tone: ToastTone.success,
      );
    }
  }
}
