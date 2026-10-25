import '../domain/assistant_input_decision.dart';
import '../infrastructure/share/assistant_entry.dart';
import '../infrastructure/share/deep_link_service.dart';
import '../infrastructure/notifications/notification_intent.dart';

enum AssistantEntryOutcome {
  waiting,
  deferred,
  discarded,
  expired,
  staged,
  navigated
}

/// Coordinates navigation/draft delivery only. It cannot send a message or run
/// a tool. Ports use the existing chat controller, review sheet and navigator.
class AssistantEntryDelivery {
  const AssistantEntryDelivery();

  /// These two entries only expose the current assistant/approval surface.
  /// Requiring a run to finish first would strand navigation to its approval.
  static bool requiresIdle(DeepLinkService entries) {
    final assistantNavigation = entries.pendingAssistant &&
        entries.pendingPrompt == null &&
        !entries.pendingMemory &&
        !entries.pendingNewAgent;
    final approval = !entries.hasLegacyPending &&
        entries.pendingExternal?.notification?.kind ==
            NotificationIntentKind.approval;
    return !assistantNavigation && !approval;
  }

  Future<AssistantEntryOutcome> deliver(
    DeepLinkService entries,
    AssistantEntry entry, {
    required bool Function() canPresent,
    required bool Function() contextUnchanged,
    required Future<AssistantInputDecision?> Function() review,
    required Future<bool> Function() pageContextAllowed,
    required Future<void> Function(NotificationIntent) navigate,
    required void Function(String text) stage,
    DateTime Function()? now,
  }) async {
    final owner = Object();
    if (!canPresent() || !entries.claimExternal(entry.id, owner)) {
      return AssistantEntryOutcome.waiting;
    }
    try {
      if (entry.notification != null) {
        await navigate(entry.notification!);
        if (entries.ownsExternal(entry.id, owner)) {
          entries.acknowledgeExternal(entry.id);
        }
        return AssistantEntryOutcome.navigated;
      }
      final page = entry.pageContext;
      if (page != null &&
          (page.isExpired(now?.call()) || !await pageContextAllowed())) {
        entries.acknowledgeExternal(entry.id);
        return AssistantEntryOutcome.expired;
      }
      if (!canPresent() ||
          !contextUnchanged() ||
          !entries.ownsExternal(entry.id, owner)) {
        return AssistantEntryOutcome.waiting;
      }
      final decision = await review();
      if (decision?.discard == true) {
        if (entries.ownsExternal(entry.id, owner)) {
          entries.acknowledgeExternal(entry.id);
        }
        return AssistantEntryOutcome.discarded;
      }
      if (decision == null) {
        entries.markExternalFailed(entry.id);
        return AssistantEntryOutcome.deferred;
      }
      if (decision.text.length > (page == null ? 16000 : 8000)) {
        entries.markExternalFailed(entry.id);
        return AssistantEntryOutcome.deferred;
      }
      if (page != null &&
          (page.isExpired(now?.call()) || !await pageContextAllowed())) {
        if (entries.ownsExternal(entry.id, owner)) {
          entries.acknowledgeExternal(entry.id);
        }
        return AssistantEntryOutcome.expired;
      }
      if (!canPresent() ||
          !contextUnchanged() ||
          !entries.ownsExternal(entry.id, owner)) {
        entries.markExternalFailed(entry.id);
        return AssistantEntryOutcome.deferred;
      }
      stage(page?.draftText(decision.text, now: now?.call()) ?? decision.text);
      entries.acknowledgeExternal(entry.id);
      return AssistantEntryOutcome.staged;
    } catch (_) {
      entries.markExternalFailed(entry.id);
      rethrow;
    } finally {
      entries.releaseExternal(owner);
    }
  }
}
