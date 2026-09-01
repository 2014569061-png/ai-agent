import '../l10n/app_strings.dart';
import '../widgets/floating_toast.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/conversation_exporter.dart';
import '../../infrastructure/providers/provider_config.dart';
import '../agents/agents_page.dart';
import '../history/history_page.dart';
import '../markdown/code_block.dart';
import '../prompts/prompt_library_page.dart';
import '../settings/settings_page.dart';
import '../widgets/tool_call_card.dart';

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(text),
      ],
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _attachments = <PlatformFile>[];

  ChatController get _chat => ref.read(chatControllerProvider.notifier);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // --- 操作 ---

  Future<void> _send() async {
    final state = ref.read(chatControllerProvider);
    final text = _controller.text.trim();
    if (text.isEmpty || state.running || state.loading) return;
    _controller.clear();
    final attachments = List<PlatformFile>.of(_attachments);
    _attachments.clear();
    await _chat.send(text: text, attachments: attachments, approveTool: _approveTool);
  }

  void _regenerate() {
    _chat.regenerate(approveTool: _approveTool);
  }

  void _stop() => _chat.stop();

  void _startNewConversation() => _chat.newConversation();

  String _buildMarkdown(ChatState state) {
    final content = StringBuffer('# ${state.conversationTitle}\n\n');
    for (final message in state.messages) {
      final role = switch (message.role) {
        MessageRole.user => '用户',
        MessageRole.assistant => '助手',
        MessageRole.system => '系统',
        MessageRole.tool => '工具',
      };
      content.write('## $role\n\n${message.text}\n\n');
    }
    return content.toString();
  }

  Future<void> _copyConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _buildMarkdown(state)));
    if (mounted) FloatingToast.show(context, AppStrings.conversationCopied);
  }

  Future<void> _exportConversation() async {
    final state = ref.read(chatControllerProvider);
    if (state.messages.isEmpty) return;
    final content = _buildMarkdown(state);
    final path = await exportConversationMarkdown(state.conversationTitle, content);
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    FloatingToast.show(context, kIsWeb || path.isEmpty ? AppStrings.copiedToClipboard : '已导出到 $path');
  }

  Future<void> _switchProvider() async {
    final store = ref.read(providerConfigStoreProvider);
    final currentId = ref.read(chatControllerProvider).activeProviderId;
    final profiles = await store.loadAll();
    if (!mounted) return;
    final selected = await showModalBottomSheet<ProviderConfig>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text(AppStrings.switchProvider), leading: Icon(Icons.tune)),
            if (profiles.isEmpty)
              const ListTile(subtitle: Text(AppStrings.noProviderConfigured)),
            ...profiles.map((profile) => ListTile(
                  leading: Icon(profile.id == currentId ? Icons.radio_button_checked : Icons.radio_button_off),
                  title: Text(profile.name),
                  subtitle: Text(profile.model),
                  onTap: () => Navigator.pop(context, profile),
                )),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _chat.switchProvider(selected);
    if (mounted) FloatingToast.show(context, '已切换到 ${selected.name} / ${selected.model}');
  }

  Future<void> _pickFiles() async {
    final state = ref.read(chatControllerProvider);
    if (state.running) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'txt', 'md', 'csv', 'json', 'pdf']);
    if (result == null || !mounted) return;
    setState(() => _attachments.addAll(result.files));
  }

  Future<bool> _approveTool(ToolCall call, ToolRisk risk) async {
    if (!mounted) return false;
    final danger = risk == ToolRisk.dangerous;
    final riskColor = danger ? const Color(0xFFDC2626) : const Color(0xFFF59E0B);
    final riskLabel = danger ? AppStrings.dangerOperation : AppStrings.requiresConfirmation;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: riskColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                  child: Icon(danger ? Icons.warning_amber_rounded : Icons.shield_outlined, color: riskColor),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppStrings.confirmToolCall, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text(AppStrings.requiresAuthorization, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: riskColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: riskColor.withValues(alpha: 0.4))),
                child: Row(children: [
                  Icon(Icons.build_circle_outlined, size: 16, color: riskColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(call.name, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700))),
                  Text(riskLabel, style: TextStyle(color: riskColor, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 12),
              Text(AppStrings.toolArguments, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(child: SelectableText(_prettyJson(call.arguments), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text(AppStrings.reject))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: riskColor), onPressed: () => Navigator.pop(context, true), child: const Text(AppStrings.allowOnce))),
              ]),
            ],
          ),
        ),
      ),
    );
    return approved ?? false;
  }

  String _prettyJson(Map<String, dynamic> value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  Future<void> _selectAgent() async {
    final state = ref.read(chatControllerProvider);
    final database = await ref.read(databaseProvider.future);
    final agents = await database.allAgents();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Agent>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text(AppStrings.selectAgent), leading: Icon(Icons.smart_toy_outlined)),
            ...agents.map((agent) => ListTile(
                  leading: CircleAvatar(child: Icon(agent.id == state.agentId ? Icons.check : Icons.smart_toy_outlined)),
                  title: Text(agent.name),
                  subtitle: Text(agent.systemPrompt, maxLines: 1, overflow: TextOverflow.ellipsis),
                  selected: agent.id == state.agentId,
                  onTap: () => Navigator.pop(context, agent),
                )),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _chat.selectAgent(selected);
  }

  Future<void> _openHistory() async {
    final state = ref.read(chatControllerProvider);
    if (state.running) return;
    final selected = await Navigator.of(context).push<Conversation>(
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
    if (selected == null || !mounted) return;
    await _chat.switchConversation(selected);
  }

  Future<void> _openPromptLibrary() async {
    final result = await Navigator.of(context).push<PromptApplyResult>(
      MaterialPageRoute(builder: (_) => const PromptLibraryPage()),
    );
    if (result == null || !mounted) return;
    if (result.mode == PromptApplyMode.systemPrompt) {
      _chat.setSystemPrompt(result.content);
      FloatingToast.show(context, AppStrings.applyAsSystemPrompt);
    } else {
      _controller.text = result.content;
      _controller.selection = TextSelection.collapsed(offset: result.content.length);
      FloatingToast.show(context, AppStrings.insertedToInput);
    }
  }

  // --- 渲染 ---

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = ['帮我写一段代码', '分析一个 PDF 文件', '总结这段文字', '翻译一段内容'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 18),
          Text(AppStrings.startNewAgentTask, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF102A43))),
          const SizedBox(height: 8),
          Text(AppStrings.pickDirectionOrTypeTask, style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF627D98))),
          const SizedBox(height: 24),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: suggestions.map((text) => ActionChip(label: Text(text), onPressed: () { _controller.text = text; _controller.selection = TextSelection.collapsed(offset: text.length); })).toList()),
        ]),
      ),
    );
  }

  Widget _messageBubble(BuildContext context, ChatMessage message, {required bool isLast, required bool running}) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;
    final isTool = message.role == MessageRole.tool;
    final assistantTextColor = theme.brightness == Brightness.dark ? const Color(0xFFEDF1F8) : const Color(0xFF243B53);
    final imageParts = message.parts.where((part) => part.type == 'image').toList();
    final hasText = message.parts.any((part) => part.type == 'text' && part.value.trim().isNotEmpty);
    final body = isUser
        ? SelectableText(message.text, style: const TextStyle(color: Colors.white, height: 1.45))
        : MarkdownBody(
            data: message.text,
            selectable: true,
            shrinkWrap: true,
            builders: {'pre': CodeBlockBuilder()},
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(p: TextStyle(color: assistantTextColor, height: 1.5)),
          );
    // 图片附件渲染为缩略图，文本部分独立成行（避免 base64 字符串被当作文本显示）。
    final content = imageParts.isEmpty
        ? body
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final part in imageParts) ...[
              _imageAttachment(part.value),
              if (hasText) const SizedBox(height: 6),
            ],
            if (hasText) body,
          ]);
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
      if (!isUser) ...[CircleAvatar(radius: 16, backgroundColor: isTool ? theme.colorScheme.secondary : theme.colorScheme.primary, child: Icon(isTool ? Icons.handyman_outlined : Icons.auto_awesome, size: 17, color: Colors.white)), const SizedBox(width: 8)],
      ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (MediaQuery.sizeOf(context).width < 640 ? .86 : .68)), child: IntrinsicWidth(child: DecoratedBox(decoration: BoxDecoration(color: isUser ? theme.colorScheme.primary : isTool ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surface, borderRadius: BorderRadius.circular(18), border: isUser ? null : Border.all(color: theme.colorScheme.outlineVariant), boxShadow: const [BoxShadow(color: Color(0x0D1A4B84), blurRadius: 8, offset: Offset(0, 2))]), child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 8, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Align(alignment: Alignment.centerLeft, child: content),
        if (!isUser && _hasMeta(message))
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_metaLabel(message), style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
            ),
          ),
        if (!isUser) Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(visualDensity: VisualDensity.compact, iconSize: 16, onPressed: () => Clipboard.setData(ClipboardData(text: message.text)), icon: const Icon(Icons.copy_outlined), tooltip: '复制'),
          if (isLast && message.role == MessageRole.assistant && !running)
            IconButton(visualDensity: VisualDensity.compact, iconSize: 16, onPressed: _regenerate, icon: const Icon(Icons.refresh), tooltip: AppStrings.regenerate),
        ]),
      ]))))),
      if (isUser) const SizedBox(width: 8),
    ]));
  }

  bool _hasMeta(ChatMessage message) =>
      message.modelName != null || message.elapsed != null || (message.usage?.totalTokens ?? 0) > 0;

  /// 把 `data:<mime>;base64,<bytes>` 解码为缩略图；解码失败/非法数据降级为占位文本，绝不显示原始字符串。
  Widget _imageAttachment(String dataUri) {
    final comma = dataUri.indexOf(',');
    final encoded = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
    try {
      final bytes = base64Decode(encoded);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: 180,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Text('[图片解码失败]'),
        ),
      );
    } catch (_) {
      return const Text('[图片解码失败]');
    }
  }

  String _metaLabel(ChatMessage message) {
    final parts = <String>[];
    if (message.modelName != null) parts.add(message.modelName!);
    if (message.elapsed != null) parts.add('${(message.elapsed!.inMilliseconds / 1000).toStringAsFixed(1)}s');
    if ((message.usage?.totalTokens ?? 0) > 0) parts.add('${message.usage!.totalTokens} tokens');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    if (state.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(leading: IconButton(onPressed: _openHistory, icon: const Icon(Icons.menu)), title: Text(state.conversationTitle), actions: [
        IconButton(onPressed: _startNewConversation, icon: const Icon(Icons.add_comment_outlined), tooltip: AppStrings.newConversation),
        IconButton(onPressed: _openPromptLibrary, icon: const Icon(Icons.auto_stories_outlined), tooltip: 'Prompt 库'),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'regenerate':
                _regenerate();
              case 'switchModel':
                _switchProvider();
              case 'copy':
                _copyConversation();
              case 'export':
                _exportConversation();
              case 'agents':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AgentsPage()));
              case 'settings':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'regenerate',
              enabled: !state.running && state.messages.isNotEmpty && state.messages.last.role == MessageRole.assistant,
              child: const _MenuLabel(icon: Icons.refresh, text: AppStrings.regenerate),
            ),
            const PopupMenuItem(value: 'switchModel', child: _MenuLabel(icon: Icons.tune, text: AppStrings.switchModel)),
            PopupMenuItem(
              value: 'copy',
              enabled: state.messages.isNotEmpty,
              child: const _MenuLabel(icon: Icons.content_copy_outlined, text: AppStrings.copyConversation),
            ),
            PopupMenuItem(
              value: 'export',
              enabled: state.messages.isNotEmpty,
              child: const _MenuLabel(icon: Icons.ios_share, text: AppStrings.exportMarkdown),
            ),
            const PopupMenuItem(value: 'agents', child: _MenuLabel(icon: Icons.smart_toy_outlined, text: 'Agent 管理')),
            const PopupMenuItem(value: 'settings', child: _MenuLabel(icon: Icons.settings_outlined, text: '设置')),
          ],
        ),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 4, children: [ActionChip(avatar: const Icon(Icons.smart_toy_outlined, size: 18), label: Text(state.agentName), onPressed: _selectAgent), ActionChip(avatar: Icon(state.providerConfigured ? Icons.check_circle : Icons.science_outlined, size: 16), label: Text(state.providerConfigured ? '${state.activeProviderName} / ${state.activeModel}' : AppStrings.demoModeUnconfigured), onPressed: _switchProvider)]))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('当前 Agent：${state.agentName}  ·  本地直连模式', style: const TextStyle(fontSize: 12, color: Color(0xFF627D98))),
          ),
        ),
        if (state.toolActivities.isNotEmpty)
          ...state.toolActivities.map((activity) => ToolCallCard(activity: activity)),
        if (state.activityLog.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(state.activityLog.last, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        Expanded(child: state.messages.isEmpty ? _emptyState(context) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: state.messages.length, itemBuilder: (context, index) {
           return _messageBubble(context, state.messages[index], isLast: index == state.messages.length - 1, running: state.running);
        })),
        if (_attachments.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _attachments.map((file) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip(label: Text(file.name), onDeleted: () => setState(() => _attachments.remove(file))),
              )).toList(),
            ),
          ),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: Card(elevation: 3, shadowColor: const Color(0x221769E0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Row(children: [
          IconButton(onPressed: _pickFiles, icon: const Icon(Icons.attach_file), tooltip: AppStrings.addFile),
          Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: AppStrings.inputTaskHint, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: state.running ? _stop : _send,
            icon: state.running ? const Icon(Icons.stop) : const Icon(Icons.arrow_upward),
            tooltip: state.running ? '停止生成' : '发送',
          ),
        ]))))),
      ]),
    );
  }
}
