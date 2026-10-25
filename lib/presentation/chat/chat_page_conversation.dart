part of 'chat_page.dart';

/// 草稿保存与恢复、新建/切换会话、导出会话。
extension _ChatConversation on _ChatPageState {
  void _rememberCurrentDraft() {
    final state = ref.read(chatControllerProvider);
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    final draft = _controller.text;
    if (draft.trim().isEmpty) {
      _draftsByConversation.remove(conversationId);
    } else {
      _draftsByConversation[conversationId] = draft;
    }
    _schedulePersistDraft(
      conversationId: conversationId,
      projectId: state.currentProjectId,
      text: draft,
    );
  }

  void _schedulePersistDraft({
    required String conversationId,
    String? projectId,
    required String text,
  }) {
    _draftPersistTimer?.cancel();
    _draftPersistTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_persistDraft(
        conversationId: conversationId,
        projectId: projectId,
        text: text,
      ));
    });
  }

  Future<void> _persistDraft({
    required String conversationId,
    String? projectId,
    required String text,
  }) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final key = DraftService.keyFor(
        conversationId: conversationId,
        projectId: projectId,
      );
      final attachments = await _stageCurrentAttachments();
      final references = [
        for (final citation
            in ref.read(chatControllerProvider).pendingCitations)
          citation.toJson(),
      ];
      if (text.trim().isEmpty && attachments.isEmpty && references.isEmpty) {
        await _draftService.clear(db, key);
        return;
      }
      await _draftService.save(
        db,
        draftKey: key,
        conversationId: conversationId,
        projectId: projectId,
        text: text,
        attachments: attachments,
        references: references,
      );
    } catch (_) {
      // 草稿自动保存（防抖 300ms）失败只影响「切换会话后能否恢复未发送内容」，
      // 不能反过来打断正在输入的用户；这也是高频路径，不宜逐次上报。
    }
  }

  Future<List<DraftAttachment>> _stageCurrentAttachments() async {
    final staged = <DraftAttachment>[];
    for (final file in _attachments) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        staged.add(DraftAttachment(
          id: UniqueId.generate('att'),
          name: file.name,
          mime: file.extension ?? 'application/octet-stream',
          path: file.path ?? '',
          status: file.path == null ? 'missing' : 'ready',
        ));
        continue;
      }
      staged.add(await _draftService.stageFile(
        id: UniqueId.generate('att'),
        name: file.name,
        mime: file.extension ?? 'application/octet-stream',
        bytes: bytes,
      ));
    }
    return staged;
  }

  void _clearCurrentDraft() {
    final state = ref.read(chatControllerProvider);
    final conversationId = state.conversationId;
    if (conversationId == null) return;
    _draftsByConversation.remove(conversationId);
    unawaited(_persistDraft(
      conversationId: conversationId,
      projectId: state.currentProjectId,
      text: '',
    ));
  }

  Future<void> _restoreDraft(String? conversationId,
      {bool Function()? canCommit}) async {
    final input = _controller.value;
    final attachmentsRevision = _attachmentsRevision.value;
    bool current() =>
        mounted &&
        ref.read(chatControllerProvider).conversationId == conversationId &&
        _controller.value == input &&
        _attachmentsRevision.value == attachmentsRevision &&
        (canCommit?.call() ?? true);
    var draft = conversationId == null
        ? ''
        : (_draftsByConversation[conversationId] ?? '');
    if (draft.isEmpty && conversationId != null) {
      try {
        final db = await ref.read(databaseProvider.future);
        final key = DraftService.keyFor(
          conversationId: conversationId,
          projectId: ref.read(chatControllerProvider).currentProjectId,
        );
        final stored = await _draftService.load(db, key);
        if (!current()) return;
        draft = stored?.text ?? '';
        if (draft.isNotEmpty) {
          _draftsByConversation[conversationId] = draft;
        }
        if (stored != null) {
          _restoreDraftAttachments(stored);
          for (final reference in stored.references) {
            unawaited(_chat.addFileCitation(FileCitation.fromJson(reference)));
          }
        }
      } catch (_) {
        // 草稿恢复失败即退回空草稿：用户看到的是一个空输入框，而不会因为一次
        // 读取异常导致整个聊天页无法打开。
      }
    }
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversationId ||
        _controller.value != input ||
        (canCommit != null && !canCommit())) {
      return;
    }
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    // 文本选择模式是"当前这条消息"的临时态，切换会话就该退出，
    // 否则会在另一个会话里意外留下一个可选气泡。
    if (_selectingMessageIndex.value != null) {
      _selectingMessageIndex.value = null;
    }
  }

  Future<void> _startNewConversation(
      {String? initialText, bool Function()? canCommit}) async {
    _rememberCurrentDraft();
    await _chat.newConversation(canCommit: canCommit);
    if (!mounted || (canCommit != null && !canCommit())) return;
    _attachments.clear();
    _notifyAttachmentsChanged();
    final conversationId = ref.read(chatControllerProvider).conversationId;
    await _restoreDraft(conversationId, canCommit: canCommit);
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversationId ||
        (canCommit != null && !canCommit())) {
      return;
    }
    if (initialText != null) {
      _controller.value = TextEditingValue(
        text: initialText,
        selection: TextSelection.collapsed(offset: initialText.length),
      );
    }
    _resetSessionSkills();
  }

  Future<void> _switchConversation(Conversation conversation,
          {bool Function()? canCommit}) =>
      _switchConversationId(conversation.id, canCommit: canCommit);

  Future<void> _switchConversationId(String conversationId,
      {bool Function()? canCommit}) async {
    _rememberCurrentDraft();
    await _chat.switchConversationById(conversationId, canCommit: canCommit);
    if (!mounted ||
        ref.read(chatControllerProvider).conversationId != conversationId ||
        (canCommit != null && !canCommit())) {
      return;
    }
    _attachments.clear();
    _notifyAttachmentsChanged();
    await _restoreDraft(conversationId, canCommit: canCommit);
    _resetSessionSkills();
  }

  void _restoreDraftAttachments(ConversationDraft draft) {
    final restored = <AttachmentFile>[];
    var missing = 0;
    for (final item in draft.attachments) {
      if (item.status == 'missing' || item.path.isEmpty) {
        missing++;
        continue;
      }
      // 草稿里的附件只有名字与路径，字节在真正发送前由发送管线补读；
      // 这里刻意留 bytes: null，避免为了「恢复草稿」就把文件全读进内存，
      // 也让发送端能区分「无字节」与「空文件」。
      restored.add(AttachmentFile(
        name: item.name,
        path: item.path,
      ));
    }
    if (!mounted) return;
    _attachments
      ..clear()
      ..addAll(restored);
    _notifyAttachmentsChanged();
    if (missing > 0) {
      FloatingToast.show(context, '有 $missing 个附件失效，请重新选择',
          tone: ToastTone.warning);
    }
  }

  String _buildMarkdown(ChatState state) {
    final content = StringBuffer('# ${state.conversationTitle}\n\n');
    final toolNamesById = <String, String>{};
    for (final message in state.messages) {
      if (message.role != MessageRole.assistant) continue;
      for (final call in message.toolCalls) {
        toolNamesById[call.id] = call.name;
      }
    }
    for (final message in state.messages) {
      final role = switch (message.role) {
        MessageRole.user => '用户',
        MessageRole.assistant => '助手',
        MessageRole.system => '系统',
        MessageRole.tool => '工具',
      };
      final text = message.role == MessageRole.tool
          ? SensitiveToolPolicy.redactText(
              toolNamesById[message.toolCallId] ?? '', message.text)
          : message.text;
      content.write('## $role\n\n$text\n\n');
    }
    return content.toString();
  }

  Future<void> _copyConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _buildMarkdown(state)));
    if (mounted) {
      FloatingToast.show(context, AppStrings.conversationCopied,
          tone: ToastTone.success);
    }
  }

  Future<void> _exportConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    final content = _buildMarkdown(state);
    final path =
        await exportConversationMarkdown(state.conversationTitle, content);
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    FloatingToast.show(context,
        kIsWeb || path.isEmpty ? AppStrings.copiedToClipboard : '已导出到 $path',
        tone: ToastTone.success);
  }

  /// 出站分享：把整段对话以 Markdown 文本分享到系统分享面板。
  Future<void> _shareConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    final content = _buildMarkdown(state);
    try {
      await SharePlus.instance
          .share(ShareParams(text: content, subject: state.conversationTitle));
    } catch (e) {
      if (mounted) {
        FloatingToast.error(context, '分享失败', rawDetail: e.toString());
      }
    }
  }
}
