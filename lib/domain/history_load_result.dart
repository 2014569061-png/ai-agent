/// A transient refusal/error is not the same as reaching the start of history.
enum HistoryLoadResult { loaded, exhausted, busy, stale, failed }
