import 'dart:async';

import 'package:flutter/material.dart';

import '../../infrastructure/tools/command_tool.dart';
import '../terminal/terminal_page.dart';
import '../widgets/nexus_sheet.dart';
import 'file_tree_sheet.dart';
import 'terminal_job_panel.dart';

class TerminalSheet extends StatefulWidget {
  const TerminalSheet({
    super.key,
    required this.workspacePath,
    this.onReselectWorkspace,
    this.sharedService,
  });

  final String workspacePath;

  /// 透传给文件树的“重新选择工作区”回调。
  final VoidCallback? onReselectWorkspace;

  /// 项目页可注入同一个 TerminalCommandService，关闭页签时保留受管理作业。
  final TerminalCommandService? sharedService;

  @override
  State<TerminalSheet> createState() => _TerminalSheetState();
}

class _TerminalSheetState extends State<TerminalSheet> {
  late final TerminalCommandService _service;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _output = '';
  bool _running = false;
  String? _activeJobId;
  int _lastSequence = -1;
  StreamSubscription<TerminalJobEvent>? _jobSub;
  Timer? _flushTimer;
  String _pendingChunk = '';
  String _runtimeLabel = '正在检测 Linux Runtime…';
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _service =
        widget.sharedService ?? TerminalCommandService(workspacePath: widget.workspacePath);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final info = await _service.inspectRuntime();
    final session = await _service.openSession(workingDirectory: widget.workspacePath);
    if (!mounted) return;
    setState(() {
      _sessionId = session.id;
      _runtimeLabel = info.available
          ? '${info.label} · ${info.detail}'
          : '${info.label} 不可用 · ${info.detail}';
    });
  }

  @override
  void dispose() {
    unawaited(_jobSub?.cancel());
    _flushTimer?.cancel();
    // 关闭页签只取消 UI 订阅，不 stop() 受管理作业。
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    final command = _controller.text.trim();
    if (command.isEmpty) return;
    await _jobSub?.cancel();
    setState(() {
      _running = true;
      _output = '\$ $command\n';
      _lastSequence = -1;
      _pendingChunk = '';
    });
    final handle = await _service.startJob(
      command: command,
      workingDirectory: widget.workspacePath,
    );
    _activeJobId = handle.jobId;
    if (!handle.liveOutput) {
      _queueOutput('运行中，完成后返回日志\n');
    }
    _jobSub = _service.watchJob(handle.jobId).listen((event) {
      if (event.sequence <= _lastSequence) return;
      _lastSequence = event.sequence;
      if (event.type == 'started') return;
      if (event.type == 'completed' || event.type == 'timeout') {
        _queueOutput('\n[退出码 ${event.exitCode ?? -1}]', flush: true);
        if (mounted) setState(() => _running = false);
        return;
      }
      _queueOutput(event.payload);
    });
  }

  void _queueOutput(String chunk, {bool flush = false}) {
    _pendingChunk += chunk;
    if (flush) {
      _flushOutput();
      return;
    }
    _flushTimer ??= Timer(const Duration(milliseconds: 150), _flushOutput);
  }

  void _flushOutput() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!mounted || _pendingChunk.isEmpty) return;
    final chunk = _pendingChunk;
    _pendingChunk = '';
    setState(() => _output += chunk);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _selectJob(String jobId) async {
    await _jobSub?.cancel();
    _activeJobId = jobId;
    _lastSequence = -1;
    setState(() {
      _output = '';
      _running = !_service.listJobs()
          .firstWhere((job) => job.jobId == jobId, orElse: () =>
              const TerminalJobSnapshot(
                  jobId: '', command: '', completed: true))
          .completed;
    });
    _jobSub = _service.watchJob(jobId).listen((event) {
      if (event.sequence <= _lastSequence) return;
      _lastSequence = event.sequence;
      if (event.type == 'started') {
        _queueOutput('\$ ${event.payload}\n');
        return;
      }
      if (event.type == 'completed' || event.type == 'timeout') {
        _queueOutput('\n[退出码 ${event.exitCode ?? -1}]', flush: true);
        if (mounted) setState(() => _running = false);
        return;
      }
      _queueOutput(event.payload);
    });
  }

  void _cancelJob(String jobId) {
    unawaited(_service.cancelJob(jobId));
    if (jobId == _activeJobId && mounted) {
      setState(() => _running = false);
    }
  }

  void _clearDisplay() {
    setState(() => _output = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jobs = _service.listJobs();
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
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                ),
                IconButton(
                  tooltip: '打开全屏交互终端 (PTY)',
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TerminalPage(),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: '查看文件树',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: () {
                    Navigator.pop(context);
                    showNexusSheet<void>(
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
                  tooltip: '清空显示（不停止作业）',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _clearDisplay,
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
                '运行时：$_runtimeLabel'
                '${_sessionId == null ? '' : ' · 会话 $_sessionId'}',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            TerminalJobPanel(
              jobs: jobs,
              activeJobId: _activeJobId,
              onSelect: _selectJob,
              onCancel: _cancelJob,
            ),
            const SizedBox(height: 8),
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
                  tooltip: _running ? '停止当前作业' : '运行命令',
                  onPressed: _running
                      ? () {
                          final id = _activeJobId;
                          if (id != null) _cancelJob(id);
                        }
                      : _run,
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
