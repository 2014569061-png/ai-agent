import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/browser/android_browser_transport.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test('services share events and one listener cannot disconnect another',
      () async {
    var listens = 0, cancels = 0;
    const channel = MethodChannel('nexus/browser/events');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'listen') listens++;
      if (call.method == 'cancel') cancels++;
      return null;
    });
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final first = <Map<String, dynamic>>[], second = <Map<String, dynamic>>[];
    final a = AndroidBrowserTransport().events.listen(first.add);
    final b = AndroidBrowserTransport().events.listen(second.add);
    await pumpEventQueue();
    Future<void> emit(int epoch) async {
      final delivered = Completer<void>();
      await binding.defaultBinaryMessenger.handlePlatformMessage(
          'nexus/browser/events',
          const StandardMethodCodec()
              .encodeSuccessEnvelope({'sessionId': 's', 'epoch': epoch}),
          (_) => delivered.complete());
      await delivered.future;
      await pumpEventQueue();
    }

    await emit(1);
    expect(listens, 1);
    expect(first.single['epoch'], 1);
    expect(second.single['epoch'], 1);
    await a.cancel();
    await emit(2);
    expect(cancels, 0);
    expect(first, hasLength(1));
    expect(second.last['epoch'], 2);
    await b.cancel();
    expect(cancels, 1);
  });
}
