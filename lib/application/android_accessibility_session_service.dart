import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/tools/android_accessibility_bridge.dart';

final androidAccessibilitySessionProvider =
    Provider<AndroidAccessibilitySessionService>((ref) {
  final service = AndroidAccessibilitySessionService(
    const AndroidAccessibilityBridge(),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// A foreground-only observation session, explicitly owned by one conversation.
class AndroidAccessibilitySessionService extends ChangeNotifier {
  AndroidAccessibilitySessionService(this.bridge);

  final AndroidAccessibilityBridge bridge;
  bool _disposed = false;
  bool _busy = false;
  bool enabled = false;
  String? owner;
  String? sessionId;
  int? expiresAtMs;
  String? errorCode;

  bool get active {
    final expiry = expiresAtMs;
    return sessionId != null &&
        owner != null &&
        (expiry == null || DateTime.now().millisecondsSinceEpoch < expiry);
  }

  bool get busy => _busy;

  bool availableFor(String conversationId) =>
      !_disposed && active && owner == conversationId;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshStatus() async {
    final status = await bridge.status();
    enabled = status['enabled'] == true;
    final nativeActive = status['sessionActive'] == true;
    final nativeSession = status['sessionId'] as String?;
    if (!nativeActive || nativeSession == null) {
      owner = null;
      sessionId = null;
      expiresAtMs = null;
    } else if (sessionId != nativeSession || owner == null) {
      // A Dart restart must not silently adopt an old native session.
      await bridge.endSession(null);
      owner = null;
      sessionId = null;
      expiresAtMs = null;
    } else {
      expiresAtMs = (status['expiresAtMs'] as num?)?.toInt();
    }
    errorCode = null;
    _changed();
  }

  Future<void> openSettings() async {
    await bridge.openSettings();
  }

  Future<void> beginSession(String conversationId) async {
    if (_disposed || _busy) {
      throw const AccessibilitySessionFailure('SESSION_BUSY');
    }
    if (conversationId.trim().isEmpty || conversationId.length > 120) {
      throw const AccessibilitySessionFailure('INVALID_OWNER');
    }
    if (active) {
      if (owner == conversationId) return;
      throw const AccessibilitySessionFailure('OWNER_MISMATCH');
    }
    _busy = true;
    _changed();
    try {
      final result = await bridge.beginSession(conversationId);
      if (result['ok'] != true || result['sessionId'] is! String) {
        final code = (result['code'] as String?) ?? 'SERVICE_UNAVAILABLE';
        errorCode = code;
        throw AccessibilitySessionFailure(code);
      }
      owner = conversationId;
      sessionId = result['sessionId'] as String;
      expiresAtMs = (result['expiresAtMs'] as num?)?.toInt();
      errorCode = null;
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<Map<String, dynamic>> observe(
    String conversationId, {
    String? expectedSessionId,
  }) async {
    if (!availableFor(conversationId)) {
      throw const AccessibilitySessionFailure('SESSION_EXPIRED');
    }
    final session = sessionId!;
    if (expectedSessionId != null && expectedSessionId != session) {
      throw const AccessibilitySessionFailure('SESSION_EXPIRED');
    }
    final result = await bridge.observe(
      ownerId: conversationId,
      sessionId: session,
    );
    if (_disposed || !availableFor(conversationId) || sessionId != session) {
      throw const AccessibilitySessionFailure('SESSION_EXPIRED');
    }
    if (result['ok'] != true) {
      final code = (result['code'] as String?) ?? 'WINDOW_UNAVAILABLE';
      if (code == 'SESSION_EXPIRED' || code == 'SERVICE_UNAVAILABLE') {
        owner = null;
        sessionId = null;
        expiresAtMs = null;
        _changed();
      }
      throw AccessibilitySessionFailure(code);
    }
    return Map.unmodifiable(result);
  }

  Future<void> endSession([String? expectedOwner]) async {
    if (expectedOwner != null && owner != expectedOwner) return;
    final previousOwner = owner;
    // Revoke local authority before the platform call.
    owner = null;
    sessionId = null;
    expiresAtMs = null;
    _changed();
    try {
      await bridge.endSession(previousOwner ?? expectedOwner);
    } catch (_) {
      errorCode = 'CLEANUP_UNCONFIRMED';
      _changed();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    final previousOwner = owner;
    _disposed = true;
    owner = null;
    sessionId = null;
    unawaited(bridge.endSession(previousOwner).catchError(
          (Object _) => <String, dynamic>{'ok': false},
        ));
    super.dispose();
  }
}

class AccessibilitySessionFailure implements Exception {
  const AccessibilitySessionFailure(this.code);

  final String code;

  @override
  String toString() => 'AccessibilitySessionFailure($code)';
}
