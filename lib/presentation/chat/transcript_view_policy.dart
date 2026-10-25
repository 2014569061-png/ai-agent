/// Only this layer maps runtime state to disclosure defaults. User overrides
/// remain local to each widget; approval-required items cannot be hidden.
enum TranscriptPhase { review, working, answering, settled }

class TranscriptViewPolicy {
  const TranscriptViewPolicy(
      {required this.toolsExpanded,
      required this.planExpanded,
      required this.condensedProgress,
      this.forceToolsOpen = false,
      this.toolsCollapsible = true,
      this.reasoningExpanded = false,
      this.errorDetailsExpanded = false});
  final bool toolsExpanded;
  final bool planExpanded;
  final bool condensedProgress;
  final bool forceToolsOpen;
  final bool toolsCollapsible;
  final bool reasoningExpanded;
  final bool errorDetailsExpanded;

  static TranscriptViewPolicy get forError => modes[TranscriptPhase.settled]!;

  static const modes = <TranscriptPhase, TranscriptViewPolicy>{
    TranscriptPhase.review: TranscriptViewPolicy(
        toolsExpanded: true,
        planExpanded: true,
        condensedProgress: false,
        forceToolsOpen: true),
    TranscriptPhase.working: TranscriptViewPolicy(
        toolsExpanded: true, planExpanded: false, condensedProgress: false),
    TranscriptPhase.answering: TranscriptViewPolicy(
        toolsExpanded: true, planExpanded: false, condensedProgress: true),
    TranscriptPhase.settled: TranscriptViewPolicy(
        toolsExpanded: false, planExpanded: false, condensedProgress: false),
  };

  static TranscriptViewPolicy forTimeline(
      {required bool running,
      required bool compact,
      required int count,
      required bool needsApproval}) {
    final base = modes[needsApproval
        ? TranscriptPhase.review
        : running
            ? TranscriptPhase.working
            : TranscriptPhase.settled]!;
    final collapsible = compact || count > 8;
    return TranscriptViewPolicy(
        toolsExpanded: base.toolsExpanded || !collapsible,
        planExpanded: base.planExpanded,
        condensedProgress: base.condensedProgress,
        forceToolsOpen: base.forceToolsOpen,
        toolsCollapsible: collapsible);
  }

  static TranscriptViewPolicy forReasoning(
          {required bool streaming,
          required bool hasAnswer,
          required bool hasProgress}) =>
      modes[!streaming
          ? TranscriptPhase.settled
          : hasAnswer && hasProgress
              ? TranscriptPhase.answering
              : TranscriptPhase.working]!;

  static TranscriptViewPolicy forPlan(
          {required bool confirmed, required String status}) =>
      modes[status == 'completed' || status == 'cancelled'
          ? TranscriptPhase.settled
          : !confirmed || status == 'paused' || status == 'failed'
              ? TranscriptPhase.review
              : TranscriptPhase.working]!;
}
