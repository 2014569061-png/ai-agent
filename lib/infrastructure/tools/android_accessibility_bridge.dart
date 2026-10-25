import 'package:flutter/services.dart';

/// Narrow platform channel for the opt-in, read-only accessibility session.
class AndroidAccessibilityBridge {
  const AndroidAccessibilityBridge();

  static const MethodChannel _channel = MethodChannel('nexus/accessibility');

  Future<Map<String, dynamic>> status() => _invoke('status');

  Future<Map<String, dynamic>> openSettings() => _invoke('openSettings');

  Future<Map<String, dynamic>> beginSession(String ownerId) =>
      _invoke('beginSession', {'ownerId': ownerId});

  Future<Map<String, dynamic>> observe({
    required String ownerId,
    required String sessionId,
  }) =>
      _invoke(
        'observe',
        {'ownerId': ownerId, 'sessionId': sessionId},
      );

  Future<Map<String, dynamic>> endSession(String? ownerId) =>
      _invoke('endSession', {if (ownerId != null) 'ownerId': ownerId});

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async =>
      await _channel.invokeMapMethod<String, dynamic>(method, arguments) ??
      const {};
}
