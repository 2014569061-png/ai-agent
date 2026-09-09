import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/knowledge_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/files/document_extractor.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
    name.dispose();
    content.dispose();
    if (saved != true || !mounted) return;
    await _ingest(title, 'paste', text);
  }

  Future<void> _delete(KnowledgeDoc doc) async {
    final confirmed = await showConfirmAction(context,
        title: '删除文档？', message: '将删除“${doc.name}”及其索引内容。', confirmLabel: '删除');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [
          IconButton(
            onPressed: _pasteText,
            icon: const Icon(Icons.note_add_outlined),
            tooltip: '粘贴文本入库',
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SectionCard(
            child: SwitchListTile(
              secondary: const Icon(Icons.library_books_outlined),
              title: const Text('启用知识库检索'),
              subtitle: const Text('对话时自动注入相关片段（当前为关键词模式）'),
              value: _enabled,
              onChanged: _toggleEnabled,
            ),
          ),
        ),
        Expanded(
          child: AsyncStateView(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: _docs.isEmpty
                ? const EmptyStateView(
                    icon: Icons.library_books_outlined,
                    title: '知识库为空',
                    message: '上传 PDF/TXT/MD 或点击右上角粘贴文本入库。')
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = _docs[index];
                      return SectionCard(
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(doc.name),
                          subtitle:
                              Text('${doc.chunkCount} 个分块 · ${doc.sourceType}'),
                          trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(doc)),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('上传文档'),
      ),
    );
  }
}
