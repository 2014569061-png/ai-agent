import 'dart:convert';

import '../../domain/sensitive_tool_policy.dart';
import '../../domain/tool_result.dart';
import '../../infrastructure/tools/tool_registry.dart';
import '../file_baseline_store.dart';
import '../run_event_tracker.dart';
import 'execution_interceptors.dart';
import 'file_baseline_interceptor.dart';
import 'tool_invocation.dart';
import 'tool_pipeline.dart';
import 'tool_run_context.dart';

/// Records every tool call as one RunEvents row (started → finished), for
/// runs that have no UI consumer doing it (headless / background runs).
///
/// Sits first in the chain so it also sees calls stopped by a guard or by
/// approval; `executed` in the finish metadata tells them apart. Uses the same
/// redaction as the chat path ([SensitiveToolPolicy], [RunEventTracker]).
/// Recording is best effort: [RunEventTracker] swallows database failures.
final class RunEventInterceptor implements ToolInterceptor {
  const RunEventInterceptor(this.tracker);

  final RunEventTracker tracker;

  @override
  String get id => 'run-events';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    final call = invocation.call;
    // Workspace file tools are recorded as `file_operation` instead of
    // `tool_call`, mirroring the chat path so both produce the same audit shape.
    final fileOperation =
        isFileOperation(invocation.registration?.spec, call.name);
    final argumentSensitive = SensitiveToolPolicy.isArgumentSensitive(call.name);
    final path = argumentSensitive ? null : call.arguments['path'];
    final newPath = argumentSensitive ? null : call.arguments['newPath'];
    final handle = await tracker.start(
      type: fileOperation ? 'file_operation' : 'tool_call',
      name: call.name,
      inputSummary: jsonEncode(
          SensitiveToolPolicy.redactArguments(call.name, call.arguments)),
      metadata: {
        'tool': call.name,
        if (path != null) 'path': path,
        if (newPath != null) 'newPath': newPath,
      },
    );
    final ToolResult result;
    try {
      result = await next(invocation);
    } on ToolRunCancelled {
      await tracker.finish(handle, status: 'cancelled');
      rethrow;
    } catch (error) {
      await tracker.finish(handle,
          status: 'failed', outputSummary: '工具管线异常：${error.runtimeType}');
      rethrow;
    }
    final executed = invocation.context.executionStarted;
    final toolMetadata = executed
        ? switch (invocation.registration?.executor) {
            final ToolExecutionMetadata source => source.lastMetadata,
            _ => const <String, dynamic>{},
          }
        : const <String, dynamic>{};
    await tracker.finish(
      handle,
      status: result.ok ? 'success' : 'failed',
      outputSummary:
          SensitiveToolPolicy.redactResultText(call.name, result.display),
      metadata: {
        ...toolMetadata,
        'tool': call.name,
        'effect': result.effect.name,
        'toolCode': result.code,
        'fileOperation': fileOperation,
        'executed': executed,
        if (path != null) 'path': path,
        if (fileOperation && !toolMetadata.containsKey('operation'))
          'operation': call.name,
      },
    );
    return result;
  }
}

/// Default pipeline with optional recording (first) and file-original
/// saving (last, right before execution).
ToolPipeline buildToolPipeline({
  RunEventTracker? runEvents,
  FileBaselineStore? baseline,
  void Function(Object error, StackTrace stackTrace)? onBaselineError,
}) =>
    ToolPipeline([
      if (runEvents != null) RunEventInterceptor(runEvents),
      ...defaultToolInterceptors(),
      if (baseline != null)
        FileBaselineInterceptor(baseline, onError: onBaselineError),
    ]);
