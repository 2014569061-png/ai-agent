import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/terminal/android_shell_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/terminal/builtin_proot_runtime_adapter.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/infrastructure/terminal/termux_runtime_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidShellRuntimeAdapter', () {
    test('reports unavailable and refuses to run off Android', () async {
      final adapter = AndroidShellRuntimeAdapter(isAndroid: false);

      final info = await adapter.inspect();
      final result = await adapter.run(
        _request('echo hello'),
        workingDirectory: '.',
        timeout: const Duration(seconds: 1),
      );

      expect(info.available, isFalse);
      expect(info.kind, LinuxRuntimeKind.androidShell);
      expect(result.exitCode, 127);
      expect(result.output, contains('仅支持 Android'));
    });

    test('runs a shell command and collects stdout through the public seam',
        () async {
      final process = _FakeProcess(
        pid: 11,
        stdoutText: 'hello\n',
        exitCode: 0,
      );
      final calls = <_ProcessStartCall>[];
      final adapter = AndroidShellRuntimeAdapter(
        isAndroid: true,
        processStarter: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          calls.add(_ProcessStartCall(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment,
            runInShell: runInShell,
            mode: mode,
          ));
          return process;
        },
      );

      final result = await adapter.run(
        _request('echo hello', shell: 'unknown'),
        workingDirectory: '/workspace',
        timeout: const Duration(seconds: 1),
      );

      expect(result.output, 'hello\n');
      expect(result.exitCode, 0);
      expect(result.succeeded, isTrue);
      expect(adapter.isRunning, isFalse);
      expect(calls, hasLength(1));
      expect(calls.single.executable, '/system/bin/sh');
      expect(calls.single.arguments, ['-c', 'echo hello']);
      expect(calls.single.workingDirectory, '/workspace');
      expect(calls.single.runInShell, isFalse);
    });

    test('terminates a command that exceeds its timeout', () async {
      final process = _FakeProcess(pid: 12);
      final adapter = AndroidShellRuntimeAdapter(
        isAndroid: true,
        processStarter: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async =>
            process,
      );

      final result = await adapter.run(
        _request('sleep 10'),
        workingDirectory: '.',
        timeout: const Duration(milliseconds: 20),
      );

      expect(result.exitCode, 124);
      expect(result.timedOut, isTrue);
      expect(result.output, contains('命令超时'));
      expect(process.wasKilled, isTrue);
    });

    test('detached execution does not inherit the parent environment',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('nexus-android-shell-');
      addTearDown(() => directory.delete(recursive: true));
      final process = _FakeProcess(
        pid: 13,
        stdoutText: 'stdout\n',
        stderrText: 'stderr\n',
        exitCode: 0,
      );
      final calls = <_ProcessStartCall>[];
      final adapter = AndroidShellRuntimeAdapter(
        isAndroid: true,
        processStarter: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          calls.add(_ProcessStartCall(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment,
            runInShell: runInShell,
            mode: mode,
          ));
          return process;
        },
      );

      final handle = await adapter.startDetached(
        _request('echo detached'),
        workingDirectory: directory.path,
        timeout: const Duration(seconds: 1),
        ownerToken: 'owner-1',
        logPath: '${directory.path}${Platform.pathSeparator}detached.log',
      );

      expect(handle, isNotNull);
      expect(handle!.pid, 13);
      final result = await handle.completion;

      expect(result.exitCode, 0);
      expect(result.output, 'stdout\nstderr: stderr\n');
      expect(calls.single.environment, {'NEXUS_DAEMON_OWNER': 'owner-1'});
      expect(calls.single.includeParentEnvironment, isFalse);
    });
  });

  group('BuiltinProotRuntimeAdapter', () {
    test('refuses to run off Android without touching the native bridge',
        () async {
      const channel = MethodChannel('test/builtin-proot-off-android');
      var bridgeCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        bridgeCalls++;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final adapter = BuiltinProotRuntimeAdapter(
        bridge: channel,
        isAndroid: false,
      );

      final info = await adapter.inspect();
      final result = await adapter.run(
        _request('echo hello'),
        workingDirectory: '.',
        timeout: const Duration(seconds: 1),
      );

      expect(info.available, isFalse);
      expect(result.exitCode, 127);
      expect(result.output, contains('仅支持 Android'));
      expect(bridgeCalls, 0);
    });

    test('aborts before native execution when the rootfs checksum is wrong',
        () async {
      const channel = MethodChannel('test/builtin-proot-invalid-rootfs');
      final support =
          await Directory.systemTemp.createTemp('nexus-proot-invalid-');
      addTearDown(() => support.delete(recursive: true));
      var bridgeCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        bridgeCalls++;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final adapter = BuiltinProotRuntimeAdapter(
        bridge: channel,
        isAndroid: true,
        rootfsAssetPath: 'test/invalid-rootfs.tar.gz',
        applicationSupportDirectory: () async => support,
        assetBundle: _InvalidRootfsAssetBundle(),
      );

      final result = await adapter.run(
        _request('echo should-not-run'),
        workingDirectory: support.path,
        timeout: const Duration(seconds: 1),
      );

      expect(result.exitCode, 127);
      expect(result.output, contains('Alpine rootfs 校验失败'));
      expect(bridgeCalls, 0);
    });

    test('prepares the verified rootfs before delegating a command', () async {
      const channel = MethodChannel('test/builtin-proot-run');
      final support = await Directory.systemTemp.createTemp('nexus-proot-');
      addTearDown(() => support.delete(recursive: true));
      Map<dynamic, dynamic>? runArguments;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'run') {
          runArguments = call.arguments as Map<dynamic, dynamic>;
          return <String, Object>{'output': 'proot-ok', 'exitCode': 0};
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final adapter = BuiltinProotRuntimeAdapter(
        bridge: channel,
        isAndroid: true,
        applicationSupportDirectory: () async => support,
      );

      final result = await adapter.run(
        _request('echo proot'),
        workingDirectory: support.path,
        timeout: const Duration(seconds: 10),
      );

      expect(result.output, 'proot-ok');
      expect(result.exitCode, 0);
      expect(runArguments, isNotNull);
      expect(runArguments!['command'], 'echo proot');
      expect(runArguments!['workingDirectory'], support.path);
      expect(runArguments!['rootfsPath'], contains('alpine-rootfs'));
      expect(adapter.isRunning, isFalse);
    });
  });

  group('TermuxRuntimeAdapter', () {
    test('reports unavailable off Android and rejects detached execution',
        () async {
      final adapter = TermuxRuntimeAdapter(isAndroid: false);

      final info = await adapter.inspect();
      final handle = await adapter.startDetached(
        _request('echo hello'),
        workingDirectory: '.',
        timeout: const Duration(seconds: 1),
        ownerToken: 'owner',
        logPath: 'unused.log',
      );

      expect(info.available, isFalse);
      expect(info.requiresExternalApp, isTrue);
      expect(handle, isNull);
    });

    test('returns false for invalid detached ownership requests', () async {
      final adapter = TermuxRuntimeAdapter(isAndroid: true);

      expect(await adapter.verifyDetached(0, 'owner'), isFalse);
      expect(await adapter.verifyDetached(1, ''), isFalse);
      expect(await adapter.stopDetached(0, 'owner'), isFalse);
      expect(await adapter.stopDetached(1, ''), isFalse);
    });

    test('runs a command through the file exchange protocol', () async {
      final bridgeDirectory =
          await Directory.systemTemp.createTemp('nexus-termux-');
      addTearDown(() => bridgeDirectory.delete(recursive: true));
      const channel = MethodChannel('test/termux-run-success');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'runInTermux') return null;
        final command = call.arguments as Map<dynamic, dynamic>;
        final script = command['command'] as String;
        final files =
            RegExp(r"> '([^']+)' 2>&1\n.*> '([^']+)'").firstMatch(script);
        expect(files, isNotNull);
        await File(files!.group(1)!).writeAsString('termux-ok');
        await File(files.group(2)!).writeAsString('0');
        return <String, Object>{'started': true};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final adapter = TermuxRuntimeAdapter(
        bridge: channel,
        isAndroid: true,
        bridgeDirectory: bridgeDirectory.path,
        bridgeCallTimeout: const Duration(seconds: 1),
      );

      final result = await adapter.run(
        _request('echo termux'),
        workingDirectory: bridgeDirectory.path,
        timeout: const Duration(seconds: 2),
      );

      expect(result.output, 'termux-ok');
      expect(result.exitCode, 0);
      expect(result.timedOut, isFalse);
    });

    test('detached execution returns the owner-scoped completion result',
        () async {
      final bridgeDirectory =
          await Directory.systemTemp.createTemp('nexus-termux-detached-');
      addTearDown(() => bridgeDirectory.delete(recursive: true));
      const channel = MethodChannel('test/termux-detached-success');
      const ownerToken = 'owner-1';
      final bridgePath = bridgeDirectory.path.replaceAll('\\', '/');
      final base = '$bridgePath/nexus-daemon-$ownerToken';
      final pidPath = '$base.pid';
      final ownerPath = '$base.owner';
      final logPath = '$base.log';
      final exitPath = '$base.exit.json';
      String? launchCommand;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'runInTermux') return null;
        final arguments = call.arguments as Map<dynamic, dynamic>;
        launchCommand = arguments['command'] as String;
        await File(pidPath).writeAsString('321');
        await File(ownerPath).writeAsString(ownerToken);
        await File(logPath).writeAsString('detached-ok');
        await File(exitPath).writeAsString('{"exitCode":0,"timedOut":false}');
        return <String, Object>{'started': true};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final adapter = TermuxRuntimeAdapter(
        bridge: channel,
        isAndroid: true,
        bridgeDirectory: bridgePath,
        bridgeCallTimeout: const Duration(seconds: 1),
      );

      final handle = await adapter.startDetached(
        _request('echo detached'),
        workingDirectory: bridgeDirectory.path,
        timeout: const Duration(seconds: 1),
        ownerToken: ownerToken,
        logPath: '${bridgeDirectory.path}${Platform.pathSeparator}ignored.log',
      );

      expect(handle, isNotNull);
      expect(handle!.pid, 321);
      expect(handle.logPath, logPath);
      expect(launchCommand, contains('NEXUS_DAEMON_OWNER'));

      final result = await handle.completion;
      expect(result.output, 'detached-ok');
      expect(result.exitCode, 0);
      expect(result.timedOut, isFalse);
    });
  });
}

LinuxCommandRequest _request(String command, {String shell = 'bash'}) {
  final parts = command.split(' ');
  return LinuxCommandRequest(
    commandLine: command,
    executable: parts.first,
    normalizedCommand: parts.first,
    arguments: parts.skip(1).toList(),
    shell: shell,
  );
}

class _ProcessStartCall {
  _ProcessStartCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.includeParentEnvironment,
    required this.runInShell,
    required this.mode,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;
  final ProcessStartMode mode;
}

class _FakeProcess implements Process {
  _FakeProcess({
    required this.pid,
    String stdoutText = '',
    String stderrText = '',
    int? exitCode,
  }) {
    _exitCode =
        exitCode == null ? _exitCodeCompleter.future : Future.value(exitCode);
    _stdoutController.add(utf8.encode(stdoutText));
    _stderrController.add(utf8.encode(stderrText));
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
  }

  @override
  final int pid;

  final _exitCodeCompleter = Completer<int>();
  late final Future<int> _exitCode;
  final _stdoutController = StreamController<List<int>>();
  final _stderrController = StreamController<List<int>>();
  final _stdin = IOSink(StreamController<List<int>>());
  bool wasKilled = false;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCodeCompleter.isCompleted) _exitCodeCompleter.complete(143);
    return true;
  }
}

class _InvalidRootfsAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'test/invalid-rootfs.tar.gz') {
      return ByteData.sublistView(Uint8List.fromList([1, 2, 3, 4]));
    }
    return rootBundle.load(key);
  }
}
