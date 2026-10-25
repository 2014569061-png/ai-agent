import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../../application/desktop_pty_session.dart';

/// User-controlled Windows shell. Agent tool approvals remain independent.
class DesktopTerminalPanel extends StatefulWidget {
  const DesktopTerminalPanel({super.key, required this.workspacePath});
  final String workspacePath;
  @override
  State<DesktopTerminalPanel> createState() => _DesktopTerminalPanelState();
}

class _DesktopTerminalPanelState extends State<DesktopTerminalPanel> {
  late DesktopPtySession _session;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _session = DesktopPtySessions.instance.forWorkspace(widget.workspacePath);
  }

  @override
  void didUpdateWidget(covariant DesktopTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath) {
      _session = DesktopPtySessions.instance.forWorkspace(widget.workspacePath);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _session,
      builder: (_, child) => Column(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Expanded(
                      child: Text(widget.workspacePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall)),
                  PopupMenuButton<String>(
                      tooltip: '选择终端 Shell',
                      initialValue: _session.shell,
                      onSelected: _session.connected ||
                              _session.opening ||
                              _session.closing
                          ? null
                          : (shell) => setState(() => _session.shell = shell),
                      itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'powershell', child: Text('PowerShell')),
                            PopupMenuItem(value: 'cmd', child: Text('命令提示符'))
                          ],
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(_session.shell))),
                  if (!_session.connected)
                    TextButton(
                        onPressed: _session.opening || _session.closing
                            ? null
                            : () async {
                                await _session.open();
                                if (mounted) _focus.requestFocus();
                              },
                        child: Text(_session.opening ? '启动中…' : '启动终端')),
                  if (_session.connected) ...[
                    IconButton(
                        tooltip: '中断 Ctrl+C',
                        onPressed: () => _session.write('\x03'),
                        icon: const Icon(Icons.stop_circle_outlined, size: 16)),
                    IconButton(
                        tooltip: '粘贴',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            await _session.write(data!.text!);
                          }
                        },
                        icon: const Icon(Icons.content_paste, size: 16)),
                    IconButton(
                        tooltip: '停止终端及子进程',
                        onPressed: _session.closing
                            ? null
                            : () async {
                                try {
                                  await _session.close();
                                } catch (_) {
                                  // The session retains the native binding and exposes the error for retry.
                                }
                              },
                        icon: const Icon(Icons.close, size: 16)),
                  ],
                ])),
            if (_session.error != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_session.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            Expanded(
                child: TerminalView(_session.terminal,
                    focusNode: _focus,
                    autofocus: false,
                    theme: TerminalThemes.defaultTheme,
                    textStyle: const TerminalStyle(
                        fontSize: 12, fontFamily: 'Consolas'))),
          ]));
}
