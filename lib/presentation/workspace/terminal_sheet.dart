import 'dart:async';

import 'package:flutter/material.dart';

import '../../infrastructure/tools/command_tool.dart';
import '../widgets/immersive_sheet.dart';
import 'file_tree_sheet.dart';

class TerminalSheet extends StatefulWidget {
  const TerminalSheet({
    super.key,
    required this.workspacePath,
    this.onReselectWorkspace,
  });

  final String workspacePath;

  /// 透传给文件树的“重新选择工作区”回调。
  final VoidCallback? onReselectWorkspace;

  @override
  State<TerminalSheet> createState() => _TerminalSheetState();
}

class _TerminalSheetState extends State<TerminalSheet> {
  late final TerminalCommandService _service;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _output = '';
  bool _running = false;
  String _runtimeLabel = '正在检测 Linux Runtime…';

  @override
  void initState() {
    super.initState();
    _service = TerminalCommandService(workspacePath: widget.workspacePath);
    unawaited(_loadRuntimeInfo());
  }

  Future<void> _loadRuntimeInfo() async {
    final info = await _service.inspectRuntime();
    if (!mounted) return;
    setState(() {
      _runtimeLabel = info.available
          ? '${info.label} · ${info.detail}'
          : '${info.label} 不可用 · ${info.detail}';
    });
  }

  @override
  void dispose() {
    _service.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    final command = _controller.text.trim();
    if (command.isEmpty) return;
    setState(() {
      _running = true;
      _output = '\$ $command\n';
    });
    final result = await _service.run(command);
    if (!mounted) return;
    setState(() {
      _running = false;
      _output += '${result.output}\n[退出码 ${result.exitCode}]';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _stop() {
    _service.stop();
    if (mounted) setState(() => _output += '\n[正在终止命令]');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.terminal_rounded),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('终端管理',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: '查看文件树',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: () {
                    Navigator.pop(context);
                    showImmersiveSheet<void>(
                      context: context,
                      builder: (_) => SizedBox(
                        height: MediaQuery.of(context).size.height * .75,
                        child: FileTreeSheet(
                          workspacePath: widget.workspacePath,
                          onReselectWorkspace: widget.onReselectWorkspace,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: '清空输出',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => setState(() => _output = ''),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.workspacePath,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '运行时：$_runtimeLabel',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF10151D)
                    : const Color(0xFF17202A),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _output.isEmpty
                        ? '可运行 git、flutter、dart、python、node 等受限命令'
                        : _output,
                    style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_running,
                    onSubmitted: (_) => _run(),
                    decoration: const InputDecoration(
                      hintText: '输入命令，例如 git status',
                      prefixText: '\$ ',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: _running ? '停止命令' : '运行命令',
                  onPressed: _running ? _stop : _run,
                  icon: Icon(
                      _running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
