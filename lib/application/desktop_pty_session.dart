import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'desktop_pty_terminal.dart';
import 'desktop_host_service.dart';

/// A shell belongs to its workspace, independently of the currently visible pane.
class DesktopPtySession extends ChangeNotifier {
  DesktopPtySession(this.workspace) {
    terminal.onOutput = (text) => unawaited(write(text));
    terminal.onResize =
        (cols, rows, width, height) => unawaited(resize(cols, rows));
  }
  final String workspace;
  final terminal = DesktopPtyTerminal(maxLines: 5000);
  StreamController<List<int>>? _bytes;
  StreamSubscription<String>? _decoded;
  Timer? _timer;
  int? _id;
  int _generation = 0;
  Future<void>? _opening, _closing;
  bool _polling = false, opening = false, _disposed = false;
  String? error;
  String shell = 'powershell';
  bool get connected => _id != null;
  bool get closing => _closing != null;

  Future<void> open() {
    if (opening || connected || closing || _disposed) return Future.value();
    opening = true;
    error = null;
    notifyListeners();
    return _opening = _open(_generation);
  }

  Future<void> _open(int generation) async {
    try {
      final id =
          await DesktopHostService.channel.invokeMethod<int>('openTerminal', {
        'cwd': workspace,
        'cols': terminal.viewWidth,
        'rows': terminal.viewHeight,
        'shell': shell,
      });
      if (id == null) throw StateError('原生终端未返回会话编号');
      DesktopHostService.instance.terminalWorkspaces[id] = workspace;
      _id = id;
      if (_disposed || generation != _generation) {
        await _closeNative(id);
        _id = null;
        return;
      }
      _bytes = StreamController<List<int>>();
      _decoded = _bytes!.stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);
      _timer = Timer.periodic(
          const Duration(milliseconds: 32), (_) => unawaited(_poll()));
    } catch (failure) {
      error = '无法启动终端：$failure';
    } finally {
      opening = false;
      _opening = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _poll() async {
    final id = _id;
    if (_polling || id == null || _disposed) return;
    _polling = true;
    try {
      final data = await DesktopHostService.channel
          .invokeMapMethod<String, dynamic>('readTerminal', {'id': id});
      if (_disposed || id != _id || closing) return;
      if (data == null) throw StateError('原生终端未返回输出');
      final bytes = (data['bytes'] as List?)?.cast<int>();
      if (bytes != null && bytes.isNotEmpty) _bytes!.add(bytes);
      if (data['exitCode'] != 259 && (bytes == null || bytes.isEmpty)) {
        terminal.write('\r\n[终端已退出：${data['exitCode']}]\r\n');
        await close();
      }
    } catch (failure) {
      _timer?.cancel();
      error = '$failure';
      if (!_disposed) notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> write(String text) async {
    final id = _id;
    if (id == null || _disposed || closing) return;
    try {
      await DesktopHostService.channel
          .invokeMethod<void>('writeTerminal', {'id': id, 'text': text});
    } catch (failure) {
      error = '$failure';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resize(int cols, int rows) async {
    final id = _id;
    if (id == null || _disposed || closing) return;
    try {
      await DesktopHostService.channel.invokeMethod<void>(
          'resizeTerminal', {'id': id, 'cols': cols, 'rows': rows});
    } catch (failure) {
      error = '$failure';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _closeNative(int id) async {
    await DesktopHostService.channel
        .invokeMethod<void>('closeTerminal', {'id': id});
    // Recovery guards must continue to see the workspace until native close is acknowledged.
    DesktopHostService.instance.terminalWorkspaces.remove(id);
  }

  Future<void> close() => _closing ??= _close().whenComplete(() {
        _closing = null;
        if (!_disposed) notifyListeners();
      });

  Future<void> _close() async {
    _generation++;
    _timer?.cancel();
    await _opening;
    final id = _id;
    if (id != null) {
      try {
        await _closeNative(id);
        _id = null;
      } catch (failure) {
        error = '无法停止终端：$failure';
        rethrow;
      }
    }
    await _bytes?.close();
    await _decoded?.cancel();
    _bytes = null;
    _decoded = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close().catchError((Object error) {
      debugPrint('终端释放失败：$error');
    }));
    super.dispose();
  }
}

class DesktopPtySessions {
  static final instance = DesktopPtySessions();
  final Map<String, DesktopPtySession> _sessions = {};
  DesktopPtySession forWorkspace(String workspace) =>
      _sessions.putIfAbsent(workspace, () => DesktopPtySession(workspace));
  Future<void> closeAll() async {
    for (final entry in _sessions.entries.toList()) {
      await entry.value.close();
      entry.value.dispose();
      _sessions.remove(entry.key);
    }
  }
}
