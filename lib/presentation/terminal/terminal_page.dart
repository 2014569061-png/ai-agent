import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../infrastructure/terminal/ssh_terminal_session.dart';
import '../../infrastructure/terminal/termux_ssh_credentials.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'terminal_accessory_bar.dart';

/// 沉浸式 Linux 终端全屏操作页面。
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    this.initialConfig,
    this.onSendToAgent,
    this.autoConnect = true,
  });

  final SSHTerminalConfig? initialConfig;
  final void Function(String terminalOutput)? onSendToAgent;
  final bool autoConnect;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal _terminal;
  late SSHTerminalSession _session;
  final _storage = TermuxSSHStorage();

  SSHTerminalConfig _config = const SSHTerminalConfig();
  SSHTerminalState _state = SSHTerminalState.disconnected;
  StreamSubscription<SSHTerminalState>? _stateSub;

  double _fontSize = 13.0;
  bool _ctrlActive = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 2000);
    _config = widget.initialConfig ?? const SSHTerminalConfig();
    _session = SSHTerminalSession(
      terminal: _terminal,
      config: _config,
    );
    _state = _session.state;
    _stateSub = _session.onStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _state = state;
        });
      }
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.initialConfig == null) {
      final stored = await _storage.loadConfig();
      if (!mounted) return;
      if (stored.host != _config.host ||
          stored.port != _config.port ||
          stored.username != _config.username ||
          stored.password != _config.password) {
        _config = stored;
        await _session.disconnect();
        _session = SSHTerminalSession(
          terminal: _terminal,
          config: _config,
        );
      }
    }

    // 没有真实的 Termux 用户名时不要用固定占位符发起失败的 SSH 请求。
    if (widget.autoConnect && _config.username.trim().isNotEmpty) {
      unawaited(_session.connect());
    } else if (widget.autoConnect && mounted) {
      _terminal.write(
        '\x1b[33m[NEXUS 终端] 首次使用请先打开设置：在 Termux 执行 whoami，'
        '将输出的 u0_a… 用户名填入 SSH 配置；端口保持 8022。\x1b[0m\r\n'
        '\x1b[33m[提示] 先在 Termux 执行 pkg install -y openssh && passwd && sshd；'
        '允许后台运行并关闭电池限制。\x1b[0m\r\n\r\n',
      );
    }
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    _session.dispose();
    super.dispose();
  }

  void _reconnect() {
    if (_config.isLocalTermux && _config.username.trim().isEmpty) {
      _showConfigSheet();
      return;
    }
    unawaited(_session.connect());
  }

  void _clearTerminal() {
    _terminal.buffer.clear();
    _session.sendCtrl('L');
  }

  void _zoomIn() {
    if (_fontSize < 20.0) {
      setState(() => _fontSize += 1.0);
    }
  }

  void _zoomOut() {
    if (_fontSize > 10.0) {
      setState(() => _fontSize -= 1.0);
    }
  }

  /// 提取当前屏幕日志并转送给 Agent 分析
  void _sendDiagnosticsToAgent() {
    // 提取最后 30 行可见文本作为上下文
    final lines = <String>[];
    final buffer = _terminal.buffer;
    final totalLines = buffer.lines.length;
    final start = totalLines > 30 ? totalLines - 30 : 0;

    for (var i = start; i < totalLines; i++) {
      final line = buffer.lines[i].getText();
      if (line.trim().isNotEmpty) {
        lines.add(line);
      }
    }

    final outputText = lines.join('\n');
    if (outputText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('终端当前没有可提取的输出内容')),
      );
      return;
    }

    if (widget.onSendToAgent != null) {
      widget.onSendToAgent!(outputText);
      Navigator.pop(context);
    } else {
      Clipboard.setData(ClipboardData(
        text: '请分析当前终端输出并帮我诊断解决：\n```bash\n$outputText\n```',
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('终端输出诊断已复制到剪贴板，可粘贴发给 Agent')),
      );
    }
  }

  void _showConfigSheet() {
    final hostCtrl = TextEditingController(text: _config.host);
    final portCtrl = TextEditingController(text: _config.port.toString());
    final userCtrl = TextEditingController(text: _config.username);
    final passCtrl = TextEditingController(text: _config.password ?? '');

    const setupCommand =
        'pkg update && pkg install -y openssh nodejs python git && passwd && whoami && sshd';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Termux / SSH 连接设置',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182030),
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                    border:
                        Border.all(color: AppPalette.darkHairline, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppPalette.brand),
                          SizedBox(width: 6),
                          Text(
                            'Termux SSH/PTY 首次配置命令（只需执行一次）',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const SelectableText(
                        setupCommand,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '执行 whoami 后，把输出的设备专属用户名（通常为 u0_a…）'
                        '填入下方“用户名”；Termux SSH 端口保持 8022。\n'
                        '全屏终端使用 SSH PTY；环境检测使用 RUN_COMMAND 桥，'
                        '两者需要分别配置。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(text: setupCommand),
                            );
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('已复制 Termux 命令到剪贴板')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('复制命令',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: hostCtrl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: '主机 (Host)',
                          labelStyle: TextStyle(color: Colors.white60),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: portCtrl,
                        keyboardType: TextInputType.number,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: '端口 (Port)',
                          labelStyle: TextStyle(color: Colors.white60),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: userCtrl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: '用户名（Termux whoami）',
                          labelStyle: TextStyle(color: Colors.white60),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: passCtrl,
                        obscureText: true,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: '密码（先在 Termux 执行 passwd）',
                          labelStyle: TextStyle(color: Colors.white60),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
                      ),
                    ),
                    onPressed: () async {
                      final updated = _config.copyWith(
                        host: hostCtrl.text.trim().isEmpty
                            ? '127.0.0.1'
                            : hostCtrl.text.trim(),
                        port: int.tryParse(portCtrl.text.trim()) ?? 8022,
                        username: userCtrl.text.trim(),
                        password: passCtrl.text.trim().isEmpty
                            ? null
                            : passCtrl.text.trim(),
                      );
                      if (updated.username.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '请先在 Termux 执行 whoami，并填写实际用户名（通常为 u0_a…）。',
                            ),
                          ),
                        );
                        return;
                      }
                      await _storage.saveConfig(updated);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        setState(() {
                          _config = updated;
                        });
                        await _session.disconnect();
                        _session = SSHTerminalSession(
                          terminal: _terminal,
                          config: updated,
                        );
                        _reconnect();
                      }
                    },
                    child: const Text('保存配置并连接',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator() {
    Color dotColor;
    String statusText;

    switch (_state) {
      case SSHTerminalState.connected:
        dotColor = AppPalette.success;
        statusText = '${_config.host}:${_config.port} • 已连接';
        break;
      case SSHTerminalState.connecting:
        dotColor = AppPalette.warning;
        statusText = '正在连接…';
        break;
      case SSHTerminalState.disconnected:
      case SSHTerminalState.error:
        dotColor = AppPalette.danger;
        statusText = '未连接 (点击重试)';
        break;
    }

    return InkWell(
      onTap:
          _state == SSHTerminalState.connected ? _showConfigSheet : _reconnect,
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border:
              Border.all(color: dotColor.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              statusText,
              style: TextStyle(
                color: dotColor,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.terminalBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F141F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Linux 交互终端',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            _buildStatusIndicator(),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '发送诊断给 Agent',
            icon: const Icon(Icons.smart_toy_outlined, color: AppPalette.brand),
            onPressed: _sendDiagnosticsToAgent,
          ),
          IconButton(
            tooltip: '放大字体',
            icon: const Icon(Icons.zoom_in_rounded),
            onPressed: _zoomIn,
          ),
          IconButton(
            tooltip: '缩小字体',
            icon: const Icon(Icons.zoom_out_rounded),
            onPressed: _zoomOut,
          ),
          IconButton(
            tooltip: '清屏',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearTerminal,
          ),
          IconButton(
            tooltip: '设置与配置向导',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showConfigSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppPalette.terminalBg,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: TerminalView(
                  _terminal,
                  theme: TerminalThemes.defaultTheme,
                  textStyle: TerminalStyle(
                    fontSize: _fontSize,
                    fontFamily: 'monospace',
                  ),
                  autofocus: true,
                ),
              ),
            ),
            TerminalAccessoryBar(
              onSendInput: (input) => _session.sendInput(input),
              onSendCtrl: (char) => _session.sendCtrl(char),
              ctrlActive: _ctrlActive,
              onToggleCtrl: (val) => setState(() => _ctrlActive = val),
            ),
          ],
        ),
      ),
    );
  }
}
