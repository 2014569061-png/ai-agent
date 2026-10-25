import 'dart:async';
import 'package:flutter/services.dart';
import '../application/speech_capture.dart';

class _SpeechFixtureSource implements SpeechCaptureSource {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  SpeechCapabilities capabilities =
      const SpeechCapabilities(onDevice: true, system: true, permission: true);
  Future<SpeechCapabilities>? inspection;
  Future<bool>? permission;
  Future<bool> Function(String)? onStart;
  final starts = <String>[],
      cancels = <String>[],
      permissions = <String>[],
      stops = <String>[];
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<SpeechCapabilities> inspect() async =>
      await (inspection ?? Future.value(capabilities));
  @override
  Future<bool> requestPermission(String id) async {
    permissions.add(id);
    return await (permission ?? Future.value(true));
  }

  @override
  Future<bool> start(String id,
      {required bool systemService, required String language}) async {
    starts.add(id);
    return await (onStart?.call(id) ?? Future.value(true));
  }

  @override
  Future<void> stop(String id) async {
    stops.add(id);
  }

  @override
  Future<void> cancel(String id) async {
    cancels.add(id);
  }

  void emit(String type, String id, {String? text, String? code}) =>
      stream.add({'type': type, 'sessionId': id, 'text': text, 'code': code});
}

Future<List<Map<String, dynamic>>> runSpeechCaptureChecks() async {
  final cases = <Map<String, dynamic>>[];
  Map<String, dynamic>? nativeSnapshot;
  Future<void> check(String name, Future<bool> Function() run) async {
    try {
      cases.add({'name': name, 'passed': await run()});
    } catch (error) {
      cases.add({
        'name': name,
        'passed': false,
        'error': error.runtimeType.toString()
      });
    }
  }

  Future<void> fixture(
          String name,
          Future<bool> Function(_SpeechFixtureSource, SpeechCaptureController)
              run,
          {Future<void> Function()? stopSpeaking}) =>
      check(name, () async {
        final source = _SpeechFixtureSource();
        final controller = SpeechCaptureController(
            source: source, stopSpeaking: stopSpeaking ?? () async {});
        try {
          return await run(source, controller);
        } finally {
          controller.dispose();
          await source.stream.close();
        }
      });
  await fixture('speech_no_engine_requests_no_permission_or_recording',
      (s, c) async {
    s.capabilities = const SpeechCapabilities();
    await c.start();
    return c.phase == SpeechCapturePhase.error &&
        s.starts.isEmpty &&
        s.permissions.isEmpty;
  });
  await fixture('speech_permission_denial_never_starts_recognizer',
      (s, c) async {
    s.capabilities = const SpeechCapabilities(onDevice: true);
    s.permission = Future.value(false);
    await c.start();
    return c.errorCode == 'permission_denied' &&
        s.starts.isEmpty &&
        s.permissions.length == 1;
  });
  await fixture('speech_cancelled_generation_cannot_restore_old_transcript',
      (s, c) async {
    await c.start();
    final old = s.starts.single;
    await c.cancel();
    s.emit('result', old, text: 'obsolete');
    await c.start();
    final current = s.starts.last;
    s.emit('partial', old, text: 'old partial');
    s.emit('result', current, text: 'current');
    return c.phase == SpeechCapturePhase.ready &&
        c.transcript == 'current' &&
        s.cancels.contains(old) &&
        old != current;
  });
  await fixture('speech_cancel_while_permission_pending_never_auto_starts',
      (s, c) async {
    s.capabilities = const SpeechCapabilities(onDevice: true);
    final grant = Completer<bool>();
    s.permission = grant.future;
    final pending = c.start();
    await Future<void>.delayed(Duration.zero);
    await c.cancel();
    grant.complete(true);
    await pending;
    return s.permissions.length == 1 &&
        s.starts.isEmpty &&
        c.phase == SpeechCapturePhase.idle;
  });
  await fixture('speech_release_before_preflight_finishes_never_records',
      (s, c) async {
    final inspect = Completer<SpeechCapabilities>();
    s.inspection = inspect.future;
    final pending = c.start();
    await c.stop();
    inspect
        .complete(const SpeechCapabilities(onDevice: true, permission: true));
    await pending;
    return s.starts.isEmpty &&
        s.permissions.isEmpty &&
        c.phase == SpeechCapturePhase.idle;
  });
  await fixture('speech_stop_waits_final_result_and_bounds_transcript',
      (s, c) async {
    await c.start();
    final id = s.starts.single;
    await c.stop();
    s.emit('recording', id);
    s.emit('partial', id, text: 'partial');
    final processing = c.phase == SpeechCapturePhase.transcribing;
    s.emit('result', id, text: 'x' * 17000);
    return processing &&
        s.stops.length == 1 &&
        c.phase == SpeechCapturePhase.ready &&
        c.transcript.length == 16000;
  });
  await fixture('speech_permission_revocation_rejects_late_result',
      (s, c) async {
    await c.start();
    final id = s.starts.single;
    s.emit('error', id, code: 'permission_revoked');
    s.emit('result', id, text: 'obsolete');
    return c.phase == SpeechCapturePhase.error &&
        c.transcript.isEmpty &&
        !c.capabilities.permission &&
        s.cancels.contains(id);
  });
  await fixture('speech_dispose_cancels_owned_session_without_resurrection',
      (s, c) async {
    await c.start();
    final id = s.starts.single;
    c.dispose();
    s.emit('result', id, text: 'obsolete');
    return s.cancels.contains(id) && c.transcript.isEmpty;
  });
  await fixture('speech_final_before_start_ack_does_not_regress_to_recording',
      (s, c) async {
    s.onStart = (id) async {
      s.emit('result', id, text: 'already final');
      return true;
    };
    await c.start();
    return c.phase == SpeechCapturePhase.ready &&
        c.transcript == 'already final';
  });
  final tts = Completer<void>();
  await fixture('speech_release_during_tts_stop_never_starts_late_microphone',
      (s, c) async {
    final pending = c.start();
    await Future<void>.delayed(Duration.zero);
    await c.stop();
    tts.complete();
    await pending;
    return s.starts.isEmpty && c.phase == SpeechCapturePhase.idle;
  }, stopSpeaking: () => tts.future);
  await check('speech_native_capability_channel_is_readonly_and_registered',
      () async {
    final status = await const MethodChannel('nexus/speech')
        .invokeMapMethod<String, dynamic>('status');
    if (status != null) {
      nativeSnapshot = {
        for (final key in [
          'onDeviceAvailable',
          'systemAvailable',
          'permissionGranted',
          'foreground',
          'singleUtteranceOnly',
          'supportedSdk',
          'minimumSdk'
        ])
          if (status[key] is bool || status[key] is num) key: status[key]
      };
    }
    return status != null &&
        status['onDeviceAvailable'] is bool &&
        status['systemAvailable'] is bool &&
        status['permissionGranted'] is bool &&
        status['foreground'] is bool &&
        status['singleUtteranceOnly'] == true;
  });
  cases.last['observed'] = nativeSnapshot;
  await fixture('speech_unconfirmed_tts_stop_never_opens_microphone',
      (s, c) async {
    await c.start();
    return c.errorCode == 'tts_stop_unconfirmed' &&
        s.starts.isEmpty &&
        s.permissions.isEmpty;
  }, stopSpeaking: () async {
    throw PlatformException(code: 'TTS_STOP_UNCONFIRMED');
  });
  await fixture(
      'speech_unsupported_sdk_never_requests_permission_or_starts_audio',
      (s, c) async {
    s.capabilities = const SpeechCapabilities(
        onDevice: true, system: true, permission: true, supported: false);
    await c.start();
    return c.errorCode == 'unsupported_sdk' &&
        s.starts.isEmpty &&
        s.permissions.isEmpty;
  });
  return cases;
}
