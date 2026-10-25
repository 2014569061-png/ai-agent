import 'dart:async';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        ValueNotifier,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter_tts/flutter_tts.dart';

/// Original system TTS service. Engine injection creates an isolated adapter seam;
/// production still uses the existing lazy FlutterTts singleton, never a new run.
class TtsService {
  TtsService._() : _createEngine = FlutterTts.new;
  @visibleForTesting
  TtsService.forTesting() : _createEngine = FlutterTts.new;
  TtsService.withEngineFactory(FlutterTts Function() factory)
      : _createEngine = factory;
  final FlutterTts Function() _createEngine;
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  @visibleForTesting
  static void debugOverride(TtsService? value) => _instance = value;
  FlutterTts? _engine;
  Future<FlutterTts?>? _initializing;
  final _speaking = ValueNotifier<bool>(false);
  int _revision = 0;
  int? _activeSpeak;
  int? _startedSpeak;
  bool _awaitingStart = false;
  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  ValueListenable<bool> get speakingListenable => _speaking;
  bool get isSpeaking => _speaking.value;
  void _setSpeaking(bool value) {
    if (_speaking.value != value) _speaking.value = value;
  }

  bool _current(int revision) => revision == _revision;
  void _finish(int revision) {
    if (_current(revision) && _activeSpeak == revision) {
      _activeSpeak = null;
      _startedSpeak = null;
      _awaitingStart = false;
      _setSpeaking(false);
    }
  }

  /// flutter_tts exposes no utterance id on its completion/cancel/error
  /// handlers, so those global callbacks are advisory only: one is trusted
  /// solely when it arrives for the utterance this service observed starting
  /// for the token it currently owns. Anything else (a cancelled utterance's
  /// late completion, a foreign queued item, a callback from a stopped
  /// utterance) is ignored instead of ending the newer utterance's state.
  /// Continuous conversation must never auto-open the microphone from these
  /// callbacks; it needs a per-utterance correlation that this handler cannot
  /// provide.
  void _nativeTerminated() {
    final active = _activeSpeak;
    if (active == null || _startedSpeak != active) return;
    _finish(active);
  }

  void _nativeStarted() {
    final active = _activeSpeak;
    if (active == null || !_awaitingStart || active != _revision) return;
    _awaitingStart = false;
    _startedSpeak = active;
    _setSpeaking(true);
  }

  Future<bool> speak(String text) async {
    final content = text.trim();
    if (content.isEmpty || !isAvailable) return false;
    final revision = ++_revision;
    try {
      final engine = await _ensureEngine();
      if (engine == null || !_current(revision)) return false;
      if (isSpeaking) {
        await engine.stop();
        if (!_current(revision)) return false;
        _setSpeaking(false);
      }
      _activeSpeak = revision;
      _startedSpeak = null;
      _awaitingStart = true;
      _setSpeaking(true);
      unawaited(engine.speak(content).then<void>((_) => _finish(revision),
          onError: (Object _) => _finish(revision)));
      return true;
    } catch (_) {
      if (_current(revision)) {
        _activeSpeak = null;
        _startedSpeak = null;
        _awaitingStart = false;
        _setSpeaking(false);
      }
      return false;
    }
  }

  /// Legacy stop remains nonthrowing. It also revokes pending initialization.
  Future<void> stop() async {
    await stopBeforeRecording();
  }

  /// Confirms the stop API request, not a physical audio-device measurement.
  /// Failure keeps the voice caller from opening its microphone.
  Future<bool> stopBeforeRecording() async {
    _revision++;
    _activeSpeak = null;
    _startedSpeak = null;
    _awaitingStart = false;
    _setSpeaking(false);
    final engine = _engine;
    if (engine == null) return true;
    try {
      final result = await engine.stop();
      return result == 1 || result == true;
    } catch (_) {
      return false;
    }
  }

  Future<FlutterTts?> _ensureEngine() {
    final engine = _engine;
    if (engine != null) return Future.value(engine);
    if (!isAvailable) return Future.value(null);
    final existing = _initializing;
    if (existing != null) return existing;
    final pending = _loadEngine();
    _initializing = pending;
    unawaited(pending.then<void>((_) {
      if (identical(_initializing, pending)) _initializing = null;
    }));
    return pending;
  }

  Future<FlutterTts?> _loadEngine() async {
    try {
      final engine = _createEngine();
      engine.setStartHandler(_nativeStarted);
      engine.setCompletionHandler(_nativeTerminated);
      engine.setCancelHandler(_nativeTerminated);
      engine.setErrorHandler((_) => _nativeTerminated());
      await engine.setLanguage('zh-CN');
      await engine.awaitSpeakCompletion(true);
      _engine = engine;
      return engine;
    } catch (_) {
      return null;
    } // Do not cache initialization failure.
  }
}
