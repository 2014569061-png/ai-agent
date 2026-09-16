import '../domain/models.dart';

/// Resolves the automatic reasoning preference before it reaches a provider.
///
/// Explicit user choices are preserved. Automatic mode keeps ordinary chat
/// cheap and only raises the floor for task types that normally need more
/// deliberate reasoning.
class ReasoningPolicy {
  const ReasoningPolicy._();

  static ReasoningEffort resolve({
    required String taskType,
    required ReasoningEffort configured,
    bool planMode = false,
  }) {
    if (configured != ReasoningEffort.auto) return configured;
    if (planMode) return ReasoningEffort.high;

    return switch (taskType.trim().toLowerCase()) {
      'project_analysis' ||
      'bug_fix' ||
      'code_review' ||
      'release_check' ||
      'implement_and_verify' =>
        ReasoningEffort.medium,
      'complex_debug' || 'planning' || 'math' => ReasoningEffort.high,
      _ => ReasoningEffort.low,
    };
  }
}
