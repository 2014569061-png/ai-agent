import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../infrastructure/tts/tts_service.dart';

/// Implements the public adapter without constructing FlutterTts or replacing
/// its global platform channel. No device engine/sound is used by these checks.
class _FixtureTts implements FlutterTts {
  Completer<dynamic>? languageGate, stopGate;
  bool failConfiguration = false;
  bool emitStart = true;
  int languages = 0, stops = 0;
  final spoken = <String>[];
  final playback = <Completer<dynamic>>[];
  dynamic started, completed, cancelled, failed;
  @override
  void setStartHandler(dynamic value) {
    started = value;
  }

  @override
  void setCompletionHandler(dynamic value) {
    completed = value;
  }

  @override
  void setCancelHandler(dynamic value) {
    cancelled = value;
  }

  @override
  void setErrorHandler(dynamic value) {
    failed = value;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    languages++;
    if (failConfiguration) throw StateError('Synthetic configuration failure');
    if (languageGate != null) return languageGate!.future;
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool value) async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken.add(text);
    if (emitStart) started?.call();
    final value = Completer<dynamic>();
    playback.add(value);
    return value.future;
  }

  @override
  Future<dynamic> stop() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
    cancelled?.call();
    for (final value in playback) {
      if (!value.isCompleted) value.complete(0);
    }
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused synthetic TTS method');
}

Future<List<Map<String, dynamic>>> runTtsLifecycleChecks() async {
  final cases = <Map<String, dynamic>>[];
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

  await check('tts_stop_during_initialization_prevents_late_audio_start',
      () async {
    final engine = _FixtureTts()..languageGate = Completer<dynamic>();
    final service = TtsService.withEngineFactory(() => engine);
    final pending = service.speak('obsolete synthetic text');
    final stopped = await service.stopBeforeRecording();
    engine.languageGate!.complete(1);
    final started = await pending;
    engine.started?.call();
    return stopped && !started && engine.spoken.isEmpty && !service.isSpeaking;
  });
  await check(
      'tts_concurrent_pending_speak_uses_one_initialization_and_latest_owner',
      () async {
    final engine = _FixtureTts()..languageGate = Completer<dynamic>();
    var creations = 0;
    final service = TtsService.withEngineFactory(() {
      creations++;
      return engine;
    });
    try {
      final old = service.speak('old');
      final current = service.speak('new');
      engine.languageGate!.complete(1);
      return !await old &&
          await current &&
          creations == 1 &&
          engine.languages == 1 &&
          engine.spoken.length == 1 &&
          engine.spoken.single == 'new';
    } finally {
      await service.stop();
    }
  });
  await check('tts_stop_revokes_replacement_waiting_for_old_stop', () async {
    final engine = _FixtureTts();
    final service = TtsService.withEngineFactory(() => engine);
    try {
      if (!await service.speak('first')) return false;
      engine.stopGate = Completer<dynamic>();
      final replacement = service.speak('replacement');
      await Future<void>.delayed(Duration.zero);
      final stop = service.stopBeforeRecording();
      engine.stopGate!.complete(1);
      return !await replacement &&
          await stop &&
          engine.spoken.length == 1 &&
          engine.spoken.single == 'first' &&
          !service.isSpeaking;
    } finally {
      if (engine.stopGate?.isCompleted == false) engine.stopGate!.complete(1);
      await service.stop();
    }
  });
  await check('tts_cancelled_owner_ignores_late_start_callback', () async {
    final engine = _FixtureTts();
    final service = TtsService.withEngineFactory(() => engine);
    await service.speak('synthetic');
    await service.stop();
    engine.started?.call();
    return !service.isSpeaking && engine.stops == 1;
  });
  await check('tts_initialization_failure_is_retryable_without_caching_failure',
      () async {
    final first = _FixtureTts()..failConfiguration = true;
    final second = _FixtureTts();
    var creations = 0;
    final service =
        TtsService.withEngineFactory(() => ++creations == 1 ? first : second);
    try {
      return !await service.speak('first') &&
          await service.speak('retry') &&
          creations == 2 &&
          second.spoken.single == 'retry';
    } finally {
      await service.stop();
    }
  });
  await check(
      'tts_global_completion_without_matching_start_is_not_trusted', () async {
    final engine = _FixtureTts()..emitStart = false;
    final service = TtsService.withEngineFactory(() => engine);
    try {
      if (!await service.speak('synthetic')) return false;
      final speakingAfterRequest = service.isSpeaking;
      engine.completed?.call();
      final untrustedIgnored = service.isSpeaking;
      engine.started?.call();
      final lateStartAccepted = service.isSpeaking;
      engine.completed?.call();
      return speakingAfterRequest && untrustedIgnored && lateStartAccepted &&
          !service.isSpeaking;
    } finally {
      await service.stop();
    }
  });
  await check(
      'tts_foreign_completion_while_replacement_awaits_start_is_ignored',
      () async {
    final engine = _FixtureTts();
    final service = TtsService.withEngineFactory(() => engine);
    try {
      if (!await service.speak('first')) return false;
      engine.emitStart = false;
      final requested = await service.speak('replacement');
      engine.completed?.call();
      final ignoredBeforeStart = service.isSpeaking;
      engine.playback.last.complete(1);
      await Future<void>.delayed(Duration.zero);
      return requested && ignoredBeforeStart && !service.isSpeaking;
    } finally {
      await service.stop();
    }
  });
  await check('tts_error_callback_before_start_keeps_correlated_owner', () async {
    final engine = _FixtureTts()..emitStart = false;
    final service = TtsService.withEngineFactory(() => engine);
    try {
      if (!await service.speak('synthetic')) return false;
      engine.failed?.call('synthetic error');
      final ignored = service.isSpeaking;
      engine.playback.single.completeError(StateError('synthetic'));
      await Future<void>.delayed(Duration.zero);
      return ignored && !service.isSpeaking;
    } finally {
      await service.stop();
    }
  });
  await check(
      'tts_stop_drops_start_ownership_so_late_callbacks_are_ignored', () async {
    final engine = _FixtureTts();
    final service = TtsService.withEngineFactory(() => engine);
    final requested = await service.speak('synthetic');
    final stopped = await service.stopBeforeRecording();
    engine.completed?.call();
    engine.failed?.call('late synthetic error');
    engine.started?.call();
    return requested && stopped && !service.isSpeaking;
  });
  return cases;
}
