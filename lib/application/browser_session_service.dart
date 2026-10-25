import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/browser_session.dart';
import '../domain/tool_codes.dart';
import '../infrastructure/browser/android_browser_transport.dart';

final browserSessionProvider = Provider<BrowserSessionService>((ref) {
  final service = BrowserSessionService(AndroidBrowserTransport());
  ref.onDispose(service.dispose);
  return service;
});

/// UI owns a foreground session. A tool run can only borrow its frozen owner.
class BrowserSessionService extends ChangeNotifier {
  BrowserSessionService(this.transport);
  final BrowserTransport transport;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Map<String, dynamic> state = const {};
  Map<String, dynamic>? observation;
  String? owner;
  String? errorCode;
  bool _disposed = false;
  bool _opening = false;
  bool _closing = false;
  int _generation = 0;
  String? get sessionId => state['sessionId'] as String?;
  bool get agentControlled => state['mode'] == 'agent';
  int get epoch => (state['epoch'] as num?)?.toInt() ?? -1;
  bool availableFor(String id) =>
      owner == id && sessionId != null && !_disposed;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _accept(Map<String, dynamic> update) {
    if (_disposed || update['sessionId'] != sessionId) return;
    if ((update['epoch'] as num? ?? -1) < epoch) return;
    if (update['epoch'] != epoch || update['mode'] != 'agent') {
      observation = null;
    }
    state = Map.unmodifiable(update);
    _changed();
  }

  Future<void> open(String conversationId) async {
    if (_opening || _closing || sessionId != null || _disposed) {
      throw const BrowserFailure(ToolCodes.alreadyExists);
    }
    _opening = true;
    final generation = ++_generation;
    try {
      _subscription ??= transport.events.listen(_accept, onError: (Object _) {
        errorCode = ToolCodes.capabilityUnavailable;
        observation = null;
        state = {...state, 'mode': 'user'};
        _changed();
      });
      final created = await transport.invoke('open', {});
      if (_disposed || generation != _generation) {
        await transport.invoke('close', {'sessionId': created['sessionId']});
        return;
      }
      owner = conversationId;
      state = Map.unmodifiable(created);
      errorCode = null;
      _changed();
    } finally {
      _opening = false;
    }
  }

  Future<Map<String, dynamic>> command(
      String expectedOwner, String method, Map<String, dynamic> args) async {
    if (!availableFor(expectedOwner)) {
      throw const BrowserFailure(ToolCodes.ownerMismatch);
    }
    final session = sessionId;
    final generation = _generation;
    final result =
        await transport.invoke(method, {...args, 'sessionId': session});
    if (_disposed || generation != _generation || session != sessionId) {
      throw BrowserFailure(ToolCodes.sessionExpired,
          dispatched: method == 'act' || method == 'navigate');
    }
    final update = result['state'];
    if (update is Map) _accept(Map<String, dynamic>.from(update));
    if (method == 'observe') {
      if (result['epoch'] != epoch || !agentControlled) {
        throw const BrowserFailure(ToolCodes.revisionConflict);
      }
      observation = Map.unmodifiable(result);
    }
    return result;
  }

  Future<void> control(String mode) async {
    final id = sessionId;
    if (id == null || _disposed) return;
    observation = null;
    // Revoke locally before crossing the platform boundary.
    if (mode != 'agent') {
      state = {...state, 'mode': 'user'};
      _changed();
    }
    final result =
        await transport.invoke('control', {'sessionId': id, 'mode': mode});
    _accept(result);
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    final id = sessionId;
    ++_generation;
    owner = null;
    state = const {};
    observation = null;
    _changed();
    try {
      if (id != null) await transport.invoke('close', {'sessionId': id});
    } finally {
      final subscription = _subscription;
      _subscription = null;
      try {
        await subscription?.cancel();
      } finally {
        _closing = false;
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    final id = sessionId;
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    if (id != null) {
      unawaited(transport.invoke('close', {'sessionId': id}).catchError(
          (Object _) => <String, dynamic>{'cleanupUnconfirmed': true}));
    }
    super.dispose();
  }
}
