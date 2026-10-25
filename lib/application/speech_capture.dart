import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/unique_id.dart';

enum SpeechCapturePhase {
  idle,
  checking,
  permission,
  recording,
  transcribing,
  ready,
  error
}

class SpeechCapabilities {
  const SpeechCapabilities(
      {this.onDevice = false,
      this.system = false,
      this.permission = false,
      this.supported = true});
  factory SpeechCapabilities.fromMap(Map<String, dynamic> value) =>
      SpeechCapabilities(
          onDevice: value['onDeviceAvailable'] == true,
          system: value['systemAvailable'] == true,
          permission: value['permissionGranted'] == true,
          supported: value['supportedSdk'] != false);
  final bool onDevice, system, permission, supported;
}

abstract interface class SpeechCaptureSource {
  Stream<Map<String, dynamic>> get events;
  Future<SpeechCapabilities> inspect();
  Future<bool> requestPermission(String sessionId);
  Future<bool> start(String sessionId,
      {required bool systemService, required String language});
  Future<void> stop(String sessionId);
  Future<void> cancel(String sessionId);
}

class AndroidSpeechCaptureSource implements SpeechCaptureSource {
  AndroidSpeechCaptureSource(this.ownerId);
  final String ownerId;
  static const _methods = MethodChannel('nexus/speech');
  static const _events = EventChannel('nexus/speech/events');
  final _connected = Completer<void>();
  String? _currentSession;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Stream<Map<String, dynamic>> get events => !supported
      ? const Stream.empty()
      : _events.receiveBroadcastStream({'ownerId': ownerId}).map((value) {
          final event = Map<String, dynamic>.from(value as Map);
          if (event['ownerId'] == ownerId &&
              event['type'] == 'connected' &&
              !_connected.isCompleted) {
            _connected.complete();
          }
          return event;
        }).where((value) => value['ownerId'] == ownerId);
  Map<String, dynamic> args(String sessionId) =>
      {'ownerId': ownerId, 'sessionId': sessionId};
  @override
  Future<SpeechCapabilities> inspect() async => !supported
      ? const SpeechCapabilities()
      : SpeechCapabilities.fromMap(
          await _methods.invokeMapMethod<String, dynamic>('status') ?? {});
  @override
  Future<bool> requestPermission(String sessionId) async {
    _currentSession = sessionId;
    await _connected.future.timeout(const Duration(seconds: 5));
    if (_currentSession != sessionId) return false;
    return (await _methods.invokeMapMethod<String, dynamic>(
            'requestPermission', args(sessionId)))?['granted'] ==
        true;
  }

  @override
  Future<bool> start(String sessionId,
      {required bool systemService, required String language}) async {
    _currentSession = sessionId;
    await _connected.future.timeout(const Duration(seconds: 5));
    if (_currentSession != sessionId) return false;
    return (await _methods.invokeMapMethod<String, dynamic>('start', {
          ...args(sessionId),
          'allowSystemService': systemService,
          'language': language
        }))?['accepted'] ==
        true;
  }

  @override
  Future<void> stop(String sessionId) =>
      _methods.invokeMethod<void>('stop', args(sessionId));
  @override
  Future<void> cancel(String sessionId) {
    if (_currentSession == sessionId) _currentSession = null;
    return _methods.invokeMethod<void>('cancel', args(sessionId));
  }
}

/// Single utterance, editable confirmation only. Does not send a message/model request.
class SpeechCaptureController extends ChangeNotifier {
  SpeechCaptureController({required this.source, required this.stopSpeaking});
  final SpeechCaptureSource source;
  final Future<void> Function() stopSpeaking;
  SpeechCapturePhase phase = SpeechCapturePhase.idle;
  SpeechCapabilities capabilities = const SpeechCapabilities();
  String transcript = '';
  String? errorCode;
  String? _session;
  int _revision = 0;
  bool _disposed = false;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Future<void>? _initializing;
  Timer? _limit;
  bool get capturing =>
      phase == SpeechCapturePhase.recording ||
      phase == SpeechCapturePhase.transcribing;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    phase = SpeechCapturePhase.checking;
    changed();
    _subscription = source.events
        .listen(_event, onError: (Object _) => _error('service_disconnected'));
    try {
      capabilities = await source.inspect().timeout(const Duration(seconds: 5));
      if (!_disposed && phase == SpeechCapturePhase.checking) {
        phase = SpeechCapturePhase.idle;
        changed();
      }
    } catch (_) {
      _error('unavailable');
    }
  }

  Future<void> start(
      {bool systemService = false, String language = 'zh-CN'}) async {
    if (_disposed || _session != null) return;
    final revision = ++_revision;
    await initialize();
    if (_disposed || revision != _revision) return;
    if (!capabilities.supported) {
      _error('unsupported_sdk');
      return;
    }
    if (systemService ? !capabilities.system : !capabilities.onDevice) {
      _error('no_recognizer');
      return;
    }
    final id = UniqueId.generate('speech');
    _session = id;
    transcript = '';
    errorCode = null;
    phase = SpeechCapturePhase.checking;
    changed();
    try {
      await stopSpeaking();
      if (!_current(id, revision)) return;
      if (!capabilities.permission) {
        phase = SpeechCapturePhase.permission;
        changed();
        if (!_current(id, revision)) return;
        final granted = await source
            .requestPermission(id)
            .timeout(const Duration(seconds: 60));
        if (!_current(id, revision)) return;
        if (!granted) {
          _error('permission_denied');
          return;
        }
        capabilities = SpeechCapabilities(
            onDevice: capabilities.onDevice,
            system: capabilities.system,
            permission: true);
      }
      phase = SpeechCapturePhase.checking;
      changed();
      if (!_current(id, revision)) return;
      final accepted = await source
          .start(id, systemService: systemService, language: language)
          .timeout(const Duration(seconds: 5));
      if (!_current(id, revision)) return;
      if (!accepted) {
        _error('start_rejected');
        return;
      }
      if (phase != SpeechCapturePhase.ready &&
          phase != SpeechCapturePhase.transcribing) {
        phase = SpeechCapturePhase.recording;
      }
      _limit = Timer(const Duration(seconds: 65), () {
        if (_current(id, revision) && capturing) _error('utterance_limit');
      });
      changed();
    } catch (error) {
      if (_current(id, revision)) {
        _error(error is PlatformException
            ? error.code.toLowerCase()
            : 'service_error');
      }
    }
  }

  bool _current(String id, int revision) =>
      !_disposed && _session == id && _revision == revision;
  void _event(Map<String, dynamic> event) {
    if (_disposed || _session == null || event['sessionId'] != _session) return;
    switch (event['type']) {
      case 'recording':
        if (phase != SpeechCapturePhase.transcribing) {
          phase = SpeechCapturePhase.recording;
        }
      case 'processing':
        phase = SpeechCapturePhase.transcribing;
      case 'partial':
        transcript = (event['text'] is String ? event['text'] as String : '')
            .substringSafe(16000);
      case 'result':
        transcript = (event['text'] is String ? event['text'] as String : '')
            .substringSafe(16000)
            .trim();
        _session = null;
        _limit?.cancel();
        if (transcript.isEmpty) {
          phase = SpeechCapturePhase.error;
          errorCode = 'no_speech';
        } else {
          phase = SpeechCapturePhase.ready;
          errorCode = null;
        }
      case 'error':
        _error(event['code'] as String? ?? 'recognizer_error');
        return;
      case 'stopped':
        _error(event['code'] as String? ?? 'cancelled');
        return;
      default:
        return;
    }
    changed();
  }

  Future<void> stop() async {
    final id = _session;
    if (id == null) {
      if (phase == SpeechCapturePhase.checking) {
        await cancel();
      }
      return;
    }
    if (phase == SpeechCapturePhase.permission ||
        phase == SpeechCapturePhase.checking) {
      await cancel();
      return;
    }
    if (phase == SpeechCapturePhase.transcribing) {
      return;
    }
    phase = SpeechCapturePhase.transcribing;
    changed();
    try {
      await source.stop(id);
    } catch (_) {
      if (_session == id) _error('service_error');
    }
  }

  void _error(String code) {
    if (_disposed) return;
    final id = _session;
    _session = null;
    _revision++;
    _limit?.cancel();
    if (code.contains('permission')) {
      capabilities = SpeechCapabilities(
          onDevice: capabilities.onDevice, system: capabilities.system);
    }
    errorCode = code;
    phase = SpeechCapturePhase.error;
    changed();
    if (id != null) unawaited(source.cancel(id).catchError((Object _) {}));
  }

  Future<void> cancel() async {
    final id = _session;
    _session = null;
    final revision = ++_revision;
    _limit?.cancel();
    transcript = '';
    errorCode = null;
    phase = SpeechCapturePhase.idle;
    changed();
    if (id != null) {
      try {
        await source.cancel(id);
      } catch (_) {
        if (!_disposed && _revision == revision) _error('service_error');
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    final id = _session;
    _session = null;
    _revision++;
    _disposed = true;
    _limit?.cancel();
    unawaited(_subscription?.cancel());
    if (id != null) unawaited(source.cancel(id).catchError((Object _) {}));
    super.dispose();
  }
}

extension _BoundedSpeechString on String {
  String substringSafe(int maximum) =>
      length > maximum ? substring(0, maximum) : this;
}
