import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../infrastructure/observability/unified_diff.dart'
    show redactSensitiveText;
import 'bounded_log_buffer.dart';
import 'desktop_preview_service.dart';

class DesktopRunConfiguration {
  const DesktopRunConfiguration({required this.command, required this.url});
  final String command, url;
  Uri get previewUrl => DesktopPreviewServer.parseUrl(url);
  Future<void> save(String root) async {
    previewUrl;
    if (command.trim().isEmpty || command.length > 8000) {
      throw ArgumentError('请输入有效的启动命令');
    }
    await (await SharedPreferences.getInstance()).setString(
        'desktop.run.$root', jsonEncode({'command': command, 'url': url}));
  }

  static Future<DesktopRunConfiguration?> load(String root) async {
    final data =
        (await SharedPreferences.getInstance()).getString('desktop.run.$root');
    if (data == null) return null;
    final map = jsonDecode(data) as Map<String, dynamic>;
    return DesktopRunConfiguration(
        command: map['command'] as String, url: map['url'] as String);
  }
}

class DesktopRunService extends ChangeNotifier {
  static final instance = DesktopRunService();
  final Map<String, Process> _processes = {};
  final Map<String, BoundedLogBuffer> _logs = {};
  final Map<String, int> exitCodes = {};
  final Set<String> _starting = {};
  bool running(String root) =>
      _processes.containsKey(root) || _starting.contains(root);
  String output(String root) => _logs[root]?.text ?? '';
  Future<void> start(String root, DesktopRunConfiguration config) async {
    if (running(root)) throw StateError('当前项目已经运行');
    if (!await Directory(root).exists()) throw StateError('项目目录不存在');
    config.previewUrl;
    _starting.add(root);
    notifyListeners();
    final log = _logs[root] = BoundedLogBuffer();
    try {
      final process = await Process.start(
          Platform.isWindows ? 'powershell.exe' : '/bin/sh',
          Platform.isWindows
              ? [
                  '-NoLogo',
                  '-NoProfile',
                  '-NonInteractive',
                  '-Command',
                  config.command
                ]
              : ['-c', config.command],
          workingDirectory: root,
          runInShell: false);
      _processes[root] = process;
      if (Platform.isWindows) {
        try {
          await const MethodChannel('nexus/desktop_process')
              .invokeMethod<void>('trackProcess', {'pid': process.pid});
        } on MissingPluginException {
          /* Host-only tests do not have process tracking. */
        } catch (_) {
          process.kill();
          rethrow;
        }
      }
      void append(String text) {
        log.append(redactSensitiveText(text));
        notifyListeners();
      }

      final stdout = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(append);
      final stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(append);
      unawaited(() async {
        final code = await process.exitCode;
        await stdout.cancel();
        await stderr.cancel();
        if (identical(_processes[root], process)) {
          _processes.remove(root);
          exitCodes[root] = code;
          append('\n[启动命令退出 $code]');
        }
      }());
    } finally {
      _starting.remove(root);
      notifyListeners();
    }
  }

  Future<void> stop(String root) async {
    final process = _processes[root];
    if (process == null) return;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F'],
          runInShell: false);
    }
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
    if (identical(_processes[root], process)) _processes.remove(root);
    notifyListeners();
  }

  Future<void> stopAll() async {
    for (final root in _processes.keys.toList()) {
      await stop(root);
    }
  }

  Future<void> waitReady(String root, Uri uri,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request =
              await client.getUrl(uri).timeout(const Duration(seconds: 2));
          final response =
              await request.close().timeout(const Duration(seconds: 2));
          await response.drain<void>().timeout(const Duration(seconds: 2));
          if (response.statusCode < 500) return;
        } catch (_) {
          /* Development servers may not have opened their port yet. */
        }
        if (!running(root)) throw StateError('开发服务器已退出，请查看启动日志');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      throw StateError('等待开发服务器超时，请检查地址、端口与启动日志');
    } finally {
      client.close(force: true);
    }
  }
}
