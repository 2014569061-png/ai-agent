import '../../domain/tool_result.dart';
import '../file_baseline_store.dart';
import 'execution_interceptors.dart';
import 'tool_invocation.dart';
import 'tool_pipeline.dart';

/// Saves each file's original content right before a workspace tool mutates
/// it, so a task's change set can restore the exact pre-task state (including
/// deletes, moves, binary files and large edits whose diffs are truncated).
///
/// Sits last in the chain: it only runs for calls that passed approval and
/// are about to execute. A failure to save never blocks the tool; the change
/// set then falls back to reconstructing the baseline from recorded diffs.
final class FileBaselineInterceptor implements ToolInterceptor {
  const FileBaselineInterceptor(this.store, {this.onError});

  final FileBaselineStore store;
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Mutating workspace tools and the argument keys naming the paths they touch.
  static const mutatingTools = <String, List<String>>{
    'write_file': ['path'],
    'edit_file': ['path'],
    'delete_file': ['path'],
    'move_file': ['path', 'newPath'],
  };

  @override
  String get id => 'file-baseline';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    final keys = mutatingTools[invocation.call.name];
    if (keys != null) {
      final arguments = invocation.arguments;
      final paths = [
        for (final key in keys)
          if (arguments[key] case final String path when path.trim().isNotEmpty)
            path,
      ];
      try {
        await store.preserve(paths);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    }
    return next(invocation);
  }
}

/// Default pipeline plus [FileBaselineInterceptor] for runs bound to a task
/// and a workspace; `null` (use the executor's default) otherwise.
ToolPipeline? fileBaselinePipeline({
  String? taskId,
  String? workspacePath,
  void Function(Object error, StackTrace stackTrace)? onError,
}) {
  if (taskId == null || taskId.isEmpty) return null;
  if (workspacePath == null || workspacePath.trim().isEmpty) return null;
  return ToolPipeline([
    ...defaultToolInterceptors(),
    FileBaselineInterceptor(
      FileBaselineStore(taskId: taskId, workspacePath: workspacePath),
      onError: onError,
    ),
  ]);
}
