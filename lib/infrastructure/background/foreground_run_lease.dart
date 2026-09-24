import 'dart:async';

/// Owns startup deadlines and compensates for late platform completion. A Dart
/// Future.timeout does not cancel the platform request it is waiting for.
class ForegroundRunLease {
  ForegroundRunLease(
      {required this.startPlatform,
      required this.stopPlatform,
      this.startupTimeout = const Duration(seconds: 2)});
  final Future<bool> Function(String title, String text) startPlatform;
  final Future<void> Function() stopPlatform;
  final Duration startupTimeout;
  final Set<Object> _owners = {};
  Future<void> _tail = Future<void>.value();

  int get activeRuns => _owners.length;
  Future<void> get settled => _tail;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      // The requesting start/stop observes the error. Keep the queue usable.
    });
    return result;
  }

  Future<bool> start({required String title, required String text}) async {
    final owner = Object();
    _owners.add(owner);
    final request = _serialize(() async {
      if (!_owners.contains(owner)) return false;
      return startPlatform(title, text);
    });
    var success = false;
    try {
      success = await request.timeout(startupTimeout, onTimeout: () => false);
    } catch (_) {
      // Missing plugins/permissions are a failed keep-alive, not a failed run.
    }
    if (!success) {
      _owners.remove(owner);
      // Queued behind the original request, even after its caller times out.
      unawaited(_stopIfUnused());
    }
    return success;
  }

  Future<void> stop() async {
    if (_owners.isNotEmpty) _owners.remove(_owners.first);
    await _stopIfUnused();
  }

  Future<void> _stopIfUnused() => _serialize(() async {
        if (_owners.isNotEmpty) return;
        try {
          await stopPlatform();
        } catch (_) {
          // Ownership has still been released. A platform stop failure must not
          // poison later runs or surface as an unhandled background Future.
        }
      });
}
