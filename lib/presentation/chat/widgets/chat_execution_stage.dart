/// Structured execution stages shared by the chat input and top bar.
///
/// User-facing copy stays separate from the stage so a wording change cannot
/// silently break status rendering.
enum ChatExecutionStage {
  waitingForUser,
  preparing,
  running,
  succeeded,
  failed,
  cancelled,
}
