import 'package:flutter/services.dart';

import '../../domain/browser_session.dart';

class AndroidBrowserTransport implements BrowserTransport {
  static const methods = MethodChannel('nexus/browser');
  static const updates = EventChannel('nexus/browser/events');
  // EventChannel installs one binary message handler. Share its broadcast
  // stream so a fixture/second service cannot disconnect an existing listener.
  static final _events = updates
      .receiveBroadcastStream()
      .map((value) => Map<String, dynamic>.from(value as Map));

  @override
  Stream<Map<String, dynamic>> get events => _events;

  @override
  Future<Map<String, dynamic>> invoke(
      String method, Map<String, dynamic> args) async {
    try {
      return await methods.invokeMapMethod<String, dynamic>(method, args) ?? {};
    } on MissingPluginException {
      throw const BrowserFailure('PLATFORM_UNSUPPORTED');
    } on PlatformException catch (error) {
      throw BrowserFailure(error.code,
          dispatched: error.details is Map &&
              (error.details as Map)['dispatched'] == true);
    }
  }
}
