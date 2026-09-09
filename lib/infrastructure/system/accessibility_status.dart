import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AccessibilityStatus {
  static const _channel = MethodChannel('nexus/accessibility');

  static Future<bool> isEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }
}
