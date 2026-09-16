import 'package:flutter/material.dart';

import '../../application/file_citation.dart';
import '../../application/workspace_file_editor.dart';
import '../theme/app_palette.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';

class WorkspaceEditorPage extends StatefulWidget {
  const WorkspaceEditorPage({
    super.key,
    required this.workspacePath,
    required this.relativePath,
    this.projectId,
    this.onCite,
  });

  final String workspacePath;
  final String relativePath;
  final String? projectId;
  final ValueChanged<FileCitation>? onCite;

  @override
  State<WorkspaceEditorPage> createState() => _WorkspaceEditorPageState();
}

class _WorkspaceEditorPageState extends State<WorkspaceEditorPage> {
  final _editor = const WorkspaceFileEditor();
  final _controller = TextEditingController();
  WorkspaceFileBuffer? _buffer;
  String? _error;
  bool _loading = true;
  int _line = 1;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final buffer = await _editor.open(
        workspacePath: widget.workspacePath,
        relativePath: widget.relativePath,
      );
      if (!mounted) return;
      _controller.text = buffer.content;
      setState(() {
        _buffer = buffer;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final original = _buffer;
    if (original == null) return;
    try {
      final next = await _editor.save(
        workspacePath: widget.workspacePath,
        original: original,
        content: _controller.text,
      );
      setState(() => _buffer = next);
      if (mounted) {
        FloatingToast.show(context, '已保存 ${next.relativePath}',
            tone: ToastTone.success);
      }
    } on ConcurrentEditException {
      if (mounted) {
        FloatingToast.show(context, '文件已被其他进程修改，请重新载入后再保存',
            tone: ToastTone.warning);
      }
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '保存失败：$error', tone: ToastTone.danger);
      }
    }
  }

  Future<void> _cite() async {
    final buffer = _buffer;
    final projectId = widget.projectId;
    if (buffer == null || projectId == null) return;
    final citation = await _editor.citeSelection(
      projectId: projectId,
      buffer: buffer,
      startLine: _line,
      endLine: _line,
    );
    widget.onCite?.call(citation);
    if (mounted) Navigator.pop(context, citation);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: NexusPageHeader(
        title: widget.relativePath,
        subtitle: _buffer == null
            ? null
            : '${_buffer!.encoding} · ${_buffer!.newline} · ${_buffer!.bytes} bytes',
        actions: [
          if (widget.onCite != null && widget.projectId != null)
            IconButton(
              tooltip: '引用当前行',
              onPressed: _cite,
              icon: const Icon(Icons.format_quote),
            ),
          IconButton(
            tooltip: '保存',
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          const Text('跳行'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '行号',
                              ),
                              onSubmitted: (value) {
                                final line = int.tryParse(value) ?? 1;
                                setState(() => _line = line);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.45,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
