import 'dart:async';
import 'dart:collection';

/// Convert batches in arrival order. A slow image read cannot let a later
/// share overtake it; a failed read cannot strand later batches.
class ShareBatchIntake {
  ShareBatchIntake(
      {required this.onBatch, required this.onFailure, this.capacity = 8});
  final void Function(List<String>) onBatch;
  final void Function() onFailure;
  final int capacity;
  final _queue = Queue<(Future<List<String>> Function(), Completer<void>)>();
  bool _draining = false;
  Future<void> append(Future<List<String>> Function() read) {
    if (_queue.length + (_draining ? 1 : 0) >= capacity) {
      onFailure();
      return Future.value();
    }
    final done = Completer<void>();
    _queue.add((read, done));
    unawaited(_drain());
    return done.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final (read, done) = _queue.removeFirst();
        try {
          onBatch(List.unmodifiable(await read()));
        } catch (_) {
          onFailure();
        } finally {
          done.complete();
        }
      }
    } finally {
      _draining = false;
    }
  }
}
