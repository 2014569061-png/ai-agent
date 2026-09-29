// 工具执行链路特征测试（重构 S1）。
//
// 锁定 AgentExecutor 在工具调用循环中的现有行为：守卫顺序、错误码、审批
// 参数隔离、拒绝回滚、授权异常、审批后取消、元数据透传，以及「每个调用
// 恰好一个结果事件 + 一条 tool 消息且顺序与调用一致」的不变式。后续把
// 循环拆成可插拔管线时，这些测试必须保持通过。
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  List<ChatMessage> userInput() => [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('run')],
        ),
      ];

  Future<_RunCapture> runWith(
    ToolRegistry registry,
    List<ToolCall> calls, {
    ToolApprovalCallback? approveTool,
    AgentCancellationToken? cancellationToken,
  }) async {
    final provider = _ScriptedProvider(calls);
    final capture = _RunCapture(provider);
    await for (final event in AgentExecutor(
      provider: provider,
      tools: registry,
    ).run(
      history: userInput(),
      model: 'test',
      maxSteps: 2,
      approveTool: approveTool,
      cancellationToken: cancellationToken,
    )) {
      capture.events.add(event);
    }
    return capture;
  }

  group('guards', () {
    test('unknown tool fails with UNKNOWN_TOOL and never asks for approval',
        () async {
      var asked = false;
      final capture = await runWith(
        ToolRegistry(),
        const [ToolCall(id: 'u1', name: 'missing_tool', arguments: {})],
        approveTool: (_, __, ___) async {
          asked = true;
          return ToolApproval.allowOnce;
        },
      );
      expect(asked, isFalse);
      expect(capture.results.single.call.id, 'u1');
      expect(capture.results.single.result.code, ToolCodes.unknownTool);
      expect(capture.results.single.result.effect, ToolEffect.none);
    });

    test('unknown tool is reported before truncated arguments', () async {
      final capture = await runWith(
        ToolRegistry(),
        const [
          ToolCall(id: 'u2', name: 'missing_tool', arguments: {'_unparsed': 'x'}),
        ],
      );
      expect(capture.results.single.result.code, ToolCodes.unknownTool);
    });

    test('truncated arguments are reported before schema validation',
        () async {
      final tool = _StrictTool();
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(id: 't1', name: 'strict', arguments: {'_unparsed': '{"a":'}),
        ],
      );
      expect(tool.executions, 0);
      expect(capture.results.single.result.code, ToolCodes.truncatedToolCall);
    });

    test('context-truncated argument mark is treated as truncated', () async {
      final tool = _StrictTool();
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(
            id: 't2',
            name: 'strict',
            arguments: {ContextWindow.truncatedArgumentMark: true, 'value': 1},
          ),
        ],
      );
      expect(tool.executions, 0);
      expect(capture.results.single.result.code, ToolCodes.truncatedToolCall);
    });

    test('schema violation fails with INVALID_ARGUMENTS without executing',
        () async {
      final tool = _StrictTool();
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [ToolCall(id: 's1', name: 'strict', arguments: {})],
      );
      expect(tool.executions, 0);
      expect(capture.results.single.result.code, ToolCodes.invalidArguments);
      expect(capture.results.single.result.message, contains('参数校验失败'));
    });

    test('missing preview plan is rejected before approval is requested',
        () async {
      final tool = _GateTool();
      var asked = false;
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(
            id: 'p1',
            name: 'gate_fixture',
            arguments: {'action': 'delete', 'planId': 'unknown-plan'},
          ),
        ],
        approveTool: (_, __, ___) async {
          asked = true;
          return ToolApproval.allowOnce;
        },
      );
      expect(asked, isFalse);
      expect(tool.executions, 0);
      expect(tool.authorizations, 0);
      expect(capture.results.single.result.code, ToolCodes.invalidArguments);
      expect(capture.results.single.result.message, contains('预览'));
    });
  });

  group('approval', () {
    test('approval details reach the approver but never the executor',
        () async {
      final tool = _GateTool();
      ToolCall? approvalCall;
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(
            id: 'a1',
            name: 'gate_fixture',
            arguments: {'action': 'delete', 'planId': 'plan-1'},
          ),
        ],
        approveTool: (call, risk, sensitive) async {
          approvalCall = call;
          expect(risk, ToolRisk.dangerous);
          return ToolApproval.allowOnce;
        },
      );
      expect(approvalCall?.arguments['_approvalDetails'], isA<Map>());
      expect(
        capture.events.whereType<ApprovalRequiredEvent>().single.call
            .arguments['_approvalDetails'],
        isA<Map>(),
      );
      expect(tool.authorizations, 1);
      expect(tool.executions, 1);
      expect(tool.lastArguments?.containsKey('_approvalDetails'), isFalse);
      expect(tool.lastArguments?['previewId'], 'issued-after-approval');
      expect(capture.results.single.result.ok, isTrue);
    });

    test('rejection calls rejectApproval once and skips execution', () async {
      final tool = _GateTool();
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(
            id: 'a2',
            name: 'gate_fixture',
            arguments: {'action': 'delete', 'planId': 'plan-1'},
          ),
        ],
        approveTool: (_, __, ___) async => ToolApproval.reject,
      );
      expect(tool.rejections, 1);
      expect(tool.authorizations, 0);
      expect(tool.executions, 0);
      expect(capture.results.single.result.code, ToolCodes.approvalRejected);
    });

    test('authorization failure after approval maps to INVALID_ARGUMENTS',
        () async {
      final tool = _GateTool(failAuthorization: true);
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(
            id: 'a3',
            name: 'gate_fixture',
            arguments: {'action': 'delete', 'planId': 'plan-1'},
          ),
        ],
        approveTool: (_, __, ___) async => ToolApproval.allowOnce,
      );
      expect(tool.executions, 0);
      expect(capture.results.single.result.code, ToolCodes.invalidArguments);
      expect(capture.results.single.result.message, 'preview expired');
    });

    test('approveTool runs only after the consumer handled the approval event',
        () async {
      // 消费方在收到审批事件时可能先 await 落库（例如任务状态改为等待审批），
      // 执行器必须等消费方处理完、恢复生成器后才调用 approveTool。
      final tool = _GateTool();
      var consumerHandled = false;
      var handledBeforeApproval = false;
      final executor = AgentExecutor(
        provider: _ScriptedProvider(const [
          ToolCall(
            id: 'a5',
            name: 'gate_fixture',
            arguments: {'action': 'delete', 'planId': 'plan-1'},
          ),
        ]),
        tools: ToolRegistry()..register(tool),
      );
      await for (final event in executor.run(
        history: userInput(),
        model: 'test',
        maxSteps: 2,
        approveTool: (_, __, ___) async {
          handledBeforeApproval = consumerHandled;
          return ToolApproval.allowOnce;
        },
      )) {
        if (event is ApprovalRequiredEvent) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          consumerHandled = true;
        }
      }
      expect(handledBeforeApproval, isTrue);
      expect(tool.executions, 1);
    });

    test('cancelling while approving stops the run before execution',
        () async {
      final tool = _GateTool();
      final token = AgentCancellationToken();
      final capture = await runWith(
        ToolRegistry()..register(tool),
        const [
          ToolCall(
            id: 'a4',
            name: 'gate_fixture',
            arguments: {'action': 'delete', 'planId': 'plan-1'},
          ),
        ],
        cancellationToken: token,
        approveTool: (_, __, ___) async {
          token.cancel();
          return ToolApproval.allowOnce;
        },
      );
      expect(tool.executions, 0);
      expect(capture.results, isEmpty);
      expect(
        capture.events.whereType<AgentStatusEvent>().last.status,
        RunStatus.cancelled,
      );
    });
  });

  group('settlement invariants', () {
    test('every call settles exactly once, in call order, after the assistant',
        () async {
      final strict = _StrictTool();
      final capture = await runWith(
        ToolRegistry()
          ..register(strict)
          ..register(CalculatorTool()),
        const [
          ToolCall(id: 'o1', name: 'missing_tool', arguments: {}),
          ToolCall(id: 'o2', name: 'calculator', arguments: {'a': 1, 'b': 2}),
          ToolCall(id: 'o3', name: 'strict', arguments: {}),
          ToolCall(id: 'o4', name: 'strict', arguments: {'value': 3}),
        ],
      );
      expect(capture.results.map((e) => e.call.id), ['o1', 'o2', 'o3', 'o4']);
      expect(
        capture.results.map((e) => e.result.code),
        [
          ToolCodes.unknownTool,
          ToolCodes.ok,
          ToolCodes.invalidArguments,
          ToolCodes.ok,
        ],
      );
      expect(strict.executions, 1);

      // 第二次模型请求里：assistant(tool_calls) 之后紧跟 4 条 tool 消息，
      // toolCallId 顺序与调用顺序一致，中间不插入其他消息。
      final followUp = capture.provider.requests[1].messages;
      final assistantIndex =
          followUp.lastIndexWhere((m) => m.toolCalls.length == 4);
      expect(assistantIndex, greaterThanOrEqualTo(0));
      final settled = followUp.sublist(assistantIndex + 1, assistantIndex + 5);
      expect(settled.every((m) => m.role == MessageRole.tool), isTrue);
      expect(settled.map((m) => m.toolCallId), ['o1', 'o2', 'o3', 'o4']);
      expect(
        followUp
            .where((m) => m.role == MessageRole.tool)
            .map((m) => m.toolCallId),
        ['o1', 'o2', 'o3', 'o4'],
      );
    });

    test('execution metadata is forwarded on the result event', () async {
      final capture = await runWith(
        ToolRegistry()..register(_MetadataTool()),
        const [ToolCall(id: 'm1', name: 'metadata_fixture', arguments: {})],
      );
      expect(capture.results.single.metadata, {'changedFiles': 2});
    });
  });
}

class _RunCapture {
  _RunCapture(this.provider);

  final _ScriptedProvider provider;
  final events = <AgentEvent>[];

  List<ToolResultEvent> get results =>
      events.whereType<ToolResultEvent>().toList();
}

/// 首次请求返回给定工具调用，之后返回纯文本结束。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.calls);

  final List<ToolCall> calls;
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(
    UnifiedRequest request, {
    CancelToken? cancelToken,
  }) async* {
    requests.add(request);
    if (requests.length == 1) {
      for (final call in calls) {
        yield ToolCallEvent(call);
      }
      yield const CompletedEvent(stopReason: StopReason.toolUse);
      return;
    }
    yield const TextDeltaEvent('done');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _StrictTool implements AgentTool {
  var executions = 0;

  @override
  final manifest = const UnifiedTool(
    name: 'strict',
    description: 'requires value',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'value': {'type': 'number'},
      },
      'required': ['value'],
    },
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    executions++;
    return ToolResult.text('ok');
  }
}

class _GateTool implements AgentTool, ToolApprovalGate {
  _GateTool({this.failAuthorization = false});

  final bool failAuthorization;
  var executions = 0;
  var authorizations = 0;
  var rejections = 0;
  Map<String, dynamic>? lastArguments;

  @override
  final manifest = const UnifiedTool(
    name: 'gate_fixture',
    description: 'action-specific approval fixture',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string'},
        'planId': {'type': 'string'},
      },
      'required': ['action', 'planId'],
    },
    risk: ToolRisk.safe,
  );

  @override
  ToolRisk riskForArguments(Map<String, dynamic> arguments) =>
      arguments['action'] == 'delete' ? ToolRisk.dangerous : ToolRisk.safe;

  @override
  bool requiresPreviewPlan(Map<String, dynamic> arguments) =>
      arguments['action'] == 'delete';

  @override
  Map<String, dynamic>? approvalDetailsFor(Map<String, dynamic> arguments) =>
      arguments['planId'] == 'plan-1'
          ? const {'target': '/tmp/report.txt', 'reversible': false}
          : null;

  @override
  Map<String, dynamic> authorizeAfterApproval(Map<String, dynamic> arguments) {
    authorizations++;
    if (failAuthorization) {
      throw const ToolApprovalAuthorizationException('preview expired');
    }
    return {...arguments, 'previewId': 'issued-after-approval'};
  }

  @override
  void rejectApproval(Map<String, dynamic> arguments) => rejections++;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    executions++;
    lastArguments = arguments;
    return ToolResult.text('executed');
  }
}

class _MetadataTool implements AgentTool, ToolExecutionMetadata {
  @override
  final manifest = const UnifiedTool(
    name: 'metadata_fixture',
    description: 'reports metadata',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Map<String, dynamic> get lastMetadata => const {'changedFiles': 2};

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.text('ok');
}
