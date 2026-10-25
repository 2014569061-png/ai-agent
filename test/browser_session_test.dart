import 'dart:async';
import 'dart:convert';

import 'package:mobile_agent/application/browser_payload_budget.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/browser_agent_tool.dart';
import 'package:mobile_agent/application/browser_session_service.dart';
import 'package:mobile_agent/application/tool_pipeline/execution_interceptors.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_pipeline.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_run_context.dart';
import 'package:mobile_agent/domain/browser_session.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/sensitive_tool_policy.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

class _Transport implements BrowserTransport {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final calls = <String>[];
  int opened = 0;
  Map<String, dynamic> state = {'sessionId': 's1', 'mode': 'user', 'epoch': 1};
  Completer<Map<String, dynamic>>? pending;
  BrowserFailure? failure;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  int get dispatched =>
      calls.where((m) => m == 'act' || m == 'navigate').length;
  @override
  Future<Map<String, dynamic>> invoke(
      String method, Map<String, dynamic> args) async {
    calls.add(method);
    if (method == 'open') {
      state = {
        ...state,
        'sessionId': 's${++opened}',
        'mode': 'user',
        'epoch': 1
      };
      return Map.from(state);
    }
    if (method == 'close') return {'closed': true};
    if (method == 'control') {
      state = {
        ...state,
        'mode': args['mode'],
        'epoch': (state['epoch'] as int) + 1
      };
      stream.add(state);
      return Map.from(state);
    }
    if (pending != null) return pending!.future;
    if (failure != null) throw failure!;
    if (method == 'observe') {
      return {
        'snapshotId': 'snap1',
        'epoch': state['epoch'],
        'state': Map.from(state),
        'url': 'https://example.invalid',
        'nodes': [
          {'id': 'n1', 'tag': 'button', 'label': 'Apply'}
        ],
        'text': 'private website content',
        'untrustedContent': true,
      };
    }
    if (method == 'act' || method == 'navigate') {
      state = {...state, 'epoch': (state['epoch'] as int) + 1};
      stream.add(state);
    }
    return {'state': Map.from(state)};
  }
}

void main() {
  late _Transport transport;
  late BrowserSessionService service;
  late BrowserAgentTool tool;
  setUp(() async {
    transport = _Transport();
    service = BrowserSessionService(transport);
    await service.open('conversation');
    await service.control('agent');
    tool = BrowserAgentTool(service, 'conversation');
  });
  tearDown(() async {
    await service.close();
    service.dispose();
    await transport.stream.close();
  });
  const navigation = {'action': 'navigate', 'url': 'https://example.invalid'};
  Map<String, dynamic> approve(Map<String, dynamic> args) {
    expect(tool.approvalDetailsFor(args), isNotNull);
    return tool.authorizeAfterApproval(args);
  }

  Future<ToolResult> pipeline(Map<String, dynamic> args,
      Future<ToolApproval> Function(ToolCall, ToolRisk, bool) decision) {
    final registry = ToolRegistry()..register(tool);
    return ToolPipeline(defaultToolInterceptors()).run(
        ToolInvocation(
            call: ToolCall(id: 'call', name: 'browser', arguments: args),
            registration: registry.findRegistration('browser'),
            context: ToolRunContext.detached(
                approvalMode: ApprovalMode.fullAccess, approveTool: decision)),
        executeWithTimeout);
  }

  test('browser capability contract distinguishes open and closed shadow roots',
      () {
    final description = tool.manifest.description;
    expect(description, contains('支持可见开放 Shadow DOM'));
    expect(description, contains('不支持封闭 Shadow DOM'));
    expect(description, contains('32 KiB'));
    expect(description, contains('不提供续读'));
  });

  test('truncated observations expose only returned nodes for approval',
      () async {
    transport.pending = Completer<Map<String, dynamic>>();
    final pending = tool.execute({'action': 'observe'});
    transport.pending!.complete({
      'snapshotId': 'large',
      'epoch': service.epoch,
      'state': Map.from(transport.state),
      'text': List.filled(12000, '中').join(),
      'nodes': List.generate(
          120,
          (i) => {
                'id': 'n${i + 1}',
                'label': 'Link $i',
                'href':
                    'https://example.invalid/${List.filled(1000, 'x').join()}',
              }),
      'untrustedContent': true,
    });
    final result = await pending;
    expect(result.ok, isTrue);
    expect(utf8.encode(result.encode()).length,
        lessThanOrEqualTo(BrowserPayloadBudget.maxBytes));
    expect(service.observation, result.data);
    expect(result.data!['payloadTruncated'], isTrue);
    final nodes = result.data!['nodes'] as List;
    expect(nodes.length, lessThan(120));
    expect(
        tool.approvalDetailsFor({
          'action': 'click',
          'snapshotId': 'large',
          'nodeId': 'n120',
        }),
        isNull);
  });

  test('full access still asks for a fresh browser write approval', () async {
    var asked = 0;
    final result = await pipeline(navigation, (_, risk, __) async {
      asked++;
      expect(risk, ToolRisk.dangerous);
      return ToolApproval.allowOnce;
    });
    expect(result.ok, true);
    expect(result.effect, ToolEffect.applied);
    expect(asked, 1);
    expect(transport.dispatched, 1);
  });

  test('rejected approval dispatches nothing', () async {
    final result =
        await pipeline(navigation, (_, __, ___) async => ToolApproval.reject);
    expect(result.ok, false);
    expect(transport.dispatched, 0);
  });

  test('takeover while approval is pending revokes the proposed write',
      () async {
    final requested = Completer<void>();
    final decision = Completer<ToolApproval>();
    final pending = pipeline(navigation, (_, __, ___) async {
      requested.complete();
      return decision.future;
    });
    await requested.future;
    await service.control('user');
    decision.complete(ToolApproval.allowOnce);
    expect((await pending).ok, false);
    expect(transport.dispatched, 0);
  });

  test('direct calls cannot forge a ticket and a valid ticket is one-use',
      () async {
    expect((await tool.execute({...navigation, '_browserTicket': 'forged'})).ok,
        false);
    final authorized = approve(navigation);
    expect((await tool.execute(authorized)).ok, true);
    expect((await tool.execute(authorized)).ok, false);
    expect(transport.dispatched, 1);
  });

  test('changing approved parameters consumes and rejects the authorization',
      () async {
    final authorized = approve(navigation);
    expect(
        (await tool.execute({...authorized, 'url': 'https://other.invalid'}))
            .ok,
        false);
    expect((await tool.execute(authorized)).ok, false);
    expect(transport.dispatched, 0);
  });

  test('page change during approval invalidates target and cached observation',
      () async {
    expect((await tool.execute({'action': 'observe'})).ok, true);
    const click = {'action': 'click', 'snapshotId': 'snap1', 'nodeId': 'n1'};
    expect(tool.approvalDetailsFor(click), isNotNull);
    transport.state = {...transport.state, 'epoch': service.epoch + 1};
    transport.stream.add(transport.state);
    expect(service.observation, isNull);
    expect(() => tool.authorizeAfterApproval(click),
        throwsA(isA<ToolApprovalAuthorizationException>()));
    expect(transport.dispatched, 0);
  });

  test('targets not returned by observation cannot be approved', () async {
    await tool.execute({'action': 'observe'});
    expect(
        tool.approvalDetailsFor(
            {'action': 'click', 'snapshotId': 'snap1', 'nodeId': 'fake'}),
        isNull);
    expect(
        tool.approvalDetailsFor(
            {'action': 'click', 'snapshotId': 'old', 'nodeId': 'n1'}),
        isNull);
  });

  test('another conversation cannot read the session', () async {
    final other = BrowserAgentTool(service, 'other');
    final result = await other.execute({'action': 'observe'});
    expect(result.code, ToolCodes.ownerMismatch);
    expect(transport.calls.where((m) => m == 'observe'), isEmpty);
  });

  test('an old tool cannot borrow a reopened session for the same conversation',
      () async {
    await service.close();
    await service.open('conversation');
    await service.control('agent');
    expect((await tool.execute({'action': 'observe'})).code,
        ToolCodes.sessionExpired);
    expect(tool.approvalDetailsFor(navigation), isNull);
    expect(transport.calls.where((method) => method == 'observe'), isEmpty);
  });

  test('a late observation cannot resurrect a closed session', () async {
    transport.pending = Completer<Map<String, dynamic>>();
    final pending = tool.execute({'action': 'observe'});
    await Future<void>.delayed(Duration.zero);
    await service.close();
    transport.pending!.complete({'snapshotId': 'late', 'epoch': 2});
    expect((await pending).code, ToolCodes.sessionExpired);
    expect(service.sessionId, isNull);
    expect(service.observation, isNull);
  });

  test('uncertain native outcomes retain unknown effect and cannot replay',
      () async {
    final authorized = approve(navigation);
    transport.failure =
        const BrowserFailure(ToolCodes.timeout, dispatched: true);
    final result = await tool.execute(authorized);
    expect(result.effect, ToolEffect.unknown);
    expect((await tool.execute(authorized)).effect, ToolEffect.none);
    expect(transport.dispatched, 1);
  });

  test('browser content and typed fields are redacted at persistence exits',
      () {
    expect(SensitiveToolPolicy.redactArguments('browser', {'text': 'PRIVATE'}),
        {'redacted': true});
    final result = SensitiveToolPolicy.redactResult(
        'browser',
        ToolResult.success(
            data: {'text': 'PRIVATE'}, effect: ToolEffect.applied));
    expect(result.encode(), isNot(contains('PRIVATE')));
    expect(result.effect, ToolEffect.applied);
  });

  for (final url in [
    'javascript:alert(1)',
    'file:///etc/passwd',
    'content://media',
    'intent://open',
    'https://user:password@example.com',
    'https://example.com/ bad',
    'https://example.com\\@other.com',
    'data:text/html,test'
  ]) {
    test('URL policy rejects $url', () {
      expect(() => browserUrl(url), throwsA(isA<BrowserFailure>()));
    });
  }
}
