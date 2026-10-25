import 'dart:async';
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

/// Only known server commands or explicit numeric placeholders may be retargeted.
/// In particular, an arbitrary npm script must not be given guessed CLI flags.
class PreviewLaunchCommand {
  const PreviewLaunchCommand(this.template);
  final String template;

  bool get isPythonHttp => RegExp(
        r'^python3? -m http\.server(?: [0-9]+)?(?: --bind (?:127\.0\.0\.1|0\.0\.0\.0|localhost))?$',
      ).hasMatch(template.trim().replaceAll(RegExp(r'\s+'), ' '));

  bool get canConfigure =>
      isPythonHttp ||
      (template.contains('{port}') &&
          template.contains('{host}') &&
          !template.contains(r'${port}') &&
          !template.contains(r'${host}'));

  String render({required int port, required String bindHost}) {
    if (!canConfigure) {
      throw const FormatException(
        '不能安全配置自定义预览命令。请明确使用 {port} 和 {host} 占位符，'
        '例如 python -m http.server {port} --bind {host}；不猜测 npm 脚本的参数。',
      );
    }
    if (isPythonHttp) {
      final executable = template.trim().split(RegExp(r'\s+')).first;
      return '$executable -m http.server $port --bind $bindHost';
    }
    return template
        .replaceAll('{port}', '$port')
        .replaceAll('{host}', bindHost);
  }
}

class PreviewService {
  PreviewService({
    TerminalCommandService? terminal,
    String workspacePath = '.',
    Future<bool> Function(int port)? waitForPort,
    Future<bool> Function(int port)? isPortBusy,
    Future<bool> Function(Uri target)? probeHttp,
    Future<String> Function()? lanHost,
    this.readinessTimeout = const Duration(seconds: 8),
    this.pollInterval = const Duration(milliseconds: 200),
  })  : _terminal =
            terminal ?? TerminalCommandService(workspacePath: workspacePath),
        _waitForPortOverride = waitForPort,
        _isPortBusyOverride = isPortBusy,
        _probeHttpOverride = probeHttp,
        _lanHostOverride = lanHost;

  final TerminalCommandService _terminal;
  final Future<bool> Function(int port)? _waitForPortOverride;
  final Future<bool> Function(int port)? _isPortBusyOverride;
  final Future<bool> Function(Uri target)? _probeHttpOverride;
  final Future<String> Function()? _lanHostOverride;
  final Duration readinessTimeout;
  final Duration pollInterval;
  PreviewSession? _active;
  Future<PreviewSession>? _starting;
  Future<void>? _stopping;
  String? _startingProject;
  String? _pendingJobId;
  int _generation = 0;

  PreviewSession? get active => _active;

  Future<PreviewSession> start({
    required String projectId,
    required String workspacePath,
    required String command,
    int preferredPort = 8765,
    bool allowLan = false,
    String runtimeId = 'local',
  }) {
    if (_stopping != null) {
      return Future.error(StateError('预览正在停止，请稍后重试'));
    }
    final current = _active;
    if (current != null) {
      if (current.projectId == projectId) return Future.value(current);
      return Future.error(StateError('已有其他项目的预览服务在运行：${current.projectId}'));
    }
    if (_starting != null) {
      if (_startingProject == projectId) return _starting!;
      return Future.error(StateError('已有其他项目的预览服务正在启动：$_startingProject'));
    }
    if (_pendingJobId != null) {
      return Future.error(StateError('上次预览作业停止状态未知，请先停止作业：$_pendingJobId'));
    }
    _startingProject = projectId;
    final generation = ++_generation;
    late final Future<PreviewSession> operation;
    operation = _start(
      projectId: projectId,
      workspacePath: workspacePath,
      launch: PreviewLaunchCommand(command),
      preferredPort: preferredPort,
      allowLan: allowLan,
      runtimeId: runtimeId,
      generation: generation,
    ).whenComplete(() {
      if (identical(_starting, operation)) {
        _starting = null;
        _startingProject = null;
      }
    });
    _starting = operation;
    return operation;
  }

  Future<PreviewSession> _start({
    required String projectId,
    required String workspacePath,
    required PreviewLaunchCommand launch,
    required int preferredPort,
    required bool allowLan,
    required String runtimeId,
    required int generation,
  }) async {
    if (preferredPort < 1 || preferredPort > 65535) {
      throw const FormatException('预览端口必须在 1–65535 之间');
    }
    final bindHost = allowLan ? '0.0.0.0' : '127.0.0.1';
    final displayHost =
        allowLan ? await (_lanHostOverride ?? _lanHost)() : '127.0.0.1';
    _checkGeneration(generation);
    if (allowLan && displayHost == '127.0.0.1') {
      throw StateError('未找到局域网 IPv4 地址，请关闭局域网预览后重试');
    }
    var port = preferredPort;
    if (await _portBusy(port, bindHost)) {
      if (!launch.canConfigure) {
        throw StateError('预览端口 $port 已占用，不能安全改写自定义命令；请使用 {port} 和 {host} 占位符');
      }
      port = await _findFreePort(preferredPort, bindHost);
    }
    _checkGeneration(generation);
    final command = launch.render(port: port, bindHost: bindHost);
    final target = Uri.parse('http://127.0.0.1:$port/');
    String? jobId;
    try {
      final job = await _terminal.startJob(
        command: command,
        workingDirectory: workspacePath,
        // Preview is a server, not a short foreground command.
        timeout: const Duration(days: 1),
      );
      jobId = job.jobId;
      _pendingJobId = jobId;
      _checkGeneration(generation);
      await _waitForReady(target, jobId, generation);
      _checkGeneration(generation);
      final session = PreviewSession(
        projectId: projectId,
        jobId: jobId,
        runtimeId: runtimeId,
        host: displayHost,
        port: port,
        url: 'http://$displayHost:$port/',
        lanEnabled: allowLan,
      );
      _active = session;
      _pendingJobId = null;
      return session;
    } catch (error) {
      if (jobId != null) {
        if (!await _terminal.cancelJob(jobId)) {
          // Keep the handle: failure must not enable a second untracked server.
          throw StateError('$error；无法确认预览作业已停止：$jobId，请先重试停止');
        }
        if (_pendingJobId == jobId) _pendingJobId = null;
      }
      rethrow;
    }
  }

  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    ++_generation;
    late final Future<void> operation;
    operation = _stopCurrent().whenComplete(() {
      if (identical(_stopping, operation)) _stopping = null;
    });
    _stopping = operation;
    return operation;
  }

  Future<void> _stopCurrent() async {
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // Start owns cleanup; retry any handle whose cancellation was unconfirmed.
      }
    }
    final jobId = _pendingJobId ?? _active?.jobId;
    if (jobId == null) return;
    if (!await _terminal.cancelJob(jobId)) {
      throw StateError('无法确认预览作业已停止：$jobId');
    }
    _pendingJobId = null;
    _active = null;
  }

  void _checkGeneration(int generation) {
    if (_generation != generation) throw StateError('预览启动已取消');
  }

  void _checkJob(String jobId) {
    for (final job in _terminal.listJobs()) {
      if (job.jobId != jobId) continue;
      if (job.completed) {
        throw StateError('预览作业已退出（exit ${job.exitCode}）：$jobId');
      }
      return;
    }
    throw StateError('无法确认预览作业状态：$jobId');
  }

  Future<void> _waitForReady(Uri target, String jobId, int generation) async {
    final deadline = DateTime.now().add(readinessTimeout);
    var wasReady = false;
    while (DateTime.now().isBefore(deadline)) {
      _checkGeneration(generation);
      _checkJob(jobId);
      var ready = false;
      try {
        final probe = _waitForPortOverride != null
            ? _waitForPortOverride(target.port)
            : (_probeHttpOverride ?? _probeHttp)(target);
        ready = await probe.timeout(deadline.difference(DateTime.now()));
      } catch (_) {
        // Connection refusal and malformed/non-HTTP responses are not readiness.
      }
      _checkGeneration(generation);
      _checkJob(jobId);
      // A second HTTP response after a poll interval rules out a transient
      // listener immediately followed by job failure. TCP connectivity alone
      // never marks a preview ready.
      if (ready && wasReady) return;
      wasReady = ready;
      await Future<void>.delayed(pollInterval);
    }
    throw StateError(
        '预览 HTTP 服务 $target 未在 ${readinessTimeout.inMilliseconds}ms 内就绪');
  }

  Future<bool> _probeHttp(Uri target) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 500);
    try {
      final request = await client
          .openUrl('HEAD', target)
          .timeout(const Duration(milliseconds: 500));
      request.followRedirects = false;
      final response =
          await request.close().timeout(const Duration(milliseconds: 500));
      return response.statusCode >= 200 && response.statusCode < 500;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _portBusy(int port, String bindHost) async {
    if (_isPortBusyOverride != null) return _isPortBusyOverride(port);
    try {
      final socket = await ServerSocket.bind(InternetAddress(bindHost), port);
      await socket.close();
      return false;
    } on SocketException {
      return true;
    }
  }

  Future<int> _findFreePort(int start, String bindHost) async {
    for (var port = start + 1; port <= 65535 && port < start + 20; port++) {
      if (!await _portBusy(port, bindHost)) return port;
    }
    final socket = await ServerSocket.bind(InternetAddress(bindHost), 0);
    final port = socket.port;
    await socket.close();
    return port;
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
    } catch (_) {
      // Failure is handled before launching; never silently expose a LAN server.
    }
    return '127.0.0.1';
  }
}
