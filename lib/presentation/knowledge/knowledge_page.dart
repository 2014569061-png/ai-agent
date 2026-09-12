import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
import '../widgets/immersive_sheet.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

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
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _docs = docs;
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
    await ref.read(knowledgeServiceProvider).setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _ingest(String name, String sourceType, String content) async {
    if (content.trim().isEmpty) {
      FloatingToast.show(context, '内容为空，未入库');
      return;
    }
    final db = await ref.read(databaseProvider.future);
    await ref
        .read(knowledgeServiceProvider)
        .ingest(db: db, name: name, sourceType: sourceType, content: content);
    await _load();
    if (mounted) FloatingToast.show(context, '已入库：$name');
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'json'],
    );
    if (result == null || !mounted) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final content = const DocumentExtractor()
              .extractText(fileName: file.name, bytes: bytes) ??
          '';
      if (content.trim().isEmpty) {
        if (mounted) FloatingToast.show(context, '文件 ${file.name} 未提取到文本');
        continue;
      }
      await _ingest(file.name, 'file', content);
    }
  }

  Future<void> _pasteText() async {
    final name = TextEditingController();
    final content = TextEditingController();
    final saved = await showImmersiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴文本入库'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '标题')),
            const SizedBox(height: 12),
            TextField(
                controller: content,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '内容')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('入库')),
        ],
      ),
    );
    final title = name.text.trim().isEmpty ? '粘贴文本' : name.text.trim();
    final text = content.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      content.dispose();
    });
    if (saved != true || !mounted) return;
    await _ingest(title, 'paste', text);
  }

  Future<void> _delete(KnowledgeDoc doc) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除文档？',
      message: '确定要删除此文档及其所有切片内容吗？删除后将无法通过知识库检索该内容。',
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
      await db.deleteKnowledgeDoc(doc.id);
      await _load();
      if (mounted) FloatingToast.show(context, '文档已删除');
    } catch (error) {
      if (mounted) FloatingToast.show(context, '删除失败：$error');
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
    final sourceLabel = isFile ? '文件导入' : (isPaste ? '手动粘贴' : doc.sourceType);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurface,
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                      border: Border.all(
                        color: isDark
                            ? AppPalette.darkHairline
                            : AppPalette.lightHairline,
                      ),
                    ),
                    child: Icon(
                      isFile
                          ? Icons.description_outlined
                          : Icons.content_paste_rounded,
                      size: 20,
                      color: AppPalette.brandAction,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: '删除文档',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _delete(doc),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurface,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      border: Border.all(
                        color: isDark
                            ? AppPalette.darkHairline
                            : AppPalette.lightHairline,
                      ),
                    ),
                    child: Text(
                      sourceLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppPalette.darkTextMuted
                            : AppPalette.lightTextMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.brand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: Text(
                      '${doc.chunkCount} 分块',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppPalette.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 12, color: AppPalette.success),
                        SizedBox(width: 3),
                        Text(
                          'BM25 已索引',
                          style: TextStyle(
                            fontSize: 11,
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
                      fontSize: 11,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _docs.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.name.toLowerCase().contains(_searchQuery) ||
          d.sourceType.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: '知识库',
        subtitle: '文档切片检索与 RAG 管理',
        actions: [
          IconButton(
            onPressed: _pasteText,
            icon: const Icon(Icons.note_add_outlined, size: 20),
            tooltip: '粘贴文本入库',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SectionCard(
              child: SwitchListTile(
                secondary: const Icon(Icons.library_books_outlined),
                title: const Text(
                  '启用知识库检索',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                subtitle: const Text(
                  '对话时自动注入相关片段（当前为 BM25 本地检索模式）',
                  style: TextStyle(fontSize: 13),
                ),
                value: _enabled,
                onChanged: _toggleEnabled,
              ),
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _searchQuery = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: '搜索文档名称或来源...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppPalette.darkTextMuted
                        : AppPalette.lightTextMuted,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  filled: true,
                  fillColor:
                      isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppPalette.darkHairline
                          : AppPalette.lightHairline,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppPalette.darkHairline
                          : AppPalette.lightHairline,
                    ),
                  ),
                ),
              ),
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
                      message:
                          '支持上传 TXT/MD/CSV/JSON 文档或粘贴文本，切片后可用于 Agent 对话时的 RAG 检索增强',
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _buildDocCard(filtered[index], isDark),
                        )),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadFile,
        backgroundColor: AppPalette.brandAction,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('上传文档'),
      ),
    );
  }
}
