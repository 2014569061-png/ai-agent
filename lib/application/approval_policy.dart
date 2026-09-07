import '../domain/models.dart';

/// Centralizes foreground tool approval decisions.
class ApprovalPolicy {
  const ApprovalPolicy();

  ApprovalDecision decide({
    required ApprovalMode mode,
    required ToolRisk risk,
    required bool trusted,
  }) {
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
  const ApprovalDecision.auto(this.source) : requiresUser = false;
  const ApprovalDecision.prompt()
      : requiresUser = true,
        source = 'user';

  final bool requiresUser;
  final String source;
}
