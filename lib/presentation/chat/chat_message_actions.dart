part of 'chat_page.dart';

extension _ChatMessageActions on _ChatPageState {
  /// 消息长按菜单：助手消息 → 朗读 / 停止朗读 / 复制；用户消息 → 编辑 / 复制。
  Future<void> _showMessageActions(int messageIndex, {Offset? position}) async {
    final snapshot = ref.read(chatControllerProvider);
    if (messageIndex < 0 || messageIndex >= snapshot.messages.length) return;
    final message = snapshot.messages[messageIndex];
    final conversationId = snapshot.conversationId;
    final isUser = message.role == MessageRole.user;
    final tts = TtsService.instance;
    // 朗读只对助手正文开放（不含工具气泡）；平台不支持时不展示入口。
    final canSpeak = message.role == MessageRole.assistant && tts.isAvailable;
    // M10：只有正在朗读的这条消息才显示「停止朗读」。
    final speaking = canSpeak &&
        tts.isSpeaking &&
        _speakingMessageIndex.value == messageIndex;
    // 打开菜单即退出上一条消息的选择模式，避免两个状态并存。
    if (_selectingMessageIndex.value != null) {
      _selectingMessageIndex.value = null;
    }
    final items = <ActionSheetItem<String>>[
      if (canSpeak)
        ActionSheetItem(
          icon: speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
          title: speaking ? AppStrings.stopSpeaking : AppStrings.speakAloud,
          value: 'speak',
        ),
      if (isUser)
        const ActionSheetItem(
          icon: Icons.edit_outlined,
          title: '编辑并重发',
          subtitle: '替换此消息，并重新生成其后的回复',
          value: 'edit',
        ),
      const ActionSheetItem(
        icon: Icons.call_split_outlined,
        title: '新建分支',
        subtitle: '只复制到此的对话上下文，不重放工具、不改文件',
        value: 'fork',
      ),
      const ActionSheetItem(
          icon: Icons.format_quote, title: '引用到输入框', value: 'quote'),
      if (!isUser && !snapshot.running)
        const ActionSheetItem(
            icon: Icons.refresh, title: '重新生成', value: 'regenerate'),
      const ActionSheetItem(
        icon: Icons.copy_outlined,
        title: AppStrings.copyFullText,
        value: 'copy',
      ),
      if (message.role != MessageRole.tool)
        const ActionSheetItem(
          icon: Icons.text_fields_rounded,
          title: AppStrings.selectText,
          subtitle: '进入后可拖动选择局部文本',
          value: 'select',
        ),
    ];
    final action = position != null
        ? await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
                position.dx, position.dy, position.dx, position.dy),
            items: [
                for (final item in items)
                  PopupMenuItem(
                      value: item.value,
                      enabled: item.enabled,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (item.icon != null) ...[
                          Icon(item.icon, size: 16),
                          const SizedBox(width: 10)
                        ],
                        Text(item.title)
                      ]))
              ])
        : await showNexusActionSheet<String>(
            context: context,
            title: AppStrings.messageActions,
            items: items,
            scrollable: true);
    if (!mounted ||
        action == null ||
        ref.read(chatControllerProvider).conversationId != conversationId) {
      return;
    }
    if (action == 'quote') {
      _controller.text +=
          '\n> ${stripRunPauseMarker(message.text).replaceAll('\n', '\n> ')}\n';
    } else if (action == 'regenerate') {
      _regenerate();
    } else if (action == 'edit') {
      await _editAndResend(messageIndex, message);
    } else if (action == 'fork') {
      try {
        await _chat.forkFromMessage(messageIndex,
            messageId: message.id, expectedConversationId: conversationId);
        if (mounted) {
          FloatingToast.show(context, '已新建会话分支，不会重放工具或改文件',
              tone: ToastTone.success);
        }
      } catch (error) {
        if (mounted) {
          FloatingToast.show(context, '无法创建分支：$error', tone: ToastTone.warning);
        }
      }
    } else if (action == 'speak') {
      await _toggleSpeak(stripRunPauseMarker(message.text),
          index: messageIndex);
    } else if (action == 'select') {
      final currentIndex = ref.read(chatControllerProvider).messages.indexWhere(
          (current) => message.id != null
              ? current.id == message.id
              : identical(current, message));
      if (currentIndex >= 0) _selectingMessageIndex.value = currentIndex;
    } else if (action == 'copy') {
      await Clipboard.setData(
          ClipboardData(text: stripRunPauseMarker(message.text)));
      if (mounted) {
        unawaited(HapticFeedback.lightImpact());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制全文'),
            duration: Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// G1：按索引朗读消息（长按菜单与读屏动作共用的入口）。
  void _speakMessageAt(int index) {
    final messages = ref.read(chatControllerProvider).messages;
    if (index < 0 || index >= messages.length) return;
    unawaited(
        _toggleSpeak(stripRunPauseMarker(messages[index].text), index: index));
  }

  /// G1：朗读 / 停止朗读助手消息正文。内容为空或设备不可用时给出提示。
  ///
  /// M10：[index] 为被操作的消息。再次点同一条 → 停止；朗读中点另一条 →
  /// 切换朗读那一条（其按钮此时显示的是「朗读」，行为与之保持一致）。
  Future<void> _toggleSpeak(String markdown, {int? index}) async {
    final tts = TtsService.instance;
    if (tts.isSpeaking &&
        (index == null || _speakingMessageIndex.value == index)) {
      await tts.stop();
      return;
    }
    final content = speakableText(markdown);
    if (content.isEmpty) {
      if (mounted) {
        FloatingToast.show(context, AppStrings.noSpeakableContent);
      }
      return;
    }
    final started = await tts.speak(content);
    // speak() 会先停掉上一段（触发一次 false → 清空索引），因此在其返回后再标记。
    if (started && mounted) _speakingMessageIndex.value = index;
    if (!started && mounted) {
      FloatingToast.show(context, AppStrings.ttsUnsupported);
    }
  }

  /// 编辑用户消息：确认后替换原消息并重新生成其后的回复。
  Future<void> _editAndResend(int messageIndex, ChatMessage message) async {
    final snapshot = ref.read(chatControllerProvider);
    if (snapshot.running) return;
    final conversationId = snapshot.conversationId;
    final controller = TextEditingController(text: message.text);
    final submitted = await showNexusDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('编辑并重发'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入新的内容',
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              MobileTheme.controlRadius(context)),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MobileTheme.brand(context),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              MobileTheme.controlRadius(context)),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('保存并重发'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    final newText = controller.text;
    // Dialog 路由退出动画结束前，TextField 仍可能访问 controller；延后一帧释放，
    // 避免快速点击保存/取消时出现 "used after disposed"。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (submitted != true || !mounted) return;
    await _chat.editAndResend(
      messageIndex: messageIndex,
      messageId: message.id,
      expectedConversationId: conversationId,
      newText: newText,
      approveTool: _approveTool,
    );
  }
}
