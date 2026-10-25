import '../theme/desktop_theme.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter/material.dart';

import '../../application/file_citation.dart';
import '../../application/workspace_file_editor.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
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
  final _lineController = TextEditingController(text: '1');
  final _editorFocusNode = FocusNode();
  WorkspaceFileBuffer? _buffer;
  String? _error;
  bool _loading = true;
  bool _dirty = false;
  bool _showJump = false;
  int _line = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_trackChanges);
    _open();
  }

  @override
  void dispose() {
    _controller.removeListener(_trackChanges);
    _controller.dispose();
    _lineController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _trackChanges() {
    final buffer = _buffer;
    if (buffer == null) return;
    final dirty = _controller.text != buffer.content;
    if (dirty != _dirty) setState(() => _dirty = dirty);
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
        _dirty = false;
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
      if (!mounted) return;
      setState(() {
        _buffer = next;
        _dirty = false;
      });
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

  void _jumpToLine(String value) {
    final text = _controller.text;
    final lines = text.split('\n');
    final requested = int.tryParse(value) ?? 1;
    final line = requested.clamp(1, lines.isEmpty ? 1 : lines.length);
    var offset = 0;
    for (var index = 0; index < line - 1; index++) {
      offset += lines[index].length + 1;
    }
    _lineController.text = '$line';
    _lineController.selection = TextSelection.collapsed(
      offset: _lineController.text.length,
    );
    setState(() => _line = line);
    _controller.selection = TextSelection.collapsed(offset: offset);
    _editorFocusNode.requestFocus();
  }

  Future<void> _discardAndPop() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showConfirmAction(
      context,
      title: '放弃未保存的修改？',
      message: '当前文件的修改尚未保存，离开后无法恢复。',
      confirmLabel: '放弃修改',
      isDanger: true,
    );
    if (discard && mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _discardAndPop();
      },
      child: Scaffold(
        appBar: NexusPageHeader(
          title: widget.relativePath,
          subtitle: _buffer == null
              ? null
              : '${_buffer!.encoding} · ${_buffer!.newline} · ${_buffer!.bytes} bytes',
          actions: [
            if (DesktopTheme.maybeOf(context) == null)
              IconButton(
                  tooltip: '跳至行',
                  onPressed: () => setState(() => _showJump = !_showJump),
                  icon: const Icon(Icons.format_list_numbered)),
            if (widget.onCite != null && widget.projectId != null)
              IconButton(
                tooltip: '引用当前行',
                onPressed: _cite,
                icon: const Icon(Icons.format_quote),
              ),
            IconButton(
              tooltip: _dirty ? '保存修改' : '文件已保存',
              onPressed: _buffer == null || !_dirty ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: NexusPageLayout(
            mobileMaxWidth: double.infinity,
            desktopMaxWidth: double.infinity,
            child: AsyncStateView(
              loading: _loading,
              error: _error,
              onRetry: _open,
              child: Column(
                children: [
                  if (_showJump || DesktopTheme.maybeOf(context) != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          const Text('跳至行'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: TextField(
                              controller: _lineController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.go,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '行号',
                              ),
                              onSubmitted: _jumpToLine,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: TextField(
                        controller: _controller,
                        focusNode: _editorFocusNode,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
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
            )),
      ),
    );
  }
}
