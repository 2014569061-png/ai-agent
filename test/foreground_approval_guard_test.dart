import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/foreground_approval_guard.dart';
import 'package:mobile_agent/domain/approval_action_codec.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  test('background accepts denial only, including legacy notification actions',
      () {
    for (final value in <String?>[
      null,
      '',
      'approve:old-request',
      'review:request',
      'approve:',
      'unknown:x'
    ]) {
      expect(parseBackgroundApprovalActionId(value), isNull);
    }
    final deny = parseBackgroundApprovalActionId('deny:request:1');
    expect(deny?.requestId, 'request:1');
    expect(deny?.approve, isFalse);
  });

  test('read-only approvals do not require fresh authentication', () async {
    var calls = 0;
    final decision = await validateForegroundToolApproval(
      decision: ToolApproval.allowOnce,
      risk: ToolRisk.safe,
      sensitive: false,
      toolName: 'read_file',
      authenticate: () async {
        calls++;
        return true;
      },
      isForeground: () => true,
    );
    expect(decision, ToolApproval.allowOnce);
    expect(calls, 0);
  });

  for (final scenario in [
    (ToolRisk.requiresConfirmation, false, 'terminal'),
    (ToolRisk.dangerous, false, 'terminal'),
    (ToolRisk.safe, true, 'personal_data'),
    (ToolRisk.requiresConfirmation, false, 'mcp_remote'),
    (ToolRisk.safe, false, 'server.tool'),
  ]) {
    test('fresh identity and one-time grant for $scenario', () async {
      var calls = 0;
      final decision = await validateForegroundToolApproval(
        decision: ToolApproval.allowAlways,
        risk: scenario.$1,
        sensitive: scenario.$2,
        toolName: scenario.$3,
        authenticate: () async {
          calls++;
          return true;
        },
        isForeground: () => true,
      );
      expect(calls, 1);
      expect(decision, ToolApproval.allowOnce);
    });
  }

  test('failed, cancelled or unavailable authenticator fails closed', () async {
    for (final auth in <Future<bool> Function()>[
      () async => false,
      () async => throw StateError('unavailable'),
    ]) {
      expect(
          await validateForegroundToolApproval(
            decision: ToolApproval.allowOnce,
            risk: ToolRisk.dangerous,
            sensitive: false,
            toolName: 'terminal',
            authenticate: auth,
            isForeground: () => true,
          ),
          ToolApproval.reject);
    }
  });

  test('background grants rejected before authenticating', () async {
    var calls = 0;
    expect(
        await validateForegroundToolApproval(
          decision: ToolApproval.allowOnce,
          risk: ToolRisk.dangerous,
          sensitive: false,
          toolName: 'terminal',
          authenticate: () async {
            calls++;
            return true;
          },
          isForeground: () => false,
        ),
        ToolApproval.reject);
    expect(calls, 0);
  });

  test('denial never opens an OS authentication prompt', () async {
    expect(
        await validateForegroundToolApproval(
          decision: ToolApproval.reject,
          risk: ToolRisk.dangerous,
          sensitive: true,
          toolName: 'terminal',
          authenticate: () async => throw StateError('must not authenticate'),
          isForeground: () => true,
        ),
        ToolApproval.reject);
  });

  test('plan changed while authenticating cannot reuse approval', () async {
    final auth = Completer<bool>();
    var current = true;
    final result = validateForegroundToolApproval(
      decision: ToolApproval.allowOnce,
      risk: ToolRisk.dangerous,
      sensitive: false,
      toolName: 'terminal',
      authenticate: () => auth.future,
      isForeground: () => true,
      isCurrent: () async => current,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    auth.complete(true);
    expect(await result, ToolApproval.reject);
  });

  test('leaving foreground during authentication invalidates approval',
      () async {
    var foreground = true;
    expect(
        await validateForegroundToolApproval(
          decision: ToolApproval.allowOnce,
          risk: ToolRisk.dangerous,
          sensitive: false,
          toolName: 'terminal',
          authenticate: () async {
            foreground = false;
            return true;
          },
          isForeground: () => foreground,
        ),
        ToolApproval.reject);
  });
}
