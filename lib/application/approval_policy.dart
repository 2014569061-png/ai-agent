import '../domain/models.dart';

/// Centralizes foreground tool approval decisions.
class ApprovalPolicy {
  const ApprovalPolicy();

  ApprovalDecision decide({
    required ApprovalMode mode,
    required ToolRisk risk,
    required bool trusted,
    bool sensitive = false,
  }) {
    // 敏感操作永远需要真人确认：不因模式（fullAccess）、信任或风险等级被绕过。
    if (sensitive) {
      return const ApprovalDecision.prompt('sensitive', true);
    }
    if (risk == ToolRisk.safe) {
      return const ApprovalDecision.auto('safe');
    }
    // Dangerous operations always require a fresh confirmation.
    if (risk == ToolRisk.dangerous) {
      return const ApprovalDecision.prompt();
    }
    if (trusted) {
      return const ApprovalDecision.auto('trust');
    }
    if (mode == ApprovalMode.fullAccess) {
      return const ApprovalDecision.auto('mode');
    }
    return const ApprovalDecision.prompt();
  }
}

class ApprovalDecision {
  const ApprovalDecision.auto(this.source, {this.sensitive = false})
      : requiresUser = false;
  const ApprovalDecision.prompt([this.source = 'user', this.sensitive = false])
      : requiresUser = true;

  final bool requiresUser;
  final String source;
  final bool sensitive;
}
