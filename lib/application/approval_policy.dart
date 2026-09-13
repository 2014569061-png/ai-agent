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
    // Dangerous operations always require a fresh confirmation.
    if (risk == ToolRisk.dangerous) {
      return ApprovalDecision.prompt(
        sensitive ? 'sensitive' : 'user',
        sensitive,
      );
    }
    // 敏感工具把 safe 抬高到确认级：未开完全访问时至少逐次确认，
    // 但不再无条件覆盖 fullAccess——完全访问是用户显式选择的信任上限，
    // 覆盖它会造成“选了完全访问仍每次弹审批”的 UX 回归。
    // 危险级不受此影响，任何模式下都保持逐次确认。
    final effectiveRisk = sensitive && risk == ToolRisk.safe
        ? ToolRisk.requiresConfirmation
        : risk;
    if (effectiveRisk == ToolRisk.safe) {
      return const ApprovalDecision.auto('safe');
    }
    if (trusted) {
      return ApprovalDecision.auto('trust', sensitive: sensitive);
    }
    if (mode == ApprovalMode.fullAccess) {
      return ApprovalDecision.auto('mode', sensitive: sensitive);
    }
    return ApprovalDecision.prompt(
      sensitive ? 'sensitive' : 'user',
      sensitive,
    );
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
