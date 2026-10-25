import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/preview_service.dart';
import 'package:mobile_agent/application/project_template_service.dart';
import 'package:mobile_agent/infrastructure/terminal/host_process_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

class _Terminal extends TerminalCommandService {
  _Terminal() : super(workspacePath: '.');
  int starts = 0;
  int cancels = 0;
  String command = '';
  bool completed = false;
  int? exitCode;
  bool canCancel = true;
  Future<void> Function()? beforeStart;
  void Function()? onStart;

  @override
  Future<TerminalJobHandle> startJob({
    required String command,
    String? workingDirectory,
    String? taskId,
    String? runId,
    Duration timeout = TerminalCommandService.defaultTimeout,
  }) async {
    starts++;
    this.command = command;
    await beforeStart?.call();
    completed = false;
    exitCode = null;
    onStart?.call();
    return TerminalJobHandle(jobId: 'preview-$starts');
  }

  @override
  List<TerminalJobSnapshot> listJobs() => [
        TerminalJobSnapshot(
            jobId: 'preview-$starts',
            command: command,
            completed: completed,
            exitCode: exitCode),
      ];

  @override
  Future<bool> cancelJob(String jobId) async {
    cancels++;
    if (canCancel) completed = true;
    return canCancel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PreviewSession> start(
    PreviewService service, {
    String command = 'python -m http.server 8765',
    int port = 9000,
    bool lan = false,
    String project = 'p',
  }) =>
      service.start(
          projectId: project,
          workspacePath: '.',
          command: command,
          preferredPort: port,
          allowLan: lan);

  PreviewService fake(
    _Terminal terminal, {
    Future<bool> Function(Uri)? probe,
    Future<bool> Function(int)? busy,
    Duration timeout = const Duration(milliseconds: 150),
  }) =>
      PreviewService(
          terminal: terminal,
          probeHttp: probe ?? (_) async => true,
          isPortBusy: busy ?? (_) async => false,
          lanHost: () async => '192.0.2.10',
          readinessTimeout: timeout,
          pollInterval: const Duration(milliseconds: 2));

  test('free selected port drives the command, HTTP probe and URL', () async {
    final terminal = _Terminal();
    final targets = <Uri>[];
    final service = fake(terminal, probe: (target) async {
      targets.add(target);
      return true;
    });
    final session = await start(service);
    expect(terminal.command, 'python -m http.server 9000 --bind 127.0.0.1');
    expect(targets, everyElement(Uri.parse('http://127.0.0.1:9000/')));
    expect(targets.length, 2);
    expect(session.url, 'http://127.0.0.1:9000/');
    await service.stop();
  });

  test('occupied ports use the same injectable availability check for fallback',
      () async {
    final terminal = _Terminal();
    final service =
        fake(terminal, busy: (port) async => port == 9000 || port == 9001);
    final session = await start(service);
    expect(session.port, 9002);
    expect(terminal.command, contains('9002 --bind 127.0.0.1'));
    expect(session.url, 'http://127.0.0.1:9002/');
    await service.stop();
  });

  test('LAN mode changes actual binding but probes loopback and displays LAN',
      () async {
    final terminal = _Terminal();
    final targets = <Uri>[];
    final service = fake(terminal, probe: (target) async {
      targets.add(target);
      return true;
    });
    final session = await start(service,
        lan: true, command: 'node index.js --port {port} --host {host}');
    expect(terminal.command, 'node index.js --port 9000 --host 0.0.0.0');
    expect(targets.every((target) => target.host == '127.0.0.1'), isTrue);
    expect(session.url, 'http://192.0.2.10:9000/');
    expect(session.lanEnabled, isTrue);
    await service.stop();
  });

  test('invalid port and missing LAN address never launch a job', () async {
    final terminal = _Terminal();
    final service = fake(terminal);
    await expectLater(start(service, port: 0), throwsFormatException);
    await expectLater(start(service, port: 65536), throwsFormatException);
    final noLan =
        PreviewService(terminal: terminal, lanHost: () async => '127.0.0.1');
    await expectLater(start(noLan, lan: true), throwsStateError);
    expect(terminal.starts, 0);
  });

  test('unsafe custom command reports occupied port instead of guessing flags',
      () async {
    final terminal = _Terminal();
    final service = fake(terminal, busy: (_) async => true);
    await expectLater(
        start(service, command: 'npm start'),
        throwsA(isA<StateError>().having(
            (error) => error.message, 'message', contains('9000 已占用'))));
    expect(terminal.starts, 0);
  });

  test('unconfigured custom command cannot claim a loopback or LAN binding',
      () async {
    final terminal = _Terminal();
    final service = fake(terminal);
    await expectLater(
        start(service, command: 'npm start'), throwsFormatException);
    await expectLater(
        start(service, command: r'node app.js --port ${port} --host ${host}'),
        throwsFormatException);
    expect(terminal.starts, 0);
  });

  test('immediate exit is failure even when another HTTP server responds',
      () async {
    final terminal = _Terminal()..onStart = null;
    terminal.onStart = () {
      terminal.completed = true;
      terminal.exitCode = 23;
    };
    var probes = 0;
    final service = fake(terminal, probe: (_) async {
      probes++;
      return true;
    });
    await expectLater(
        start(service),
        throwsA(isA<StateError>()
            .having((error) => error.message, 'message', contains('exit 23'))));
    expect(probes, 0);
    expect(terminal.cancels, 1);
    expect(service.active, isNull);
  });

  test('slow startup waits for two stable HTTP responses', () async {
    final terminal = _Terminal();
    var probes = 0;
    final service = fake(terminal, probe: (_) async => ++probes >= 3);
    await start(service);
    expect(probes, 4);
    await service.stop();
  });

  test('exit after first HTTP response is not reported ready', () async {
    final terminal = _Terminal();
    final service = fake(terminal, probe: (_) async {
      terminal.completed = true;
      terminal.exitCode = 1;
      return true;
    });
    await expectLater(start(service), throwsStateError);
    expect(service.active, isNull);
    expect(terminal.cancels, 1);
  });

  test('readiness timeout cancels the exact job and leaves no active session',
      () async {
    final terminal = _Terminal();
    final service = fake(terminal,
        probe: (_) async => false, timeout: const Duration(milliseconds: 15));
    await expectLater(start(service), throwsStateError);
    expect(terminal.cancels, 1);
    expect(service.active, isNull);
  });

  test('repeated starts coalesce, and repeated stops do not double-cancel',
      () async {
    final terminal = _Terminal();
    final service = fake(terminal);
    final first = start(service);
    final second = start(service);
    expect(identical(first, second), isTrue);
    await expectLater(start(service, project: 'other'), throwsStateError);
    final session = await first;
    expect(await second, same(session));
    expect(await start(service), same(session));
    expect(terminal.starts, 1);
    final stop1 = service.stop();
    final stop2 = service.stop();
    expect(identical(stop1, stop2), isTrue);
    await stop1;
    expect(terminal.cancels, 1);
  });

  test('stop during delayed launch drains and cancels the late job', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final terminal = _Terminal()
      ..beforeStart = () {
        entered.complete();
        return gate.future;
      };
    final service = fake(terminal);
    final starting = start(service);
    final rejected = expectLater(
        starting,
        throwsA(isA<StateError>()
            .having((error) => error.message, 'message', contains('已取消'))));
    await entered.future;
    final stopping = service.stop();
    await expectLater(start(service), throwsStateError);
    gate.complete();
    await rejected;
    await stopping;
    expect(terminal.starts, 1);
    expect(terminal.cancels, 1);
    expect(service.active, isNull);
  });

  test(
      'unknown cancellation retains handle and blocks a replacement until stopped',
      () async {
    final terminal = _Terminal()..canCancel = false;
    var ready = false;
    final service = fake(terminal,
        probe: (_) async => ready, timeout: const Duration(milliseconds: 15));
    await expectLater(
        start(service),
        throwsA(isA<StateError>()
            .having((error) => error.message, 'message', contains('无法确认'))));
    await expectLater(start(service), throwsStateError);
    expect(terminal.starts, 1);
    terminal.canCancel = true;
    await service.stop();
    ready = true;
    await start(service);
    expect(terminal.starts, 2);
    await service.stop();
  });

  test('failed active stop retains the session for a confirmed retry',
      () async {
    final terminal = _Terminal();
    final service = fake(terminal);
    final session = await start(service);
    terminal.canCancel = false;
    await expectLater(service.stop(), throwsStateError);
    expect(service.active, same(session));
    expect(await start(service), same(session));
    expect(terminal.starts, 1);
    terminal.canCancel = true;
    await service.stop();
    expect(service.active, isNull);
  });

  test('TCP-only listener is not HTTP readiness', () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final socketServer =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = socketServer.listen((socket) {
      socket.write('not an HTTP response\r\n');
      unawaited(socket.close());
    });
    addTearDown(() async {
      await socketServer.close();
      await subscription.cancel();
    });
    final terminal = _Terminal();
    final service = PreviewService(
        terminal: terminal,
        isPortBusy: (_) async => false,
        readinessTimeout: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 5));
    await expectLater(
        start(service, port: socketServer.port), throwsStateError);
    expect(terminal.cancels, 1);
    expect(service.active, isNull);
  });

  test(
      'real terminal job binds the fallback port, serves HTTP, and stops in both modes',
      () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final root = await Directory.systemTemp.createTemp('preview port test-');
    final terminal = TerminalCommandService(
        workspacePath: root.path, runtime: HostProcessRuntimeAdapter());
    final service = PreviewService(
        terminal: terminal,
        lanHost: () async => '192.0.2.10',
        readinessTimeout: const Duration(seconds: 8),
        pollInterval: const Duration(milliseconds: 40));
    addTearDown(() async {
      await service.stop();
      terminal.stop();
      await root.delete(recursive: true);
    });
    await File('test/fixtures/preview_http_worker.js')
        .copy('${root.path}/server.js');
    final occupied = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = occupied.listen((request) {
      request.response.statusCode = 200;
      unawaited(request.response.close());
    });
    addTearDown(() async {
      await occupied.close(force: true);
      await subscription.cancel();
    });
    for (final lan in [false, true]) {
      final session = await service.start(
          projectId: 'p',
          workspacePath: root.path,
          command: 'node server.js --port {port} --host {host} --delay 120',
          preferredPort: occupied.port,
          allowLan: lan);
      expect(session.port, isNot(occupied.port));
      expect(
          terminal.listJobs().last.command,
          contains(
              '--port ${session.port} --host ${lan ? "0.0.0.0" : "127.0.0.1"}'));
      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://127.0.0.1:${session.port}/'));
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        expect(body, contains('"port":${session.port}'));
        expect(body, contains('"host":"${lan ? "0.0.0.0" : "127.0.0.1"}"'));
      } finally {
        client.close(force: true);
      }
      await service.stop();
      expect(terminal.listJobs().last.completed, isTrue);
      expect(service.active, isNull);
    }
  });

  test('real terminal immediate failure is rejected and leaves a completed job',
      () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final root = await Directory.systemTemp.createTemp('preview fail test-');
    final terminal = TerminalCommandService(
        workspacePath: root.path, runtime: HostProcessRuntimeAdapter());
    final service = PreviewService(
        terminal: terminal,
        readinessTimeout: const Duration(seconds: 8),
        pollInterval: const Duration(milliseconds: 40));
    addTearDown(() async {
      await service.stop();
      terminal.stop();
      await root.delete(recursive: true);
    });
    await File('test/fixtures/preview_http_worker.js')
        .copy('${root.path}/server.js');
    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    await expectLater(
        service.start(
            projectId: 'p',
            workspacePath: root.path,
            command: 'node server.js --port {port} --host {host} --fail',
            preferredPort: port),
        throwsA(isA<StateError>()
            .having((error) => error.message, 'message', contains('exit 23'))));
    expect(terminal.listJobs().single.completed, isTrue);
    expect(service.active, isNull);
  });

  test(
      'legacy Python preview and Node template launch with the selected binding',
      () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final root =
        await Directory.systemTemp.createTemp('preview template test-');
    final terminal = TerminalCommandService(
        workspacePath: root.path, runtime: HostProcessRuntimeAdapter());
    final service = PreviewService(
        terminal: terminal,
        lanHost: () async => '192.0.2.10',
        readinessTimeout: const Duration(seconds: 8),
        pollInterval: const Duration(milliseconds: 40));
    addTearDown(() async {
      await service.stop();
      terminal.stop();
      await root.delete(recursive: true);
    });
    final node = ProjectTemplateService.node;
    await File('${root.path}/index.js').writeAsString(node.files
        .singleWhere((file) => file.relativePath == 'index.js')
        .contents);
    await File('${root.path}/index.html')
        .writeAsString('owned Python HTTP preview');
    final occupied = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = occupied.listen((request) {
      unawaited(request.response.close());
    });
    addTearDown(() async {
      await occupied.close(force: true);
      await subscription.cancel();
    });
    for (final template in [ProjectTemplateService.staticWeb, node]) {
      for (final lan in [false, true]) {
        final session = await service.start(
            projectId: template.id,
            workspacePath: root.path,
            command: template.id == 'static-web'
                ? 'python -m http.server {port} --bind {host}'
                : template.settings.previewCommand!,
            preferredPort: occupied.port,
            allowLan: lan);
        expect(session.port, isNot(occupied.port));
        expect(terminal.listJobs().last.command, contains('${session.port}'));
        expect(terminal.listJobs().last.command,
            contains(lan ? '0.0.0.0' : '127.0.0.1'));
        final client = HttpClient();
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:${session.port}/'));
          final response = await request.close();
          final body = await utf8.decoder.bind(response).join();
          expect(
              body,
              template.id == 'node'
                  ? 'NEXUS Node starter'
                  : 'owned Python HTTP preview');
        } finally {
          client.close(force: true);
        }
        await service.stop();
        expect(terminal.listJobs().last.completed, isTrue);
      }
    }
  });
}
