import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/tool_pipeline/execution_interceptors.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_run_context.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  final calculator = ToolRegistration(
    spec: ToolSpec.fromManifest(CalculatorTool().manifest),
    executor: CalculatorTool(),
  );

  ToolInvocation invocationWith(ToolRunContext context) => ToolInvocation(
        call: const ToolCall(
          id: 'c1',
          name: 'calculator',
          arguments: {'a': 1, 'b': 2},
        ),
        registration: calculator,
        context: context,
      );

  Future<ToolResult> ok(ToolInvocation _) async => ToolResult.text('ok');

  group('CheckpointInterceptor', () {
    test('throws ToolRunCancelled when already cancelled', () {
      final context = ToolRunContext(
        approvalMode: ApprovalMode.ask,
        emit: (_) async {},
        isCancelled: () => true,
      );
      expect(
        const CheckpointInterceptor().intercept(invocationWith(context), ok),
        throwsA(isA<ToolRunCancelled>()),
      );
    });

    test('emits paused, waits for resume, then emits executingTool', () async {
      final trace = <String>[];
      var paused = true;
      final context = ToolRunContext(
        approvalMode: ApprovalMode.ask,
        emit: (event) async {
          if (event is AgentStatusEvent) trace.add(event.status.name);
        },
        isPaused: () => paused,
        waitForResume: () async {
          trace.add('waiting');
          paused = false;
        },
      );
      final result = await const CheckpointInterceptor().intercept(
        invocationWith(context),
        (_) async {
          trace.add('next');
          return ToolResult.text('ok');
        },
      );
      expect(result.ok, isTrue);
      expect(trace, [
        RunStatus.paused.name,
        'waiting',
        RunStatus.executingTool.name,
        'next',
      ]);
    });

    test('cancellation during pause stops before execution', () {
      var cancelled = false;
      final context = ToolRunContext(
        approvalMode: ApprovalMode.ask,
        emit: (_) async {},
        isCancelled: () => cancelled,
        isPaused: () => true,
        waitForResume: () async => cancelled = true,
      );
      expect(
        const CheckpointInterceptor().intercept(invocationWith(context), ok),
        throwsA(isA<ToolRunCancelled>()),
      );
    });
  });

  group('ExecutionBoundary', () {
    test('marks execution started and passes results through', () async {
      final context = ToolRunContext.detached();
      final result = await const ExecutionBoundary()
          .intercept(invocationWith(context), ok);
      expect(context.executionStarted, isTrue);
      expect(result.ok, isTrue);
    });

    test('maps authorization failures to INVALID_ARGUMENTS', () async {
      final result = await const ExecutionBoundary().intercept(
        invocationWith(ToolRunContext.detached()),
        (_) async =>
            throw const ToolApprovalAuthorizationException('ticket expired'),
      );
      expect(result.code, ToolCodes.invalidArguments);
      expect(result.message, 'ticket expired');
      expect(result.effect, ToolEffect.none);
    });

    test('maps other failures to TOOL_ERROR with unknown effect', () async {
      final result = await const ExecutionBoundary().intercept(
        invocationWith(ToolRunContext.detached()),
        (_) async => throw StateError('boom'),
      );
      expect(result.code, ToolCodes.toolError);
      expect(result.effect, ToolEffect.unknown);
    });

    test('never swallows cancellation', () {
      expect(
        const ExecutionBoundary().intercept(
          invocationWith(ToolRunContext.detached()),
          (_) async => throw const ToolRunCancelled(),
        ),
        throwsA(isA<ToolRunCancelled>()),
      );
    });
  });

  group('ApprovalInterceptor', () {
    test('safe tools pass through without asking', () async {
      var asked = false;
      final result = await const ApprovalInterceptor().intercept(
        invocationWith(ToolRunContext.detached(
          approveTool: (_, __, ___) async {
            asked = true;
            return ToolApproval.reject;
          },
        )),
        ok,
      );
      expect(asked, isFalse);
      expect(result.ok, isTrue);
    });
  });

  test('executeWithTimeout reports a timeout with unknown effect', () async {
    final registration = ToolRegistration(
      spec: ToolSpec.fromManifest(CalculatorTool().manifest)
          .copyWith(timeout: const Duration(milliseconds: 10)),
      executor: _NeverCompletes(),
    );
    final result = await executeWithTimeout(ToolInvocation(
      call: const ToolCall(id: 't', name: 'calculator', arguments: {}),
      registration: registration,
      context: ToolRunContext.detached(),
    ));
    expect(result.code, ToolCodes.timeout);
    expect(result.effect, ToolEffect.unknown);
  });
}

class _NeverCompletes implements ToolExecutor {
  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) =>
      Completer<ToolResult>().future;
}
