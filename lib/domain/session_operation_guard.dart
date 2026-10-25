/// Serializes destructive restoration against new agent runs in this process.
/// The lock is acquired before any asynchronous preflight work.
class SessionOperationGuard {
  static final Set<String> _restoring = {};
  static bool get restoring => _restoring.isNotEmpty;
  static void assertCanRun() {
    if (restoring) throw StateError('正在恢复工作区，请等待恢复完成后再执行任务');
  }

  static Future<T> restore<T>(
      String conversationId, Future<T> Function() action) async {
    if (_restoring.isNotEmpty) throw StateError('已有恢复操作正在进行');
    _restoring.add(conversationId);
    try {
      return await action();
    } finally {
      _restoring.remove(conversationId);
    }
  }
}
