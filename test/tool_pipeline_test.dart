import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/tool_pipeline/preflight_guards.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_pipeline.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_run_context.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  ToolInvocation invocationFor(ToolRegistration? registration) =>
      ToolInvocation(
        call: const ToolCall(id: 'c1', name: 'calculator', arguments: {}),
        registration: registration,
        context: ToolRunContext.detached(),
      );

  final calculator = ToolRegistration(
    spec: ToolSpec.fromManifest(CalculatorTool().manifest),
    executor: CalculatorTool(),
  );

  test('rejects duplicate interceptor ids', () {
    expect(
      () => ToolPipeline(const [UnknownToolGuard(), UnknownToolGuard()]),
      throwsArgumentError,
    );
  });

  test('runs interceptors in order around the terminal', () async {
    final trace = <String>[];
    final pipeline = ToolPipeline([
      _Tracing('a', trace),
      _Tracing('b', trace),
    ]);
    final result = await pipeline.run(invocationFor(calculator), (_) async {
      trace.add('terminal');
      return ToolResult.text('done');
    });
    expect(result.ok, isTrue);
    expect(trace, ['a:before', 'b:before', 'terminal', 'b:after', 'a:after']);
  });

  test('the terminal receives the invocation rewritten upstream', () async {
    ToolInvocation? seen;
    await ToolPipeline(const [_Annotating()]).run(
      invocationFor(calculator),
      (invocation) async {
        seen = invocation;
        return ToolResult.text('done');
      },
    );
    expect(seen?.approvalDetails, {'annotated': true});
  });

  test('a guard short-circuits before the terminal runs', () async {
    var terminalRan = false;
    final result = await ToolPipeline(defaultToolPreflightGuards()).run(
      invocationFor(null),
      (_) async {
        terminalRan = true;
        return ToolResult.text('done');
      },
    );
    expect(terminalRan, isFalse);
    expect(result.code, ToolCodes.unknownTool);
  });

  test('execution arguments override the model arguments only downstream',
      () {
    final original = invocationFor(calculator);
    final authorized = original.withExecutionArguments(const {'a': 1});
    expect(original.arguments, isEmpty);
    expect(authorized.arguments, {'a': 1});
    expect(authorized.call.arguments, isEmpty);
    expect(authorized.withApprovalDetails(null).arguments, {'a': 1});
  });

  test('resolved throws a StateError when the tool is unregistered', () {
    expect(() => invocationFor(null).resolved, throwsStateError);
  });
}

class _Tracing implements ToolInterceptor {
  _Tracing(this.id, this.trace);

  @override
  final String id;
  final List<String> trace;

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) async {
    trace.add('$id:before');
    final result = await next(invocation);
    trace.add('$id:after');
    return result;
  }
}

class _Annotating implements ToolInterceptor {
  const _Annotating();

  @override
  String get id => 'annotating';

  @override
  Future<ToolResult> intercept(ToolInvocation invocation, ToolNext next) =>
      next(invocation.withApprovalDetails(const {'annotated': true}));
}
