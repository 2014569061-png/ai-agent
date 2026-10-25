import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('discovery reports connected, unauthorized and offline devices', () {
    final devices =
        DesktopDeviceService.parseDevices('List of devices attached\n'
            'phone-a device product:test model:Pixel_9 transport_id:1\n'
            'phone-b unauthorized transport_id:2\nphone-c offline\n');
    expect(devices.map((d) => d.serial), ['phone-a', 'phone-b', 'phone-c']);
    expect(devices.first.label, 'Pixel 9');
    expect(devices[1].connected, isFalse);
    expect(devices[2].statusLabel, '离线');
  });

  test('actions target only the selected serial and audit no input content',
      () async {
    final commands = <List<String>>[];
    final audits = <String>[];
    final service = DesktopDeviceService(
        adbOverride: 'adb-test',
        run: (exe, args) async {
          commands.add(args);
          return ProcessResult(
              1,
              0,
              utf8.encode(args.first == 'devices'
                  ? 'List of devices attached\na device\nb device\n'
                  : ''),
              <int>[]);
        },
        audit: (action, serial, success) async =>
            audits.add('$action:$serial:$success'));
    addTearDown(service.dispose);
    await service.discover();
    service.select('b');
    await service.back();
    await service.home();
    await service.inputText('hello world');
    expect(commands.skip(1), [
      ['-s', 'b', 'shell', 'input', 'keyevent', '4'],
      ['-s', 'b', 'shell', 'input', 'keyevent', '3'],
      ['-s', 'b', 'shell', 'input', 'text', 'hello%sworld'],
    ]);
    expect(audits, ['back:b:true', 'home:b:true', 'input_text:b:true']);
    await expectLater(service.inputText('hello; reboot'), throwsArgumentError);
    await expectLater(service.inputText('hello\nreboot'), throwsArgumentError);
    expect(commands.length, 4);
  });

  test('unauthorized devices and failed discovery cannot execute actions',
      () async {
    var failed = false;
    var count = 0;
    final service = DesktopDeviceService(
        adbOverride: 'adb-test',
        run: (exe, args) async {
          count++;
          return ProcessResult(1, failed ? 1 : 0,
              utf8.encode('phone unauthorized\n'), utf8.encode('ADB error'));
        });
    addTearDown(service.dispose);
    expect((await service.discover()).label, '请在手机上授权 USB 调试');
    await expectLater(service.back(), throwsStateError);
    failed = true;
    expect((await service.discover()).label, '检测失败');
    await expectLater(service.home(), throwsStateError);
    expect(count, 2);
  });

  test('screenshots preserve PNG bytes and reject invalid output', () async {
    var valid = true;
    final successes = <bool>[];
    final png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 255, 10];
    final service = DesktopDeviceService(
        adbOverride: 'adb-test',
        audit: (action, serial, succeeded) async => successes.add(succeeded),
        run: (exe, args) async => ProcessResult(
              1,
              0,
              args.first == 'devices'
                  ? utf8.encode('phone device\n')
                  : valid
                      ? png
                      : utf8.encode('not a PNG'),
              <int>[],
            ));
    addTearDown(service.dispose);
    await service.discover();
    expect(await service.screenshot(), png);
    valid = false;
    await expectLater(service.screenshot(), throwsStateError);
    expect(successes, [true, false]);
  });

  test('mirror lifecycle tracks and stops only its own process', () async {
    final process = _MirrorProcess();
    late List<String> mirrorArgs;
    final service = DesktopDeviceService(
      adbOverride: 'adb-test',
      scrcpyOverride: 'scrcpy-test',
      run: (exe, args) async =>
          ProcessResult(1, 0, utf8.encode('phone device\n'), <int>[]),
      start: (exe, args) async {
        mirrorArgs = args;
        return process;
      },
    );
    addTearDown(service.dispose);
    await service.discover();
    await service.startMirror();
    expect(mirrorArgs, ['--serial', 'phone']);
    expect((await service.discover()).mirroringSerial, 'phone');
    await service.stopMirror();
    expect(process.killed, isTrue);
    expect((await service.discover()).mirroringSerial, isNull);
  });

  test('tool settings survive recreation', () async {
    final service = DesktopDeviceService();
    await service.configure('D:/tools/adb.exe', 'D:/tools/scrcpy.exe');
    final restored = DesktopDeviceService();
    await restored.loadSettings();
    expect(restored.adbOverride, 'D:/tools/adb.exe');
    expect(restored.scrcpyOverride, 'D:/tools/scrcpy.exe');
    service.dispose();
    restored.dispose();
  });
}

class _MirrorProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 123;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }
}
