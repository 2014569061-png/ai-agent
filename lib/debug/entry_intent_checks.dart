import '../infrastructure/share/deep_link_service.dart';
import '../application/speech_submission_guard.dart';
import '../presentation/navigation/assistant_entry_surface.dart';

Future<List<Map<String, dynamic>>> runEntryIntentChecks() async {
  final cases = <Map<String, dynamic>>[];
  void check(String name, bool Function() run) {
    try {
      cases.add({'name': name, 'passed': run()});
    } catch (error) {
      cases.add({
        'name': name,
        'passed': false,
        'error': error.runtimeType.toString()
      });
    }
  }

  bool fixture(bool Function(DeepLinkService) run) {
    final links = DeepLinkService.detached();
    try {
      return run(links);
    } finally {
      links.dispose();
    }
  }

  check(
      'entry_assistant_navigation_does_not_prefill_or_request_other_action',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://assistant'));
            return s.revision == 1 &&
                s.pendingPrompt == null &&
                !s.pendingNewAgent &&
                !s.pendingMemory &&
                s.drainAssistant() &&
                !s.drainAssistant() &&
                !s.hasPending;
          }));
  check(
      'entry_existing_shortcuts_preserve_empty_prompt_agent_and_memory',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://new-chat'));
            final empty = s.drainPrompt() == '' && s.drainPrompt() == null;
            s.handleUri(Uri.parse('nexus://new-agent'));
            final agent = s.drainNewAgent();
            s.handleUri(Uri.parse('nexus://memory'));
            return empty &&
                agent &&
                s.drainMemory() &&
                !s.hasPending &&
                s.revision == 3;
          }));
  check(
      'entry_rejects_unknown_host_credentials_port_fragment_path_and_parameters',
      () {
    for (final uri in [
      'https://new-chat?prompt=x',
      'nexus://evil?prompt=x',
      'nexus://user@new-chat?prompt=x',
      'nexus://new-chat:123?prompt=x',
      'nexus://new-chat/private?prompt=x',
      'nexus://new-chat?prompt=x#fragment',
      'nexus://new-chat?prompt=x&prompt=y',
      'nexus://memory?execute=1',
      'nexus://assistant?prompt=x'
    ]) {
      if (!fixture((s) {
        s.handleUri(Uri.parse(uri));
        return !s.hasPending &&
            !s.lastEventAccepted &&
            s.hasRejection &&
            s.revision == 0;
      })) {
        return false;
      }
    }
    return true;
  });
  check(
      'entry_pending_content_is_not_silently_replaced',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://new-chat?prompt=first'));
            s.handleUri(Uri.parse('nexus://memory'));
            return s.pendingPrompt == 'first' &&
                !s.pendingMemory &&
                s.hasRejection &&
                !s.lastEventAccepted &&
                s.revision == 1;
          }));
  check(
      'entry_duplicate_pending_prefill_is_idempotent_but_revokes_old_ui_revision',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://new-chat?prompt=same'));
            final old = s.revision;
            s.handleUri(Uri.parse('nexus://new-chat?prompt=same'));
            return s.revision > old &&
                s.drainPrompt() == 'same' &&
                !s.hasPending &&
                !s.hasRejection;
          }));
  check(
      'entry_prompt_boundary_16000_and_overlimit_rejection',
      () => fixture((s) {
            s.handleUri(Uri(
                scheme: 'nexus',
                host: 'new-chat',
                queryParameters: {'prompt': 'x' * 16000}));
            final accepted = s.drainPrompt()?.length == 16000;
            s.handleUri(Uri(
                scheme: 'nexus',
                host: 'new-chat',
                queryParameters: {'prompt': 'x' * 16001}));
            return accepted &&
                !s.hasPending &&
                !s.lastEventAccepted &&
                s.revision == 1;
          }));
  check(
      'entry_encoded_uri_has_independent_size_limit',
      () => fixture((s) {
            s.handleUri(
                Uri.parse('nexus://new-chat?prompt=${'%E4%B8%AD' * 3000}'));
            return !s.hasPending && s.hasRejection && s.revision == 0;
          }));
  check(
      'entry_unicode_numbers_and_dates_are_prefill_not_execution',
      () => fixture((s) {
            const text = '明天2026年10月20日，查看应用和第123条记录';
            s.handleUri(Uri(
                scheme: 'nexus',
                host: 'new-chat',
                queryParameters: {'prompt': text}));
            return s.drainPrompt() == text &&
                !s.pendingNewAgent &&
                !s.pendingMemory &&
                !s.pendingAssistant;
          }));
  check('entry_detached_streams_do_not_modify_each_other', () {
    final a = DeepLinkService.detached(), b = DeepLinkService.detached();
    try {
      a.handleUri(Uri.parse('nexus://new-chat?prompt=isolated'));
      return a.hasPending && !b.hasPending && b.revision == 0;
    } finally {
      a.dispose();
      b.dispose();
    }
  });
  check('entry_visibility_route_and_busy_gate_truth_table', () {
    for (final visible in [true, false]) {
      for (final route in [true, false]) {
        for (final busy in [true, false]) {
          if (canConsumeAssistantEntry(
                  visible: visible, currentRoute: route, busy: busy) !=
              (visible && route && !busy)) {
            return false;
          }
        }
      }
    }
    return true;
  });
  check(
      'entry_new_accepted_scene_revokes_voice_auto_send_but_rejected_uri_does_not',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://assistant'));
            final captured = s.revision;
            s.drainAssistant();
            s.handleUri(Uri.parse('nexus://new-chat?prompt=next'));
            final advanced = s.revision;
            s.handleUri(Uri.parse('nexus://invalid'));
            return advanced != captured &&
                s.revision == advanced &&
                s.pendingPrompt == 'next';
          }));
  check(
      'entry_persistent_failure_is_not_retried_per_frame',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://new-chat?prompt=retained'));
            final revision = s.revision;
            s.markConsumptionFailed(revision);
            return s.hasPending &&
                s.pendingPrompt == 'retained' &&
                !s.consumptionReady &&
                s.revision == revision;
          }));
  check(
      'entry_explicit_retry_is_bound_to_failed_revision',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://assistant'));
            final revision = s.revision;
            s.markConsumptionFailed(revision);
            final retried = s.retryPending(revision);
            final current = s.revision;
            return retried &&
                s.consumptionReady &&
                current > revision &&
                !s.retryPending(revision) &&
                s.revision == current;
          }));
  check(
      'entry_old_failure_cannot_suppress_newly_accepted_retry',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://new-chat?prompt=retained'));
            final old = s.revision;
            s.markConsumptionFailed(old);
            s.handleUri(Uri.parse('nexus://new-chat?prompt=retained'));
            s.markConsumptionFailed(old);
            return s.consumptionReady &&
                s.revision > old &&
                s.pendingPrompt == 'retained';
          }));
  bool allowed(SpeechSubmissionGuard guard, DeepLinkService links,
          {bool requested = true,
          bool empty = true,
          bool unchanged = true,
          bool attachments = true,
          bool available = true}) =>
      guard.allowsAutoSend(
          links: links,
          requested: requested,
          initiallyEmpty: empty,
          draftUnchanged: unchanged,
          attachmentsEmpty: attachments,
          contextAvailable: available);
  check('speech_submission_clean_explicit_request_can_send',
      () => fixture((s) => allowed(SpeechSubmissionGuard.capture(s), s)));
  check('speech_submission_existing_pending_entry_blocks_unchanged_revision',
      () {
    for (final host in ['new-chat', 'new-agent', 'memory', 'assistant']) {
      if (!fixture((s) {
        s.handleUri(Uri.parse('nexus://$host'));
        return !allowed(SpeechSubmissionGuard.capture(s), s);
      })) {
        return false;
      }
    }
    return true;
  });
  check(
      'speech_submission_draining_existing_entry_cannot_reauthorize_old_voice',
      () => fixture((s) {
            s.handleUri(Uri.parse('nexus://new-chat?prompt=retained'));
            final guard = SpeechSubmissionGuard.capture(s);
            s.drainPrompt();
            return !s.hasPending && !allowed(guard, s);
          }));
  check(
      'speech_submission_commit_pending_checked_even_without_revision_change',
      () => fixture((s) {
            final guard = SpeechSubmissionGuard.capture(s);
            // Legacy public pending slots can be populated without handleUri.
            s.pendingMemory = true;
            return s.revision == 0 && !allowed(guard, s);
          }));
  check(
      'speech_submission_new_entry_stays_revoked_after_consumption',
      () => fixture((s) {
            final guard = SpeechSubmissionGuard.capture(s);
            s.handleUri(Uri.parse('nexus://assistant'));
            s.drainAssistant();
            return !s.hasPending && !allowed(guard, s);
          }));
  check(
      'speech_submission_context_draft_attachment_and_opt_in_barriers',
      () => fixture((s) {
            final guard = SpeechSubmissionGuard.capture(s);
            return !allowed(guard, s, requested: false) &&
                !allowed(guard, s, empty: false) &&
                !allowed(guard, s, unchanged: false) &&
                !allowed(guard, s, attachments: false) &&
                !allowed(guard, s, available: false);
          }));
  return cases;
}
