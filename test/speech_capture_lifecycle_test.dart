import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/speech_capture.dart';

class _Source implements SpeechCaptureSource {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final cancelled = <String>[];
  final started = <String>[];
  Future<void> Function()? onCancel;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<SpeechCapabilities> inspect() async =>
      const SpeechCapabilities(onDevice: true, permission: true);
  @override
  Future<bool> requestPermission(String sessionId) async => true;
  @override
  Future<bool> start(String sessionId,
      {required bool systemService, required String language}) async {
    started.add(sessionId);
    return true;
  }

  @override
  Future<void> stop(String sessionId) async {}
  @override
  Future<void> cancel(String sessionId) async {
    cancelled.add(sessionId);
    await onCancel?.call();
  }
}

void main() {
  late _Source source;
  late SpeechCaptureController controller;
  setUp(() {
    source = _Source();
    controller =
        SpeechCaptureController(source: source, stopSpeaking: () async {});
  });
  tearDown(() async {
    controller.dispose();
    await source.stream.close();
  });

  test('unconfirmed cancellation is visible and late transcript is rejected',
      () async {
    await controller.start();
    source.onCancel = () async => throw StateError('private native failure');
    await controller.cancel();
    source.stream.add({
      'type': 'result',
      'sessionId': source.started.single,
      'text': 'obsolete',
    });
    expect(controller.phase, SpeechCapturePhase.error);
    expect(controller.errorCode, 'service_error');
    expect(controller.transcript, isEmpty);
    expect(source.cancelled, hasLength(1));
  });

  test('a late cancellation error cannot overwrite a newer recording',
      () async {
    await controller.start();
    final completion = Completer<void>();
    source.onCancel = () => completion.future;
    final pending = controller.cancel();
    await controller.start();
    completion.completeError(StateError('old cancellation'));
    await pending;
    expect(controller.phase, SpeechCapturePhase.recording);
    expect(controller.errorCode, isNull);
    source.stream.add({
      'type': 'result',
      'sessionId': source.started.last,
      'text': 'current',
    });
    expect(controller.phase, SpeechCapturePhase.ready);
    expect(controller.transcript, 'current');
  });

  test('a cancellation error after disposal does not notify listeners',
      () async {
    await controller.start();
    final completion = Completer<void>();
    source.onCancel = () => completion.future;
    final pending = controller.cancel();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.dispose();
    completion.completeError(StateError('cancelled after disposal'));
    await pending;
    expect(notifications, 0);
  });
}
