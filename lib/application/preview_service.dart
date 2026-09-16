import 'dart:io';

import '../infrastructure/tools/command_tool.dart';

class PreviewSession {
  const PreviewSession({
    required this.projectId,
    required this.jobId,
    required this.runtimeId,
    required this.host,
    required this.port,
    required this.url,
    this.lanEnabled = false,
  });

  final String projectId;
  final String jobId;
  final String runtimeId;
  final String host;
  final int port;
  final String url;
  final bool lanEnabled;
}

class PreviewService {
  PreviewService({
    TerminalCommandService? terminal,
    String workspacePath = '.',
    Future<bool> Function(int port)? waitForPort,
    Future<bool> Function(int port)? isPortBusy,
  })  : _terminal =
            terminal ?? TerminalCommandService(workspacePath: workspacePath),
        _waitForPortOverride = waitForPort,
        _isPortBusyOverride = isPortBusy;

  final TerminalCommandService _terminal;
  final Future<bool> Function(int port)? _waitForPortOverride;
  final Future<bool> Function(int port)? _isPortBusyOverride;
  PreviewSession? _active;

  PreviewSession? get active => _active;

  Future<PreviewSession> start({
    required String projectId,
    required String workspacePath,
    required String command,
    int preferredPort = 8765,
    bool allowLan = false,
    String runtimeId = 'local',
  }) async {
    if (_active != null && _active!.projectId != projectId) {
      throw StateError('已有其他项目的预览服务在运行：${_active!.projectId}');
    }
    var port = preferredPort;
    if (await (_isPortBusyOverride ?? _isPortBusy)(port)) {
      port = await _findFreePort(preferredPort);
    }
    final displayHost = allowLan ? await _lanHost() : '127.0.0.1';
    final job = await _terminal.startJob(
      command: command,
      workingDirectory: workspacePath,
    );
    final ready = await (_waitForPortOverride ?? _waitForPort)(port);
    if (!ready) {
      await _terminal.cancelJob(job.jobId);
      throw StateError('预览端口 $port 未就绪');
    }
    _active = PreviewSession(
      projectId: projectId,
      jobId: job.jobId,
      runtimeId: runtimeId,
      host: displayHost,
      port: port,
      url: 'http://$displayHost:$port/',
      lanEnabled: allowLan,
    );
    return _active!;
  }

  Future<void> stop() async {
    final current = _active;
    if (current == null) return;
    await _terminal.cancelJob(current.jobId);
    _active = null;
  }

  Future<bool> _isPortBusy(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 250));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _findFreePort(int start) async {
    for (var port = start; port < start + 20; port++) {
      if (!await _isPortBusy(port)) return port;
    }
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<bool> _waitForPort(int port) async {
    for (var i = 0; i < 20; i++) {
      if (await _isPortBusy(port)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<String> _lanHost() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
