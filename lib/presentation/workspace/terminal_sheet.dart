import 'dart:async';
import '../../application/bounded_log_buffer.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';

import '../../infrastructure/tools/command_tool.dart';
import '../motion/nexus_page_route_factory.dart';
import '../terminal/terminal_page.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/floating_toast.dart';
import 'file_tree_sheet.dart';
import 'terminal_job_panel.dart';

class TerminalSheet extends StatefulWidget {
  const TerminalSheet({
    super.key,
    required this.workspacePath,
    this.onReselectWorkspace,
    this.sharedService,
    this.embedded = false,
  });

  final String workspacePath;
  final bool embedded;

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
  final _logBuffer = BoundedLogBuffer();
  String get _output => _logBuffer.text;
  set _output(String text) {
    _logBuffer.clear();
    _logBuffer.append(text);
  }

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
    _service = widget.sharedService ??
        TerminalCommandService(workspacePath: widget.workspacePath);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final info = await _service.inspectRuntime();
      final session =
          await _service.openSession(workingDirectory: widget.workspacePath);
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
        _runtimeLabel = info.available
            ? '${info.label} · ${info.detail}'
            : '${info.label} 不可用 · ${info.detail}';
      });
      final jobs = _service.listJobs();
      if (jobs.isNotEmpty) await _selectJob(jobs.last.jobId);
    } catch (error) {
      if (mounted) setState(() => _runtimeLabel = '检测失败：$error');
    }
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
    try {
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
    } catch (error) {
      _queueOutput('\n执行失败：$error', flush: true);
      if (mounted) setState(() => _running = false);
    }
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
    final following = !_scrollController.hasClients ||
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 24;
    _pendingChunk = '';
    setState(() => _logBuffer.append(chunk));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (following && _scrollController.hasClients) {
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
      _running = !_service
          .listJobs()
          .firstWhere((job) => job.jobId == jobId,
              orElse: () => const TerminalJobSnapshot(
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

  Future<void> _cancelJob(String jobId) async {
    final stopped = await _service.cancelJob(jobId);
    if (!stopped && mounted) {
      FloatingToast.show(context, '运行时无法确认作业已停止，请检查终端输出');
    }
  }

  void _clearDisplay() {
    setState(() => _output = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jobs = _service.listJobs();
    if (widget.embedded) {
      final colors = DesktopTheme.maybeOf(context)!;
      return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: Tooltip(
                      message: widget.workspacePath,
                      child: Text('手动命令 · $_runtimeLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall))),
              if (jobs.isNotEmpty)
                PopupMenuButton<String>(
                    tooltip: '切换命令作业',
                    onSelected: _selectJob,
                    itemBuilder: (_) => [
                          for (final job in jobs)
                            PopupMenuItem(
                                value: job.jobId,
                                child: Text(
                                    '${job.command} · ${job.completed ? '退出 ${job.exitCode ?? '-'}' : '运行中'}'))
                        ],
                    child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text('${jobs.length} 个作业',
                            style: theme.textTheme.bodySmall))),
              IconButton(
                  tooltip: '清空显示（不停止作业）',
                  onPressed: _clearDisplay,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16)),
            ]),
            Expanded(
                child: Container(
                    width: double.infinity,
                    color: colors.canvas,
                    child: SelectionArea(
                        child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _logBuffer.lines.isEmpty
                                ? 1
                                : _logBuffer.lines.length +
                                    (_logBuffer.droppedCharacters > 0 ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_logBuffer.lines.isEmpty) {
                                return const Text('在当前项目目录执行命令，输出保留在此面板。');
                              }
                              if (_logBuffer.droppedCharacters > 0 &&
                                  index == 0) {
                                return const Text('仅显示最近日志；完整输出可在作业记录中查看。');
                              }
                              final line = index -
                                  (_logBuffer.droppedCharacters > 0 ? 1 : 0);
                              return Text(_logBuffer.lines[line],
                                  style: DesktopTheme.monospaceStyle(context,
                                      size: DesktopTheme.smallSize));
                            })))),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _controller,
                      enabled: !_running,
                      onSubmitted: (_) => _run(),
                      style: DesktopTheme.monospaceStyle(context,
                          size: DesktopTheme.smallSize),
                      decoration: const InputDecoration(
                          hintText: '例如 git status',
                          prefixText: '> ',
                          isDense: true))),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: _running ? '停止当前作业' : '运行命令',
                  onPressed: _running
                      ? () {
                          final id = _activeJobId;
                          if (id != null) _cancelJob(id);
                        }
                      : _run,
                  icon: Icon(
                      _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 16))
            ]),
          ]));
    }
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
                  tooltip: '打开远程交互终端',
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: () {
                    // 先收起 Sheet 再推入全屏页：让整屏转场作用在 Sheet 下方的
                    // 页面上（视差 + 暗化），而不是让 Sheet 自己横移。
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      NexusPageRoute.workspace(
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
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    widget.workspacePath,
                    maxLines: 2,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: '复制项目路径',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: widget.workspacePath),
                    );
                    FloatingToast.show(context, '项目路径已复制');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
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
                    ? AppPalette.terminalSurface
                    : AppPalette.terminalSurfaceHover,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _output.isEmpty
                        ? '可运行 git、flutter、dart、python、node 等受限命令'
                        : _output,
                    style: const TextStyle(
                        color: AppPalette.terminalText,
                        fontFamily: 'monospace',
                        fontSize: AppTokens.fontSizeFootnote,
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
