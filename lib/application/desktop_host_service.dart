import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopHostService {
  static final instance = DesktopHostService();
  static const channel = MethodChannel('nexus/desktop_host');
  final _files = StreamController<List<String>>.broadcast();
  Stream<List<String>> get droppedFiles => _files.stream;
  final _images = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get pastedImages => _images.stream;
  Future<bool> pasteImage() async {
    if (!supported) return false;
    final bytes = await channel.invokeMethod<Uint8List>('clipboardImage');
    if (bytes == null) return false;
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return false;
        _images.add(data.buffer.asUint8List());
        return true;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool closeToTray = false;
  final Map<int, String> terminalWorkspaces = {};
  bool hasTerminal(String workspace) => terminalWorkspaces.values.contains(workspace);
  bool notifications = true;
  bool _initialized = false;
  Future<void> initialize() async {
    if (!supported || _initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'filesDropped') {
        _files.add((call.arguments as List).cast<String>());
      }
    });
    final prefs = await SharedPreferences.getInstance();
    closeToTray = prefs.getBool('desktop.closeToTray') ?? false;
    notifications = prefs.getBool('desktop.notifications') ?? true;
    await configure(closeToTray: closeToTray, notifications: notifications);
  }

  Future<void> configure(
      {required bool closeToTray, required bool notifications}) async {
    if (supported) {
      await channel.invokeMethod<void>(
          'configure', {'closeToTray': closeToTray ? 1 : 0});
    }
    this.closeToTray = closeToTray;
    this.notifications = notifications;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('desktop.closeToTray', closeToTray);
    await prefs.setBool('desktop.notifications', notifications);
  }

  Future<void> notify(String title, String body) async {
    if (!supported || !notifications) return;
    await channel.invokeMethod<void>('notify', {'title': title, 'body': body});
  }
}
