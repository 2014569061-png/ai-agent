import '../widgets/nexus_search_field.dart';
import '../theme/mobile_theme.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:drift/drift.dart' show OrderingTerm;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_resource_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/knowledge_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/document_extractor.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/nexus_switch.dart';
import '../../application/local_error_copy.dart';

/// 知识库 / RAG 管理页（C4）：文档列表 + 上传/粘贴 + 删除 + 总开关。
class KnowledgePage extends ConsumerStatefulWidget {
  const KnowledgePage({super.key});

  @override
  ConsumerState<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends ConsumerState<KnowledgePage> {
  bool _loading = true;
  Object? _error;
  bool _enabled = true;
  List<KnowledgeDoc> _docs = [];
  Map<String, String> _scopes = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final service = ref.read(knowledgeServiceProvider);
      final enabled = await service.isEnabled();
      final docs = await db.allKnowledgeDocs();
      final scopes = await db.knowledgeDocumentScopes();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _docs = docs;
        _scopes = scopes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    try {
      await ref.read(knowledgeServiceProvider).setEnabled(value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) FloatingToast.show(context, '开关未保存，请重试');
    }
  }

  Future<bool> _ingest(String name, String sourceType, String content) async {
    if (content.trim().isEmpty) {
      FloatingToast.show(context, '内容为空，未入库');
      return false;
    }
    final db = await ref.read(databaseProvider.future);
    final projects = await db.allProjects();
    if (!mounted) return false;
    final selectedScope = await showNexusDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
                title: const Text('资料可用范围'),
                backgroundColor: Theme.of(dialogContext)
                    .colorScheme
                    .surface
                    .withValues(alpha: 1),
                children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('项目资料只供本项目会话检索；知识管理和全量搜索仍是你的全库视图。取消不会入库。')),
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, ''),
                      child: const Text('全局 · 所有会话可用')),
                  for (final project in projects)
                    SimpleDialogOption(
                        onPressed: () =>
                            Navigator.pop(dialogContext, project.id),
                        child: Text('项目 · ${project.name}')),
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消')),
                ]));
    if (selectedScope == null) return false;
    await ref.read(knowledgeServiceProvider).ingest(
        db: db,
        name: name,
        sourceType: sourceType,
        content: content,
        projectId: selectedScope.isEmpty ? null : selectedScope);
    await _load();
    if (mounted) FloatingToast.show(context, '已入库：$name');
    return true;
  }

  Future<void> _uploadFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'json'],
    );
    if (!mounted) return;
    for (final file in picked) {
      // file_picker 13 已移除 withData，字节改为按需读取。
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        continue;
      }
      final content = const DocumentExtractor()
              .extractText(fileName: file.name, bytes: bytes) ??
          '';
      if (content.trim().isEmpty) {
        if (mounted) FloatingToast.show(context, '文件 ${file.name} 未提取到文本');
        continue;
      }
      try {
        await _ingest(file.name, 'file', content);
      } catch (_) {
        if (mounted) FloatingToast.show(context, '文件入库未确认，请保留原文件并刷新核实');
      }
    }
  }

  Future<void> _pasteText() async {
    final name = TextEditingController();
    final content = TextEditingController();
    var saving = false;
    var confirming = false;
    String? error;
    try {
      await showNexusDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (dialogContext, setDialogState) {
                Future<void> cancel() async {
                  if (saving || confirming) return;
                  if (name.text.isNotEmpty || content.text.isNotEmpty) {
                    confirming = true;
                    final discard = await showConfirmAction(dialogContext,
                        title: '放弃未入库文本？',
                        message: '输入尚未入库，放弃后不会保留。可先取消返回并复制草稿。',
                        confirmLabel: '放弃修改',
                        isDanger: true);
                    confirming = false;
                    if (!discard) return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, false);
                  }
                }

                Future<void> save() async {
                  if (saving) return;
                  setDialogState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    if (content.text.trim().isEmpty) {
                      throw const FormatException('请输入需要入库的文本');
                    }
                    final title =
                        name.text.trim().isEmpty ? '粘贴文本' : name.text.trim();
                    final saved = await _ingest(title, 'paste', content.text);
                    if (!dialogContext.mounted) return;
                    if (saved) {
                      Navigator.pop(dialogContext, true);
                    } else {
                      setDialogState(() {
                        saving = false;
                      });
                    }
                  } on FormatException catch (e) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        saving = false;
                        error = e.message;
                      });
                    }
                  } catch (_) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        saving = false;
                        error = '入库未确认，草稿已保留。请先复制草稿并刷新核实，避免重复入库。';
                      });
                    }
                  }
                }

                return PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, result) {
                      if (!didPop) cancel();
                    },
                    child: AlertDialog(
                        title: const Text('粘贴文本入库'),
                        backgroundColor: Theme.of(dialogContext)
                            .colorScheme
                            .surface
                            .withValues(alpha: 1),
                        content: SizedBox(
                            width: double.maxFinite,
                            child: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  TextField(
                                      controller: name,
                                      enabled: !saving,
                                      maxLength: 256,
                                      decoration: const InputDecoration(
                                          labelText: '标题')),
                                  const SizedBox(height: 12),
                                  TextField(
                                      controller: content,
                                      enabled: !saving,
                                      maxLines: 6,
                                      maxLength:
                                          KnowledgeService.maxContentChars,
                                      decoration: const InputDecoration(
                                          labelText: '内容')),
                                  if (error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(dialogContext)
                                                .colorScheme
                                                .error)),
                                  ],
                                  TextButton(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              try {
                                                await Clipboard.setData(
                                                    ClipboardData(
                                                        text:
                                                            '${name.text}\n${content.text}'));
                                              } catch (_) {
                                                if (dialogContext.mounted) {
                                                  FloatingToast.show(
                                                      dialogContext,
                                                      '复制失败，草稿仍保留');
                                                }
                                              }
                                            },
                                      child: const Text('复制未入库草稿')),
                                ]))),
                        actions: [
                          TextButton(
                              onPressed: saving ? null : cancel,
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: saving ? null : save,
                              child: Text(saving ? '正在入库…' : '入库'))
                        ]));
              }));
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        name.dispose();
        content.dispose();
      });
    }
  }

  Future<void> _delete(KnowledgeDoc doc) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除文档？',
      message: '删除本地文档、全部切片并使本地检索索引失效。不会删除导入原文件，也不会撤回历史消息、已发送上下文或备份/外部副本。',
      confirmLabel: '删除',
      isDanger: true,
      bulletItems: [
        '文档名称：${doc.name}',
        '切片数量：${doc.chunkCount} 个分块',
        '来源类型：${doc.sourceType == "file" ? "文件导入" : (doc.sourceType == "paste" ? "手动粘贴" : doc.sourceType)}',
      ],
    );
    if (!confirmed || !mounted) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await ref.read(knowledgeServiceProvider).delete(
            db: db,
            documentId: doc.id,
          );
      await _load();
      if (mounted) FloatingToast.show(context, '文档已删除');
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '删除').headline());
    }
  }

  Future<void> _showSource(KnowledgeDoc selected) async {
    try {
      final db = await ref.read(databaseProvider.future);
      final doc = await db.findKnowledgeDoc(selected.id);
      if (!mounted) return;
      if (doc == null) {
        FloatingToast.show(context, '文档已删除，请刷新列表');
        return;
      }
      final chunks = await (db.select(db.knowledgeChunks)
            ..where((row) => row.docId.equals(doc.id))
            ..orderBy([(row) => OrderingTerm.asc(row.index)])
            ..limit(21))
          .get();
      if (!mounted) return;
      await showNexusDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('本地资料来源'),
                content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: SingleChildScrollView(
                        child: SelectableText([
                      '名称：${doc.name}',
                      '文档标识：${doc.id}',
                      '来源类型：${doc.sourceType}',
                      '会话检索范围：${_scopes[doc.id] == null ? '全局' : '项目 ${_scopes[doc.id]}'}',
                      '更新时间（UTC）：${doc.updatedAt.toUtc().toIso8601String()}',
                      '仅展示当前本地副本；不代表已验证原文件仍存在或内容权威。',
                      if (chunks.isEmpty) '没有可用分块；不应声称已完成索引。',
                      for (final chunk in chunks.take(20))
                        '\n分块 ${chunk.index + 1} · ${chunk.id}\n${chunk.content}',
                      if (chunks.length > 20) '\n仅预览前 20 个分块，未加载完整文档。',
                    ].join('\n')))),
                actions: [
                  if (chunks.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _correctChunk(chunks.first);
                      },
                      child: const Text('更正首段分块'),
                    ),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'))
                ],
              ));
    } catch (_) {
      if (mounted) FloatingToast.show(context, '读取本地来源失败，请重试');
    }
  }

  Future<void> _correctChunk(KnowledgeChunk chunk) async {
    final controller = TextEditingController(text: chunk.content);
    try {
      final updated = await showNexusDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('更正知识分块 · #${chunk.index + 1}'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '分块内容',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('保存更正'),
            ),
          ],
        ),
      );
      if (updated == null || updated.isEmpty || !mounted) return;
      final db = await ref.read(databaseProvider.future);
      await ref.read(knowledgeServiceProvider).correctChunkContent(
            db: db,
            chunkId: chunk.id,
            newContent: updated,
          );
      await _load();
      if (mounted) {
        FloatingToast.show(context, '已保存知识分块更正并刷新索引');
      }
    } catch (error) {
      if (mounted) FloatingToast.show(context, LocalErrorCopy.of(error, action: '更正').headline());
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  String _formatDate(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Widget _buildDocCard(KnowledgeDoc doc, bool isDark) {
    final isFile = doc.sourceType == 'file';
    final isPaste = doc.sourceType == 'paste';
    final sourceLabel =
        '${isFile ? '文件导入' : (isPaste ? '手动粘贴' : doc.sourceType)} · ${_scopes[doc.id] == null ? '全局' : '项目 ${_scopes[doc.id]}'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        glass: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.brandSoftDark
                          : AppPalette.brandSoftLight,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : MobileTheme.brand(context)
                                .withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      isFile
                          ? Icons.description_outlined
                          : Icons.content_paste_rounded,
                      size: 20,
                      color: MobileTheme.brand(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: AppTokens.fontSizeBody,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: '删除文档',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _delete(doc),
                  ),
                ],
              ),
              TextButton.icon(
                  onPressed: () => _showSource(doc),
                  icon: const Icon(Icons.source_outlined, size: 16),
                  label: const Text('查看本地来源与分块')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.70),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      sourceLabel,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppPalette.darkTextMuted
                            : AppPalette.lightTextMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.brandSoftDark
                          : AppPalette.brandSoftLight,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : MobileTheme.brand(context)
                                .withValues(alpha: 0.20),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '${doc.chunkCount} 分块',
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: MobileTheme.brand(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSuccessSoft
                          : AppPalette.lightSuccessSoft,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: isDark
                            ? AppPalette.success.withValues(alpha: 0.25)
                            : AppPalette.success.withValues(alpha: 0.20),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 12, color: AppPalette.success),
                        SizedBox(width: 3),
                        Text(
                          'BM25 按需检索',
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeBadge,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 12,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    '更新于 ${_formatDate(doc.updatedAt)}',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBadge,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopKnowledge() => DesktopResourceView<KnowledgeDoc>(
        title: '知识库',
        icon: Icons.library_books_outlined,
        description: '管理本地文档与文本分块，为会话提供 BM25 检索上下文。',
        items: _docs,
        loading: _loading,
        error: _error,
        onReload: _load,
        searchHint: '搜索文档名称或来源',
        searchText: (doc) =>
            '${doc.name} ${doc.sourceType} ${_scopes[doc.id] ?? '全局'}',
        filters: [
          DesktopResourceFilter('文件导入', (doc) => doc.sourceType == 'file'),
          DesktopResourceFilter('粘贴文本', (doc) => doc.sourceType == 'paste')
        ],
        sorts: [
          DesktopResourceSort(
              '最近更新', (a, b) => b.updatedAt.compareTo(a.updatedAt)),
          DesktopResourceSort('名称 A–Z',
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
          DesktopResourceSort(
              '分块数：多到少', (a, b) => b.chunkCount.compareTo(a.chunkCount))
        ],
        banner: Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
                title: const Text('在对话中启用知识库检索'),
                subtitle:
                    const Text('BM25 本地检索，命中片段随请求发送给当前模型服务；不代表模型已读取所有文档。'),
                value: _enabled,
                onChanged: _loading || _error != null ? null : _toggleEnabled)),
        actions: [
          FilledButton.icon(
              onPressed: _uploadFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('上传文档')),
          OutlinedButton.icon(
              onPressed: _pasteText,
              icon: const Icon(Icons.content_paste_outlined),
              label: const Text('粘贴文本'))
        ],
        emptyTitle: '知识库还没有文档',
        emptyMessage: '上传 TXT、MD、CSV、JSON 文件，或粘贴文本建立检索资料。',
        itemBuilder: (context, doc) => DesktopResourceCard(
          key: ValueKey('desktop-document-${doc.id}'),
          title: doc.name,
          icon: doc.sourceType == 'file'
              ? Icons.description_outlined
              : Icons.content_paste_outlined,
          metadata: [
            doc.sourceType == 'file'
                ? '文件导入'
                : doc.sourceType == 'paste'
                    ? '粘贴文本'
                    : doc.sourceType,
            '${doc.chunkCount} 分块',
            '更新于 ${_formatDate(doc.updatedAt)}'
          ],
          actions: [
            OutlinedButton.icon(
                onPressed: () => _showSource(doc),
                icon: const Icon(Icons.source_outlined, size: 16),
                label: const Text('查看本地来源与分块')),
            TextButton.icon(
                onPressed: () => _delete(doc),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除文档'))
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopKnowledge();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _docs.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.name.toLowerCase().contains(_searchQuery) ||
          d.sourceType.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: NexusPageHeader(
        title: '知识库',
        subtitle: '在对话中检索你的资料',
        actions: [
          IconButton(
            onPressed: _pasteText,
            icon: const Icon(Icons.note_add_outlined, size: 20),
            tooltip: '粘贴文本入库',
          ),
        ],
      ),
      body: NexusPageLayout(
          child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SectionCard(
              child: NexusSwitchListTile(
                secondary: const Icon(Icons.library_books_outlined),
                title: const Text(
                  '启用知识库检索',
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: AppTokens.fontSizeBody),
                ),
                subtitle: const Text(
                  '资料在本地检索；命中片段会随请求发送给当前模型服务。',
                  style: TextStyle(fontSize: AppTokens.fontSizeCaption),
                ),
                value: _enabled,
                onChanged: _toggleEnabled,
              ),
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: NexusSearchField(
              controller: _searchController,
              hintText: '搜索文档名称或来源…',
              onChanged: (value) =>
                  setState(() => _searchQuery = value.trim().toLowerCase()),
              onClear: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AsyncStateView(
              loading: _loading,
              error: _error,
              onRetry: _load,
              child: _docs.isEmpty
                  ? EmptyStateView(
                      icon: Icons.library_books_outlined,
                      title: '知识库为空',
                      message: '上传 TXT、MD、CSV、JSON 文档或粘贴文本，让助手在对话中查找相关资料。',
                      actionLabel: '上传文档',
                      onAction: _uploadFile,
                    )
                  : (filtered.isEmpty
                      ? EmptyStateView(
                          icon: Icons.search_off_rounded,
                          title: '未找到相关文档',
                          message: '没有匹配 "$_searchQuery" 的文档',
                          actionLabel: '清空搜索',
                          onAction: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 104),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _buildDocCard(filtered[index], isDark),
                        )),
            ),
          ),
        ],
      )),
      floatingActionButton: !_loading && _error == null && _docs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _uploadFile,
              backgroundColor: MobileTheme.brand(context),
              foregroundColor: Colors.white,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(MobileTheme.controlRadius(context)),
              ),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('上传文档'),
            ),
    );
  }
}
