import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/browser_session_service.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/browser_session.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/browser/browser_page.dart';

class _Transport implements BrowserTransport {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final calls = <String>[];
  Map<String, dynamic> state = {
    'sessionId': 'fixture',
    'mode': 'user',
    'epoch': 1,
    'attached': true
  };
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<Map<String, dynamic>> invoke(
      String method, Map<String, dynamic> args) async {
    calls.add(method);
    if (method == 'control') {
      state = {
        ...state,
        'mode': args['mode'],
        'epoch': (state['epoch'] as int) + 1
      };
      stream.add(state);
    }
    return Map.from(state);
  }
}

class _Chat extends ChatController {
  int stops = 0;
  @override
  ChatState build() => const ChatState(conversationId: 'owner');
  @override
  void stop() {
    stops++;
  }
}

void main() {
  late AppDatabase db;
  late _Transport transport;
  late BrowserSessionService service;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    transport = _Transport();
    service = BrowserSessionService(transport);
  });
  tearDown(() async {
    service.dispose();
    await transport.stream.close();
    await db.close();
  });

  Future<void> show(WidgetTester tester, Size size, double scale) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          chatControllerProvider.overrideWith(_Chat.new),
          browserSessionProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: BrowserPage(
                conversationId: 'owner',
                viewBuilder: (_) => const ColoredBox(
                    color: Colors.white,
                    child: Text('Native view fixture'))))));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('browser remains usable at $size with large text',
        (tester) async {
      await show(tester, size, 2);
      expect(find.text('Native view fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('允许助手操作'));
      await tester.tap(find.text('允许助手操作'));
      await tester.pumpAndSettle();
      expect(service.agentControlled, true);
      await tester.tap(find.byTooltip('立即接管'));
      await tester.pumpAndSettle();
      expect(service.agentControlled, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(transport.calls, contains('close'));
    });
  }

  testWidgets('failed duplicate page cannot close another owner session',
      (tester) async {
    await service.open('other-owner');
    await show(tester, const Size(360, 800), 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(service.owner, 'other-owner');
    expect(transport.calls.where((method) => method == 'close'), isEmpty);
  });

  testWidgets('address follows navigation and editing takes back control',
      (tester) async {
    transport.state['url'] = 'https://first.invalid';
    await show(tester, const Size(360, 800), 1);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'https://first.invalid');
    transport.state = {...transport.state, 'url': 'https://second.invalid'};
    transport.stream.add(transport.state);
    await tester.pumpAndSettle();
    expect(field.controller!.text, 'https://second.invalid');
    await tester.tap(find.text('允许助手操作'));
    await tester.pumpAndSettle();
    expect(service.agentControlled, true);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(service.agentControlled, false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('background revokes control and resume does not restore it',
      (tester) async {
    await show(tester, const Size(360, 800), 1);
    await tester.tap(find.text('允许助手操作'));
    await tester.pumpAndSettle();
    expect(service.agentControlled, true);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(service.agentControlled, false);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.agentControlled, false);
    expect(transport.calls.where((method) => method == 'control').length, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
