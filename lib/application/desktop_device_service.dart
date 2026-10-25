import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_service.dart';
import 'providers.dart';

class DesktopDevice {
  const DesktopDevice(this.serial, this.status, this.model);
  final String serial;
  final String status;
  final String model;
  bool get connected => status == 'device';
  String get label => model.isEmpty ? serial : model.replaceAll('_', ' ');
  String get statusLabel => switch (status) {
        'device' => '已连接',
        'unauthorized' => '请在手机上授权 USB 调试',
        'offline' => '离线',
        _ => status,
      };
}

class DesktopDeviceSnapshot {
  const DesktopDeviceSnapshot({
    this.devices = const [],
    this.adbPath,
    this.scrcpyPath,
    this.selectedSerial,
    this.mirroringSerial,
    this.problem,
  });
  final List<DesktopDevice> devices;
  final String? adbPath;
  final String? scrcpyPath;
  final String? selectedSerial;
  final String? mirroringSerial;
  final String? problem;
  DesktopDevice? get selected {
    for (final device in devices) {
      if (device.serial == selectedSerial) return device;
    }
    return null;
  }

  String get label => problem != null
      ? '检测失败'
      : selected?.statusLabel ?? (adbPath == null ? '未配置 ADB' : '未连接');
}

typedef DeviceCommandRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);
typedef DeviceAuditWriter = Future<void> Function(
    String action, String serial, bool succeeded);
typedef DeviceProcessStarter = Future<Process> Function(
    String executable, List<String> arguments);

/// Explicit serial selection and argv execution prevent accidentally acting on
/// another phone or passing text through a host shell.
class DesktopDeviceService {
  DesktopDeviceService({
    DeviceCommandRunner? run,
    DeviceProcessStarter? start,
    this.audit,
    this.adbOverride,
    this.scrcpyOverride,
  })  : _run = run ?? runCommand,
        _start = start ?? startManagedProcess;

  final DeviceCommandRunner _run;
  final DeviceProcessStarter _start;
  final DeviceAuditWriter? audit;
  String? adbOverride;
  String? scrcpyOverride;
  String? _selectedSerial;
  DesktopDeviceSnapshot _snapshot = const DesktopDeviceSnapshot();
  Process? _mirror;
  String? _mirroringSerial;
  bool _disposed = false;

  static List<DesktopDevice> parseDevices(String output) {
    return [
      for (final line in const LineSplitter().convert(output))
        if (line.trim().isNotEmpty &&
            !line.startsWith('List of devices') &&
            !line.startsWith('*'))
          if (line.trim().split(RegExp(r'\s+')) case final parts
              when parts.length >= 2)
            DesktopDevice(
              parts[0],
              parts[1],
              parts
                      .where((part) => part.startsWith('model:'))
                      .map((part) => part.substring(6))
                      .firstOrNull ??
                  '',
            ),
    ];
  }

  static Future<ProcessResult> runCommand(
      String executable, List<String> arguments) async {
    final process = await Process.start(executable, arguments);
    Future<List<int>> read(Stream<List<int>> stream) async {
      final bytes = <int>[];
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > 32 * 1024 * 1024) {
          process.kill();
          throw const FileSystemException('设备输出超过 32 MB');
        }
        bytes.addAll(chunk);
      }
      return bytes;
    }

    final results = await Future.wait<Object>([
      process.exitCode,
      read(process.stdout),
      read(process.stderr),
    ]).timeout(const Duration(seconds: 15), onTimeout: () {
      process.kill();
      throw TimeoutException('设备命令超时');
    });
    return ProcessResult(process.pid, results[0] as int,
        results[1] as List<int>, results[2] as List<int>);
  }

  static Future<Process> startManagedProcess(
      String exe, List<String> args) async {
    final process = await Process.start(exe, args);
    if (Platform.isWindows) {
      try {
        await const MethodChannel('nexus/desktop_process').invokeMethod<void>(
          'trackProcess',
          {'pid': process.pid},
        );
      } catch (error) {
        process.kill();
        rethrow;
      }
    }
    return process;
  }

  static String _text(Object output) => output is List<int>
      ? utf8.decode(output, allowMalformed: true)
      : output.toString();

  static String? findExecutable(String name, String? override) {
    if (override != null && override.trim().isNotEmpty) return override.trim();
    final env = Platform.environment;
    final suffix = Platform.isWindows ? '.exe' : '';
    final executable = '$name$suffix';
    final appDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      if (env['NEXUS_${name.toUpperCase()}_PATH'] case final path?) path,
      p.join(appDir, 'tools', executable),
      if (name == 'adb') ...[
        for (final key in ['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
          if (env[key] case final sdk?)
            p.join(sdk, 'platform-tools', executable),
        if (Platform.isWindows && env['LOCALAPPDATA'] != null)
          p.join(env['LOCALAPPDATA']!, 'Android', 'Sdk', 'platform-tools',
              executable),
      ],
      for (final dir
          in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'))
        if (dir.isNotEmpty) p.join(dir.replaceAll('"', ''), executable),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    adbOverride ??= prefs.getString('desktop.adb_path');
    scrcpyOverride ??= prefs.getString('desktop.scrcpy_path');
  }

  Future<void> configure(String adb, String scrcpy) async {
    final prefs = await SharedPreferences.getInstance();
    adbOverride = adb.trim();
    scrcpyOverride = scrcpy.trim();
    await prefs.setString('desktop.adb_path', adbOverride!);
    await prefs.setString('desktop.scrcpy_path', scrcpyOverride!);
  }

  Future<DesktopDeviceSnapshot> discover() async {
    final adb = findExecutable('adb', adbOverride);
    final scrcpy = findExecutable('scrcpy', scrcpyOverride);
    var devices = <DesktopDevice>[];
    String? problem;
    if (adb != null) {
      try {
        final result = await _run(adb, ['devices', '-l']);
        if (result.exitCode != 0) {
          throw StateError(_text(result.stderr));
        }
        devices = parseDevices(_text(result.stdout));
      } catch (error) {
        problem = error.toString();
      }
    }
    if (!devices.any((d) => d.serial == _selectedSerial)) {
      _selectedSerial = devices.where((d) => d.connected).firstOrNull?.serial ??
          devices.firstOrNull?.serial;
    }
    return _snapshot = DesktopDeviceSnapshot(
      devices: devices,
      adbPath: adb,
      scrcpyPath: scrcpy,
      selectedSerial: _selectedSerial,
      mirroringSerial: _mirroringSerial,
      problem: problem,
    );
  }

  void select(String serial) {
    if (!_snapshot.devices.any((device) => device.serial == serial)) {
      throw StateError('设备已断开，请刷新');
    }
    _selectedSerial = serial;
  }

  String _requireDevice() {
    if (_disposed) throw StateError('设备服务已关闭');
    final device =
        _snapshot.devices.where((d) => d.serial == _selectedSerial).firstOrNull;
    if (device == null || !device.connected || _snapshot.problem != null) {
      throw StateError('请先连接并授权设备');
    }
    return device.serial;
  }

  Future<ProcessResult> _action(String action, List<String> args,
      {void Function(ProcessResult)? validate}) async {
    final serial = _requireDevice();
    var succeeded = false;
    try {
      final result = await _run(_snapshot.adbPath!, ['-s', serial, ...args]);
      if (result.exitCode != 0) throw StateError(_text(result.stderr));
      validate?.call(result);
      succeeded = true;
      return result;
    } finally {
      // Input text and screenshot bytes never enter the persisted audit trail.
      await audit?.call(action, serial, succeeded);
    }
  }

  Future<void> back() async =>
      _action('back', ['shell', 'input', 'keyevent', '4']);
  Future<void> home() async =>
      _action('home', ['shell', 'input', 'keyevent', '3']);

  Future<void> inputText(String text) async {
    // adb shell re-parses arguments remotely. Permit a small literal alphabet
    // rather than treating quoting as a substitute for a device-side boundary.
    if (text.isEmpty ||
        text.length > 1000 ||
        !RegExp(r'^[a-zA-Z0-9 .,@_+:/-]+$').hasMatch(text)) {
      throw ArgumentError('支持最多 1000 个英文、数字及常用标点；中文请在投屏窗口粘贴');
    }
    await _action(
        'input_text', ['shell', 'input', 'text', text.replaceAll(' ', '%s')]);
  }

  Future<List<int>> screenshot() async {
    final result = await _action('screenshot', ['exec-out', 'screencap', '-p'],
        validate: (result) {
      final bytes = result.stdout as List<int>;
      const png = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 8 ||
          !List.generate(8, (i) => bytes[i] == png[i])
              .every((match) => match)) {
        throw StateError('设备没有返回有效 PNG 截图');
      }
    });
    return result.stdout as List<int>;
  }

  Future<void> startMirror() async {
    final serial = _requireDevice();
    if (_mirror != null) {
      if (_mirroringSerial == serial) return;
      throw StateError('请先停止当前投屏');
    }
    final scrcpy = _snapshot.scrcpyPath;
    if (scrcpy == null) throw StateError('请先在设备设置中选择 scrcpy.exe');
    var succeeded = false;
    try {
      final process = await _start(scrcpy, ['--serial', serial]);
      if (_disposed) {
        process.kill();
        throw StateError('设备服务已关闭');
      }
      _mirror = process;
      _mirroringSerial = serial;
      // Drain pipes so a long-running mirror cannot block on console output.
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.exitCode.then((_) {
        if (identical(_mirror, process)) {
          _mirror = null;
          _mirroringSerial = null;
        }
      }));
      final earlyExit = await process.exitCode.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => -999,
      );
      if (earlyExit != -999) {
        throw StateError('投屏程序已退出（$earlyExit），请检查设备连接和 scrcpy 配置');
      }
      succeeded = true;
    } finally {
      await audit?.call('mirror_start', serial, succeeded);
    }
  }

  Future<void> stopMirror() async {
    final process = _mirror;
    if (process == null) return;
    final serial = _mirroringSerial!;
    final stopped = process.kill();
    await audit?.call('mirror_stop', serial, stopped);
    if (!stopped) throw StateError('无法停止投屏，请关闭投屏窗口');
    await process.exitCode.timeout(const Duration(seconds: 5));
    _mirror = null;
    _mirroringSerial = null;
  }

  void dispose() {
    _disposed = true;
    _mirror?.kill();
  }
}

final desktopDeviceServiceProvider =
    Provider.autoDispose<DesktopDeviceService>((ref) {
  final database = ref.read(databaseProvider.future);
  final service =
      DesktopDeviceService(audit: (action, serial, succeeded) async {
    final db = await database;
    await AuditService().log(
      db,
      type: 'desktop_device',
      detail: jsonEncode({
        'operation': action,
        'tool': action.startsWith('mirror_') ? 'scrcpy' : 'adb',
        'effect':
            'device_${sha256.convert(utf8.encode(serial)).toString().substring(0, 16)}',
        'code': succeeded ? 'success' : 'failed',
      }),
      decision: succeeded ? 'completed' : 'failed',
      force: true,
    );
  });
  ref.onDispose(service.dispose);
  return service;
});

final desktopDevicesProvider = AsyncNotifierProvider.autoDispose<
    DesktopDevicesController,
    DesktopDeviceSnapshot>(DesktopDevicesController.new);

class DesktopDevicesController extends AsyncNotifier<DesktopDeviceSnapshot> {
  bool _refreshing = false;

  @override
  Future<DesktopDeviceSnapshot> build() async {
    final service = ref.watch(desktopDeviceServiceProvider);
    final timer =
        Timer.periodic(const Duration(seconds: 5), (_) => unawaited(refresh()));
    ref.onDispose(timer.cancel);
    _refreshing = true;
    try {
      await service.loadSettings();
      return await service.discover();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> refresh() async {
    if (_refreshing || !ref.mounted) return;
    _refreshing = true;
    try {
      final next = await AsyncValue.guard(
          ref.read(desktopDeviceServiceProvider).discover);
      if (ref.mounted) state = next;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> select(String serial) async {
    ref.read(desktopDeviceServiceProvider).select(serial);
    await refresh();
  }
}
