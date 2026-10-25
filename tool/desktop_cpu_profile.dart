// Diagnostic-only VM CPU sampling. Never enabled by a release acceptance run.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

Map<String, Object?> summarizeDesktopCpuProfile(Map<String, dynamic> profile) {
  final count = profile['sampleCount'] as int;
  if (count <= 0) throw StateError('CPU profile has no samples');
  final functions = (profile['functions'] as List).map((value) {
    final entry = value as Map;
    final function = entry['function'] as Map?;
    return <String, Object?>{
      'name': function?['name'] ?? entry['name'] ?? '<native>',
      'script': (function?['location'] as Map?)?['script']?['uri'],
      'exclusiveTicks': entry['exclusiveTicks'],
      'inclusiveTicks': entry['inclusiveTicks'],
    };
  }).toList();
  List<Map<String, Object?>> top(String field) => (List.of(functions)
        ..sort((a, b) => (b[field] as int).compareTo(a[field] as int)))
      .take(35)
      .toList();
  return {
    'sampleCount': count,
    'samplePeriodUs': profile['samplePeriod'],
    'topExclusive': top('exclusiveTicks'),
    'topInclusive': top('inclusiveTicks')
  };
}

class DesktopCpuProfile {
  DesktopCpuProfile._(this._socket, this._isolate) {
    _subscription = _socket.listen((message) {
      final response = jsonDecode(message as String) as Map<String, dynamic>;
      final reply = _pending[response['id']];
      if (reply == null) return;
      if (response['error'] != null) {
        reply
            .completeError(StateError('CPU profile RPC: ${response['error']}'));
      } else {
        reply.complete(response['result'] as Map<String, dynamic>);
      }
    });
  }
  final WebSocket _socket;
  final String _isolate;
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _sequence = 0;

  static Future<DesktopCpuProfile?> startIfRequested() async {
    if (Platform.environment['MOBILE_AGENT_P2_CPU_PROFILE'] != '1') return null;
    if (!kProfileMode) {
      throw StateError('CPU diagnostics require a profile build');
    }
    var info = await developer.Service.getInfo();
    info = info.serverUri == null
        ? await developer.Service.controlWebServer(enable: true)
        : info;
    final uri = info.serverUri;
    if (uri == null) throw StateError('VM service is unavailable');
    if (!{'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
      throw StateError('CPU diagnostics require a loopback VM service');
    }
    final socket = await WebSocket.connect(
        uri.replace(scheme: 'ws', path: '${uri.path}ws').toString());
    final profiler = DesktopCpuProfile._(
        socket, developer.Service.getIsolateId(Isolate.current)!);
    try {
      await profiler._call('setFlag', {'name': 'profiler', 'value': 'true'});
      return profiler;
    } catch (_) {
      await profiler.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _call(
      String method, Map<String, Object> parameters) async {
    final id = ++_sequence;
    final reply = Completer<Map<String, dynamic>>();
    _pending[id] = reply;
    _socket.add(jsonEncode(
        {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': parameters}));
    try {
      return await reply.future.timeout(const Duration(seconds: 10));
    } finally {
      _pending.remove(id);
    }
  }

  int begin() => developer.Timeline.now;
  Future<Map<String, Object?>> capture(String name, int start) async {
    final end = developer.Timeline.now;
    final profile = await _call('getCpuSamples', {
      'isolateId': _isolate,
      'timeOriginMicros': start,
      'timeExtentMicros': end - start
    });
    final file = File('artifacts/desktop/p2-history-cpu-$start-$name.json');
    await file.writeAsString(jsonEncode(profile));
    return {
      'rawFile': file.path,
      'durationUs': end - start,
      ...summarizeDesktopCpuProfile(profile)
    };
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
  }
}
