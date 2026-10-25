import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import '../application/run_controller.dart';
import '../application/agent_executor.dart' show AgentEvent, AgentStatusEvent;
import '../application/tool_pipeline/execution_interceptors.dart';
import '../application/tool_pipeline/tool_invocation.dart';
import '../application/tool_pipeline/tool_pipeline.dart';
import '../application/tool_pipeline/tool_run_context.dart';
import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/tools/tool_registry.dart';

bool _registered = false;
void registerSteeringGuardChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.steeringGuardContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
}

class _Gate implements ToolExecutor, ToolApprovalGate {
  int executions = 0, authorizations = 0, rejections = 0;
  void Function()? onExecute;
  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    executions++;
    onExecute?.call();
    return ToolResult.success(
        message: 'Synthetic fixture counter only', effect: ToolEffect.applied);
  }

  @override
  ToolRisk riskForArguments(Map<String, dynamic> arguments) =>
      ToolRisk.requiresConfirmation;
  @override
  bool requiresPreviewPlan(Map<String, dynamic> arguments) => true;
  @override
  Map<String, dynamic>? approvalDetailsFor(Map<String, dynamic> arguments) =>
      {'fixtureOnly': true};
  @override
  Map<String, dynamic> authorizeAfterApproval(Map<String, dynamic> arguments) {
    authorizations++;
    return {...arguments, 'fixtureTicket': true};
  }

  @override
  void rejectApproval(Map<String, dynamic> arguments) {
    rejections++;
  }
}

Future<ToolResult> _invoke(AgentRunController controller, _Gate gate,
    {required int revision,
    Future<ToolApproval> Function()? approve,
    Future<void> Function()? wait,
    Future<void> Function(AgentEvent)? emit}) {
  final registration = ToolRegistration(
      spec: const ToolSpec(
          name: 'fixture_gate',
          description: 'Isolated counter, no platform actions',
          parametersSchema: {'type': 'object'},
          risk: ToolRisk.requiresConfirmation,
          sensitive: true),
      executor: gate);
  return ToolPipeline(defaultToolInterceptors()).run(
      ToolInvocation(
          call: const ToolCall(
              id: 'fixture-call', name: 'fixture_gate', arguments: {}),
          registration: registration,
          context: ToolRunContext(
              approvalMode: ApprovalMode.ask,
              emit: emit ?? (_) async {},
              approveTool: (call, risk, sensitive) async =>
                  approve == null ? ToolApproval.allowOnce : await approve(),
              isSuperseded: () => controller.controlRevision != revision,
              isCancelled: () => controller.isCancelled,
              isPaused: () => controller.isPaused,
              waitForResume: wait ?? controller.checkpoint)),
      executeWithTimeout);
}

Future<Map<String, dynamic>> _checks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  bool blocked(ToolResult r, _Gate g) =>
      r.code == ToolCodes.revisionConflict &&
      r.effect == ToolEffect.none &&
      g.executions == 0 &&
      g.authorizations == 0;
  await check('local_revision_starts_zero',
      () async => AgentRunController().controlRevision == 0);
  await check('accepted_correction_advances_revision', () async {
    final c = AgentRunController();
    return c.steer('new scope') && c.controlRevision == 1;
  });
  await check('empty_correction_has_no_generation', () async {
    final c = AgentRunController();
    return !c.steer('  ') && c.controlRevision == 0;
  });
  await check('sealed_run_cannot_accept_new_correction', () async {
    final c = AgentRunController()..seal();
    return !c.steer('late') && c.controlRevision == 0;
  });
  await check('cancelled_run_cannot_accept_new_correction', () async {
    final c = AgentRunController()..cancel();
    return !c.steer('late') && c.controlRevision == 0;
  });
  await check('stale_batch_skips_approval_and_execution', () async {
    final c = AgentRunController();
    final g = _Gate();
    final rev = c.controlRevision;
    var approvals = 0;
    c.steer('different object');
    final r = await _invoke(c, g, revision: rev, approve: () async {
      approvals++;
      return ToolApproval.allowOnce;
    });
    return blocked(r, g) && approvals == 0 && g.rejections == 1;
  });
  await check('correction_while_approval_pending_invalidates_old_allow',
      () async {
    final c = AgentRunController();
    final g = _Gate();
    final rev = c.controlRevision;
    final r = await _invoke(c, g, revision: rev, approve: () async {
      c.steer('new recipient');
      return ToolApproval.allowOnce;
    });
    return blocked(r, g) && g.rejections == 1;
  });
  await check('correction_during_pause_invalidates_old_tool_after_resume',
      () async {
    final c = AgentRunController()..pause();
    final g = _Gate();
    final rev = c.controlRevision;
    final r = await _invoke(c, g, revision: rev, wait: () async {
      c.steer('new time range');
      c.resume();
    });
    return blocked(r, g);
  });
  await check('correction_during_event_backpressure_still_blocks_authorization',
      () async {
    final c = AgentRunController();
    final g = _Gate();
    final rev = c.controlRevision;
    final r = await _invoke(c, g, revision: rev, emit: (event) async {
      if (event is AgentStatusEvent &&
          event.status == RunStatus.executingTool) {
        c.steer('different destination');
      }
    });
    return blocked(r, g);
  });
  await check('already_dispatched_effect_is_not_claimed_undone', () async {
    final c = AgentRunController();
    final g = _Gate()..onExecute = () => c.steer('arrives after dispatch');
    final r = await _invoke(c, g, revision: c.controlRevision);
    return r.ok &&
        r.effect == ToolEffect.applied &&
        g.executions == 1 &&
        g.rejections == 0;
  });
  await check('remaining_old_batch_calls_do_not_execute', () async {
    final c = AgentRunController();
    final g = _Gate();
    final rev = c.controlRevision;
    final first = await _invoke(c, g, revision: rev);
    c.steer('replace rest');
    final second = await _invoke(c, g, revision: rev);
    return first.ok &&
        second.code == ToolCodes.revisionConflict &&
        g.executions == 1 &&
        g.authorizations == 1;
  });
  await check('fresh_turn_requires_new_approval_and_can_execute', () async {
    final c = AgentRunController()..steer('fresh plan');
    final g = _Gate();
    var approvals = 0;
    final r =
        await _invoke(c, g, revision: c.controlRevision, approve: () async {
      approvals++;
      return ToolApproval.allowOnce;
    });
    return r.ok && approvals == 1 && g.executions == 1 && g.authorizations == 1;
  });
  return {
    'type': 'SteeringGuardContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((c) => c['passed'] == true).length,
    'total': cases.length
  };
}
