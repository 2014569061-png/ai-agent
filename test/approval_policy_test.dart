import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/approval_policy.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  const policy = ApprovalPolicy();

  test('safe tools are always automatic', () {
    for (final mode in ApprovalMode.values) {
      expect(
        policy
            .decide(mode: mode, risk: ToolRisk.safe, trusted: false)
            .requiresUser,
        isFalse,
      );
    }
  });

  test('full access automatically allows confirmation-level tools', () {
    final decision = policy.decide(
      mode: ApprovalMode.fullAccess,
      risk: ToolRisk.requiresConfirmation,
      trusted: false,
    );
    expect(decision.requiresUser, isFalse);
    expect(decision.source, 'mode');
  });

  test('dangerous tools always require a fresh prompt', () {
    for (final mode in ApprovalMode.values) {
      expect(
        policy
            .decide(mode: mode, risk: ToolRisk.dangerous, trusted: true)
            .requiresUser,
        isTrue,
      );
    }
  });

  test('trusted confirmation-level tools bypass the prompt', () {
    final decision = policy.decide(
      mode: ApprovalMode.ask,
      risk: ToolRisk.requiresConfirmation,
      trusted: true,
    );
    expect(decision.requiresUser, isFalse);
    expect(decision.source, 'trust');
  });

  test('sensitive tools always require a prompt regardless of mode/trust', () {
    for (final mode in ApprovalMode.values) {
      for (final trusted in [true, false]) {
        for (final risk in ToolRisk.values) {
          final decision = policy.decide(
            mode: mode,
            risk: risk,
            trusted: trusted,
            sensitive: true,
          );
          expect(decision.requiresUser, isTrue,
              reason: 'mode=$mode trusted=$trusted risk=$risk');
          expect(decision.source, 'sensitive');
          expect(decision.sensitive, isTrue);
        }
      }
    }
  });

  test('sensitive flag is surfaced on auto decisions when not enforced', () {
    // 非敏感工具的自动放行 decision 默认不带 sensitive 标记。
    final auto = policy.decide(
      mode: ApprovalMode.fullAccess,
      risk: ToolRisk.requiresConfirmation,
      trusted: false,
    );
    expect(auto.requiresUser, isFalse);
    expect(auto.sensitive, isFalse);
  });
}
