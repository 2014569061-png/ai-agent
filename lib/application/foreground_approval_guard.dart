import '../domain/models.dart';

/// Identity verification is independent of persistence/redaction policy. This
/// does not escalate safe tools into approvals; it validates a requested grant.
bool requiresFreshToolAuthentication(
        ToolRisk risk, bool sensitive, String toolName) =>
    risk == ToolRisk.dangerous ||
    toolName == 'terminal' ||
    sensitive ||
    toolName.startsWith('mcp_') ||
    toolName.contains('.');

/// A foreground approval is not a reusable authentication grant. Check the
/// durable scope both before and after the OS prompt (which may background us).
Future<ToolApproval> validateForegroundToolApproval({
  required ToolApproval decision,
  required ToolRisk risk,
  required bool sensitive,
  required String toolName,
  required Future<bool> Function() authenticate,
  required bool Function() isForeground,
  Future<bool> Function()? isCurrent,
}) async {
  if (decision == ToolApproval.reject) return ToolApproval.reject;
  try {
    if (!isForeground() || (isCurrent != null && !await isCurrent())) {
      return ToolApproval.reject;
    }
    final fresh = requiresFreshToolAuthentication(risk, sensitive, toolName);
    if (fresh && !await authenticate()) return ToolApproval.reject;
    if (!isForeground() || (isCurrent != null && !await isCurrent())) {
      return ToolApproval.reject;
    }
    return fresh ? ToolApproval.allowOnce : decision;
  } catch (_) {
    // An unavailable authenticator/storage cannot prove authorization.
    return ToolApproval.reject;
  }
}
