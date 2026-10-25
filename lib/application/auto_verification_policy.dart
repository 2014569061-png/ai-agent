/// Enabling this setting authorizes project analysis/test commands at completion.
/// Builds and automatic repair are intentionally separate operations.
abstract final class AutoVerificationPolicy {
  static const preferenceKey = 'settings.tool.auto_verification';
  static const repairPreferenceKey = 'settings.tool.auto_verification_repair';

  static bool allows({
    required bool enabled,
    required bool workspaceFiles,
    required bool terminal,
    required String status,
    required bool cancelled,
    required bool planMode,
  }) =>
      enabled &&
      workspaceFiles &&
      terminal &&
      status == 'completed' &&
      !cancelled &&
      !planMode;
}
