import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/desktop_host_service.dart';
import 'package:mobile_agent/application/desktop_pty_session.dart';
import 'package:mobile_agent/application/desktop_pty_terminal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CPR uses one-based coordinates, including a split device query', () {
    final terminal = DesktopPtyTerminal();
    final responses = <String>[];
    terminal.onOutput = responses.add;
    terminal.write('\x1b[6n');
    terminal.write('\x1b[4;8H');
    terminal.write('\x1b[');
    terminal.write('6n');
    expect(responses, ['\x1b[1;1R', '\x1b[4;8R']);
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => DesktopHostService.instance.terminalWorkspaces.clear());
  tearDown(() {
    messenger.setMockMethodCallHandler(DesktopHostService.channel, null);
    DesktopHostService.instance.terminalWorkspaces.clear();
  });

  test('close during opening waits for and releases the late native session',
      () async {
    final opened = Completer<int>();
    final closed = <int>[];
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return opened.future;
      if (call.method == 'closeTerminal') {
        closed.add(call.arguments['id'] as int);
      }
      return null;
    });
    final session = DesktopPtySession('workspace');
    final opening = session.open();
    final closing = session.close();
    opened.complete(7);
    await Future.wait([opening, closing]);
    expect(session.connected, false);
    expect(closed, [7]);
    expect(DesktopHostService.instance.hasTerminal('workspace'), false);
    session.dispose();
  });

  test('dispose during opening cannot resurrect the native session', () async {
    final opened = Completer<int>();
    final closed = <int>[];
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return opened.future;
      if (call.method == 'closeTerminal') {
        closed.add(call.arguments['id'] as int);
      }
      return null;
    });
    final session = DesktopPtySession('workspace');
    final opening = session.open();
    session.dispose();
    opened.complete(9);
    await opening;
    await session.close();
    expect(closed, [9]);
    expect(session.connected, false);
    expect(DesktopHostService.instance.terminalWorkspaces, isEmpty);
  });

  test('concurrent closes share acknowledgement and retain the recovery guard',
      () async {
    final acknowledged = Completer<void>();
    var closeCalls = 0;
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return 11;
      if (call.method == 'closeTerminal') {
        closeCalls++;
        await acknowledged.future;
      }
      return null;
    });
    final session = DesktopPtySession('workspace');
    await session.open();
    final first = session.close();
    final second = session.close();
    await Future<void>.delayed(Duration.zero);
    expect(DesktopHostService.instance.hasTerminal('workspace'), true);
    expect(closeCalls, 1);
    acknowledged.complete();
    await Future.wait([first, second]);
    expect(DesktopHostService.instance.hasTerminal('workspace'), false);
    session.dispose();
  });

  test('failed close retains the session and supports explicit retry',
      () async {
    var fail = true;
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return 13;
      if (call.method == 'closeTerminal' && fail) {
        throw PlatformException(code: 'close_failed');
      }
      return null;
    });
    final session = DesktopPtySession('workspace');
    await session.open();
    await expectLater(session.close(), throwsA(isA<PlatformException>()));
    expect(session.connected, true);
    expect(DesktopHostService.instance.hasTerminal('workspace'), true);
    fail = false;
    await session.close();
    expect(session.connected, false);
    session.dispose();
  });

  test('UTF-8 is decoded across poll chunks and decoder resets on reopen',
      () async {
    final chunks = <List<int>>[];
    var nextId = 20;
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return nextId++;
      if (call.method == 'readTerminal') {
        return {
          'bytes': chunks.isEmpty ? <int>[] : chunks.removeAt(0),
          'exitCode': 259
        };
      }
      return null;
    });
    final session = DesktopPtySession('workspace');
    await session.open();
    final encoded = utf8.encode('中文');
    chunks.addAll(
        [encoded.sublist(0, 2), encoded.sublist(2, 4), encoded.sublist(4)]);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(session.terminal.buffer.getText(), contains('中文'));
    expect(session.terminal.buffer.getText(), isNot(contains('\uFFFD')));
    await session.close();
    await session.open();
    chunks.add(utf8.encode('重启'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(session.terminal.buffer.getText(), contains('重启'));
    await session.close();
    session.dispose();
  });

  test('workspace shells are independent and closeAll releases all bindings',
      () async {
    final calls = <int>[];
    var nextId = 30;
    messenger.setMockMethodCallHandler(DesktopHostService.channel,
        (call) async {
      if (call.method == 'openTerminal') return nextId++;
      if (call.method == 'closeTerminal') {
        calls.add(call.arguments['id'] as int);
      }
      return null;
    });
    final sessions = DesktopPtySessions();
    final a = sessions.forWorkspace('a');
    final b = sessions.forWorkspace('b');
    expect(identical(a, sessions.forWorkspace('a')), true);
    expect(identical(a, b), false);
    await a.open();
    await b.open();
    await sessions.closeAll();
    expect(calls, [30, 31]);
    expect(DesktopHostService.instance.terminalWorkspaces, isEmpty);
  });
}
