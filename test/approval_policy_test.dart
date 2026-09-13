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

  test('sensitive safe tools prompt below full access, auto-run in it', () {
    // 敏感把 safe 抬高到确认级：ask/autoSafe 下逐次确认（除非有信任）。
    for (final mode in ApprovalMode.values) {
      if (mode == ApprovalMode.fullAccess) continue;
      final decision = policy.decide(
        mode: mode,
        risk: ToolRisk.safe,
        trusted: false,
        sensitive: true,
      );
      expect(decision.requiresUser, isTrue, reason: 'mode=$mode');
      expect(decision.sensitive, isTrue);
    }
    // fullAccess 是用户显式选择的信任上限，敏感 safe 工具自动放行。
    final fullAccess = policy.decide(
      mode: ApprovalMode.fullAccess,
      risk: ToolRisk.safe,
      trusted: false,
      sensitive: true,
    );
    expect(fullAccess.requiresUser, isFalse);
    expect(fullAccess.source, 'mode');
    expect(fullAccess.sensitive, isTrue);
  });

  test('sensitive confirmation-level tools follow mode/trust rules', () {
    // MCP 型工具（确认级 + 敏感）：fullAccess 自动放行，ask 下确认。
    final fullAccess = policy.decide(
      mode: ApprovalMode.fullAccess,
      risk: ToolRisk.requiresConfirmation,
      trusted: false,
      sensitive: true,
    );
    expect(fullAccess.requiresUser, isFalse);
    expect(fullAccess.source, 'mode');

    final ask = policy.decide(
      mode: ApprovalMode.ask,
      risk: ToolRisk.requiresConfirmation,
      trusted: false,
      sensitive: true,
    );
    expect(ask.requiresUser, isTrue);
    expect(ask.sensitive, isTrue);

    final trusted = policy.decide(
      mode: ApprovalMode.ask,
      risk: ToolRisk.requiresConfirmation,
      trusted: true,
      sensitive: true,
    );
    expect(trusted.requiresUser, isFalse);
    expect(trusted.source, 'trust');
  });

  test('sensitive dangerous tools still always require a fresh prompt', () {
    for (final mode in ApprovalMode.values) {
      for (final trusted in [true, false]) {
        final decision = policy.decide(
          mode: mode,
          risk: ToolRisk.dangerous,
          trusted: trusted,
          sensitive: true,
        );
        expect(decision.requiresUser, isTrue,
            reason: 'mode=$mode trusted=$trusted');
        expect(decision.sensitive, isTrue);
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
