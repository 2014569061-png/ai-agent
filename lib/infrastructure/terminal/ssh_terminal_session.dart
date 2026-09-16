import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import 'termux_ssh_credentials.dart';

enum SSHTerminalState {
  disconnected,
  connecting,
  connected,
  error,
}

/// 统一管理与 Termux / Linux SSH 服务的 PTY 交互会话。
class SSHTerminalSession {
  SSHTerminalSession({
    required this.terminal,
    this.config = const SSHTerminalConfig(),
  });

  final Terminal terminal;
  final SSHTerminalConfig config;

  SSHClient? _client;
  SSHSession? _shellSession;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;

  SSHTerminalState _state = SSHTerminalState.disconnected;
  SSHTerminalState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  final _stateController = StreamController<SSHTerminalState>.broadcast();
  Stream<SSHTerminalState> get onStateChanged => _stateController.stream;

  void _setState(SSHTerminalState newState, [String? error]) {
    _state = newState;
    _lastError = error;
    _stateController.add(newState);
  }

  /// 启动 SSH PTY 交互会话
  Future<void> connect({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_state == SSHTerminalState.connecting ||
        _state == SSHTerminalState.connected) {
      return;
    }

    _setState(SSHTerminalState.connecting);
    terminal.write(
        '\r\n\x1b[36m[NEXUS 终端] 正在连接 ${config.host}:${config.port}…\x1b[0m\r\n');

    try {
      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: timeout,
      );

      List<SSHKeyPair>? identities;
      if (config.privateKey != null && config.privateKey!.trim().isNotEmpty) {
        try {
          identities = SSHKeyPair.fromPem(config.privateKey!);
        } catch (_) {
          // 密钥解析失败时回退
        }
      }

      _client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest:
            config.password != null ? () => config.password! : null,
        identities: identities,
      );

      // 申请 PTY 伪终端并启动交互 Shell
      final cols = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      final rows = terminal.viewHeight > 0 ? terminal.viewHeight : 24;

      final session = await _client!.shell(
        pty: SSHPtyConfig(
          width: cols,
          height: rows,
          type: 'xterm-256color',
        ),
      );
      _shellSession = session;

      // 绑定 SSH 输出流 -> Terminal 渲染
      _stdoutSub = session.stdout.listen(
        (data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onError: (e) {
          terminal.write('\r\n\x1b[31m[NEXUS 终端] stdout 流异常: $e\x1b[0m\r\n');
        },
      );

      _stderrSub = session.stderr.listen(
        (data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
      );

      // 绑定 Terminal 用户输入 -> SSH stdin
      terminal.onOutput = (String data) {
        if (_state == SSHTerminalState.connected && _shellSession != null) {
          _shellSession!.stdin.add(Uint8List.fromList(utf8.encode(data)));
        }
      };

      // 绑定终端窗口尺寸缩放 -> PTY SIGWINCH
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (_state == SSHTerminalState.connected && _shellSession != null) {
          _shellSession!.resizeTerminal(width, height, pixelWidth, pixelHeight);
        }
      };

      _setState(SSHTerminalState.connected);
      terminal.write('\x1b[32m[NEXUS 终端] 会话已建立 (PTY 80x24 就绪)\x1b[0m\r\n\r\n');

      // 监听会话结束
      unawaited(session.done.then((_) {
        if (_state == SSHTerminalState.connected) {
          disconnect(reason: '远程会话已正常退出');
        }
      }));
    } catch (e) {
      final errorMsg = e.toString();
      _setState(SSHTerminalState.error, errorMsg);
      terminal.write('\r\n\x1b[31m[NEXUS 终端] 连接失败: $errorMsg\x1b[0m\r\n');
      if (config.isLocalTermux) {
        terminal.write('\x1b[33m[提示] Termux SSH PTY 需要实际用户名：先运行 whoami，'
            '再执行 pkg install -y openssh && passwd && sshd；'
            '请打开 Termux、允许后台运行并关闭电池限制。'
            '环境检测的 RUN_COMMAND 桥与 SSH PTY 是两条独立通道。\x1b[0m\r\n\r\n');
      }
      await _cleanup();
    }
  }

  /// 发送原始 ANSI 字符序列（供辅助键盘调用，例如 TAB, ESC, 方向键, Ctrl+C）
  void sendInput(String input) {
    if (_state == SSHTerminalState.connected && _shellSession != null) {
      _shellSession!.stdin.add(Uint8List.fromList(utf8.encode(input)));
    } else {
      // 离线状态下本地回显提示
      terminal.write(input);
    }
  }

  /// 发送特定控制信号（如 Ctrl+C: \x03）
  void sendCtrl(String char) {
    if (char.isEmpty) return;
    final code = char.toUpperCase().codeUnitAt(0);
    if (code >= 64 && code <= 95) {
      // ASCII 64 ('@') -> \x00, 65 ('A') -> \x01, ..., 67 ('C') -> \x03
      final ctrlChar = String.fromCharCode(code - 64);
      sendInput(ctrlChar);
    }
  }

  /// 断开当前连接并清理资源
  Future<void> disconnect({String? reason}) async {
    if (_state == SSHTerminalState.disconnected) return;
    if (reason != null) {
      terminal.write('\r\n\x1b[33m[NEXUS 终端] $reason\x1b[0m\r\n');
    }
    _setState(SSHTerminalState.disconnected);
    await _cleanup();
  }

  Future<void> _cleanup() async {
    terminal.onOutput = null;
    terminal.onResize = null;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _shellSession?.close();
    } catch (_) {}
    _shellSession = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
  }

  void dispose() {
    unawaited(disconnect());
    _stateController.close();
  }
}
