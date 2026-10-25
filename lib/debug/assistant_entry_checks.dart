import 'dart:async';
import 'package:flutter/services.dart';
import '../application/assistant_entry_delivery.dart';
import '../application/speech_submission_guard.dart';
import '../domain/assistant_input_decision.dart';
import '../domain/assistant_page_context.dart';
import '../infrastructure/share/deep_link_service.dart';
import '../infrastructure/notifications/notification_intent.dart';
import '../infrastructure/share/share_batch_intake.dart';

Future<List<Map<String, dynamic>>> runAssistantEntryChecks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(
      String name, FutureOr<bool> Function(DeepLinkService) run) async {
    final entries = DeepLinkService.detached();
    try {
      cases.add({'name': name, 'passed': await run(entries)});
    } catch (error) {
      cases.add({
        'name': name,
        'passed': false,
        'error': error.runtimeType.toString()
      });
    } finally {
      entries.dispose();
    }
  }

  AssistantPageContext page(
          {String id = 'fixture-context', DateTime? expires}) =>
      AssistantPageContext(
          id: id,
          sourcePackage: 'com.example.fixture',
          sourceLabel: 'Fixture',
          text: 'synthetic page text',
          capturedAt: DateTime.now(),
          expiresAt: expires ?? DateTime.now().add(const Duration(minutes: 2)));
  Future<AssistantEntryOutcome> deliver(
    DeepLinkService s, {
    bool Function()? visible,
    bool Function()? unchanged,
    Future<AssistantInputDecision?> Function()? review,
    Future<bool> Function()? role,
    void Function(String)? stage,
    Future<void> Function(NotificationIntent)? navigate,
    DateTime Function()? now,
  }) =>
      const AssistantEntryDelivery().deliver(s, s.pendingExternal!,
          canPresent: visible ?? () => true,
          contextUnchanged: unchanged ?? () => true,
          review:
              review ?? () async => const AssistantInputDecision.use('edited'),
          pageContextAllowed: role ?? () async => true,
          stage: stage ?? (_) {},
          navigate: navigate ?? (_) async {},
          now: now);

  await check('external_running_gate_only_allows_pure_navigation_and_approval',
      (s) {
    s.handleUri(Uri.parse('nexus://assistant'));
    final navigation = !AssistantEntryDelivery.requiresIdle(s);
    s.drainAssistant();
    s.enqueueNotification(const NotificationIntent(
        NotificationIntentKind.approval, 'fixture-approval'));
    final approval = !AssistantEntryDelivery.requiresIdle(s);
    s.enqueueShare(['later draft']);
    s.acknowledgeExternal(s.pendingExternal!.id);
    final draftBlocked = AssistantEntryDelivery.requiresIdle(s);
    s.acknowledgeExternal(s.pendingExternal!.id);
    s.handleUri(Uri.parse('nexus://new-chat?prompt=blocked'));
    return navigation &&
        approval &&
        draftBlocked &&
        AssistantEntryDelivery.requiresIdle(s);
  });
  await check('external_share_batches_are_immutable_and_not_flattened', (s) {
    final input = ['first', 'second'];
    s.enqueueShare(input);
    input[0] = 'replaced';
    s.enqueueShare(['third']);
    final first = s.pendingExternal!;
    final immutable = first.shared.join(',') == 'first,second';
    s.acknowledgeExternal(first.id);
    return immutable &&
        s.externalCount == 1 &&
        s.pendingExternal!.shared.single == 'third';
  });
  await check(
      'external_duplicate_notification_deduplicates_without_replacing_share',
      (s) {
    s.enqueueShare(['preserved']);
    const intent =
        NotificationIntent(NotificationIntentKind.task, 'fixture-task');
    s.enqueueNotification(intent);
    s.enqueueNotification(intent);
    return s.externalCount == 2 &&
        s.pendingExternal!.shared.single == 'preserved';
  });
  await check('external_full_queue_rejects_without_eviction', (s) {
    for (var i = 0; i < DeepLinkService.maxExternalEntries; i++) {
      s.enqueueShare(['batch-$i']);
    }
    final first = s.pendingExternal!.id;
    return !s.enqueueShare(['overflow']) &&
        s.externalCount == 8 &&
        s.pendingExternal!.id == first &&
        s.hasRejection;
  });
  await check('external_payload_bounds_and_nexus_share_filter', (s) {
    return !s.enqueueShare(['nexus://new-chat?prompt=not_share']) &&
        !s.enqueueShare(['x' * 16001]) &&
        !s.enqueueShare(['x' * 8000, 'y' * 8000]) &&
        !s.hasPending &&
        NotificationIntent.parse('task:${'x' * 257}') == null &&
        NotificationIntent.parse('task:space id') == null;
  });
  await check('external_arrival_and_ack_revoke_old_voice_submission', (s) {
    final guard = SpeechSubmissionGuard.capture(s);
    s.enqueueShare(['new input']);
    s.acknowledgeExternal(s.pendingExternal!.id);
    return !s.hasPending &&
        !guard.allowsAutoSend(
            links: s,
            requested: true,
            initiallyEmpty: true,
            draftUnchanged: true,
            attachmentsEmpty: true,
            contextAvailable: true);
  });
  await check('external_arrival_does_not_retry_failed_legacy_entry', (s) {
    s.handleUri(Uri.parse('nexus://new-chat?prompt=retained'));
    s.markConsumptionFailed(s.revision);
    s.enqueueShare(['later']);
    return !s.consumptionReady &&
        s.pendingPrompt == 'retained' &&
        s.externalCount == 1;
  });
  await check('external_failure_retry_is_bound_to_entry_identity', (s) {
    s.enqueueShare(['first']);
    final id = s.pendingExternal!.id;
    s.markExternalFailed(id);
    s.enqueueShare(['second']);
    final blocked = !s.consumptionReady && !s.retryExternal('obsolete');
    return blocked &&
        s.retryExternal(id) &&
        s.consumptionReady &&
        !s.retryExternal(id);
  });
  await check(
      'external_claim_is_exclusive_and_old_release_cannot_clear_new_owner',
      (s) {
    s.enqueueShare(['first']);
    final id = s.pendingExternal!.id;
    final a = Object(), b = Object();
    final first = s.claimExternal(id, a) && !s.claimExternal(id, b);
    s.releaseExternal(b);
    final retained = s.ownsExternal(id, a);
    s.releaseExternal(a);
    s.claimExternal(id, b);
    s.releaseExternal(a);
    return first && retained && s.ownsExternal(id, b);
  });
  await check('external_context_duplicate_cannot_extend_expiry', (s) {
    final first = page();
    s.enqueuePageContext(first);
    s.enqueuePageContext(
        page(expires: first.expiresAt.add(const Duration(minutes: 2))));
    return s.externalCount == 1 &&
        identical(s.pendingExternal!.pageContext, first);
  });
  await check(
      'external_context_payload_parser_rejects_invalid_source_size_and_ttl',
      (s) {
    final base = <Object?, Object?>{
      'version': 1,
      'id': 'fixture-id',
      'sourcePackage': 'com.example.fixture',
      'sourceLabel': 'Fixture',
      'text': 'safe literal',
      'capturedAtMillis': DateTime.now().millisecondsSinceEpoch,
      'remainingMs': 60000
    };
    final invalid = <Map<Object?, Object?>>[
      {...base, 'version': 2},
      {...base, 'id': 'bad id'},
      {...base, 'sourcePackage': 'invalid'},
      {...base, 'sourceLabel': 'bad\nlabel'},
      {...base, 'text': 'x' * 8001},
      {...base, 'remainingMs': 0},
      {...base, 'remainingMs': 120001},
      {...base, 'remainingMs': '1000'}
    ];
    for (final value in invalid) {
      try {
        AssistantPageContext.fromMap(value);
        return false;
      } on FormatException {/* expected */}
    }
    return AssistantPageContext.fromMap(base).text == 'safe literal';
  });
  await check('external_context_expiry_removes_only_context_and_releases_claim',
      (s) {
    final context = page();
    s.enqueuePageContext(context);
    s.enqueueShare(['preserved']);
    final owner = Object();
    s.claimExternal(s.pendingExternal!.id, owner);
    s.discardExpiredContexts(context.expiresAt);
    return s.externalCount == 1 &&
        s.pendingExternal!.shared.single == 'preserved' &&
        s.claimExternal(s.pendingExternal!.id, Object());
  });
  await check(
      'external_context_draft_retains_source_and_rejects_expired_content', (s) {
    final context = page();
    final draft = context.draftText('user edited');
    var refused = false;
    try {
      context.draftText('old', now: context.expiresAt);
    } on FormatException {
      refused = true;
    }
    return refused &&
        draft.contains('com.example.fixture') &&
        draft.endsWith('user edited');
  });
  await check('external_delivery_requires_review_then_acknowledges_once',
      (s) async {
    s.enqueueShare(['incoming']);
    var reviews = 0, stages = 0;
    final result = await deliver(s, review: () async {
      reviews++;
      return const AssistantInputDecision.use('edited');
    }, stage: (text) {
      if (text == 'edited') stages++;
    });
    return result == AssistantEntryOutcome.staged &&
        reviews == 1 &&
        stages == 1 &&
        !s.hasPending;
  });
  await check('external_delivery_dismissal_pauses_without_per_frame_retry',
      (s) async {
    s.enqueueShare(['incoming']);
    var reviews = 0;
    final first = await deliver(s, review: () async {
      reviews++;
      return null;
    });
    final second = await deliver(s, review: () async {
      reviews++;
      return null;
    });
    return first == AssistantEntryOutcome.deferred &&
        second == AssistantEntryOutcome.waiting &&
        reviews == 1 &&
        s.hasPending &&
        !s.consumptionReady;
  });
  await check('external_delivery_concurrent_consumers_open_one_review',
      (s) async {
    s.enqueueShare(['incoming']);
    final receipt = Completer<AssistantInputDecision?>();
    var reviews = 0, stages = 0;
    final first = deliver(s,
        review: () {
          reviews++;
          return receipt.future;
        },
        stage: (_) => stages++);
    final second = await deliver(s, review: () async {
      reviews++;
      return null;
    });
    receipt.complete(const AssistantInputDecision.use('edited'));
    await first;
    return second == AssistantEntryOutcome.waiting &&
        reviews == 1 &&
        stages == 1;
  });
  await check('external_delivery_hidden_during_review_never_stages', (s) async {
    s.enqueueShare(['incoming']);
    var visible = true, stages = 0;
    final result = await deliver(s,
        visible: () => visible,
        review: () async {
          visible = false;
          return const AssistantInputDecision.use('edited');
        },
        stage: (_) => stages++);
    return result == AssistantEntryOutcome.deferred &&
        stages == 0 &&
        s.hasPending;
  });
  await check('external_delivery_changed_owner_or_draft_preserves_new_context',
      (s) async {
    s.enqueueShare(['incoming']);
    var unchanged = true, stages = 0;
    final result = await deliver(s,
        unchanged: () => unchanged,
        review: () async {
          unchanged = false;
          return const AssistantInputDecision.use('edited');
        },
        stage: (_) => stages++);
    return result == AssistantEntryOutcome.deferred &&
        stages == 0 &&
        s.hasPending;
  });
  await check('external_delivery_role_revoked_after_review_discards_context',
      (s) async {
    s.enqueuePageContext(page());
    var probes = 0, stages = 0;
    final result = await deliver(s,
        role: () async => ++probes == 1, stage: (_) => stages++);
    return result == AssistantEntryOutcome.expired &&
        probes == 2 &&
        stages == 0 &&
        !s.hasPending;
  });
  await check('external_delivery_context_expired_during_review_is_not_staged',
      (s) async {
    final context = page();
    s.enqueuePageContext(context);
    var now = context.capturedAt, stages = 0;
    final result = await deliver(s,
        now: () => now,
        review: () async {
          now = context.expiresAt;
          return const AssistantInputDecision.use('edited');
        },
        stage: (_) => stages++);
    return result == AssistantEntryOutcome.expired &&
        stages == 0 &&
        !s.hasPending;
  });
  await check('external_delivery_old_confirmation_cannot_ack_next_entry',
      (s) async {
    s.enqueueShare(['old']);
    var stages = 0;
    final old = s.pendingExternal!.id;
    final result = await deliver(s,
        review: () async {
          s.acknowledgeExternal(old);
          s.enqueueShare(['new']);
          return const AssistantInputDecision.use('obsolete');
        },
        stage: (_) => stages++);
    return result == AssistantEntryOutcome.deferred &&
        stages == 0 &&
        s.pendingExternal!.shared.single == 'new';
  });
  await check('external_notification_lookup_failure_keeps_exact_entry',
      (s) async {
    s.enqueueNotification(const NotificationIntent(
        NotificationIntentKind.conversation, 'fixture'));
    final id = s.pendingExternal!.id;
    var stages = 0, rejected = false;
    try {
      await deliver(s,
          navigate: (_) async => throw StateError('fixture lookup unavailable'),
          stage: (_) => stages++);
    } on StateError {
      rejected = true;
    }
    return rejected &&
        stages == 0 &&
        s.pendingExternal!.id == id &&
        !s.consumptionReady;
  });
  await check('external_wrong_ack_does_not_remove_pending_entry', (s) {
    s.enqueueShare(['preserved']);
    return !s.acknowledgeExternal('wrong') && s.hasPending;
  });
  await check('external_assistant_navigation_preserves_staged_input', (s) {
    s.enqueueShare(['preserved']);
    final id = s.pendingExternal!.id, version = s.revision;
    s.handleUri(Uri.parse('nexus://assistant'));
    return s.pendingExternal!.id == id &&
        s.externalCount == 1 &&
        !s.pendingAssistant &&
        !s.hasRejection &&
        s.revision > version;
  });
  await check(
      'external_context_native_read_filter_excludes_inputs_blocked_and_hidden_nodes',
      (s) async {
    final raw = await const MethodChannel('nexus/assistant_role')
        .invokeMapMethod<String, Object?>('debugTextFilterCheck');
    return raw != null &&
        raw.length == 5 &&
        raw.values.every((value) => value == true);
  });
  await check('share_batch_slow_conversion_preserves_arrival_order', (s) async {
    final first = Completer<List<String>>(), seen = <String>[];
    final intake = ShareBatchIntake(
        onBatch: (values) => seen.add(values.single), onFailure: () {});
    final a = intake.append(() => first.future);
    final b = intake.append(() async => ['second']);
    final before = seen.isEmpty;
    first.complete(['first']);
    await Future.wait([a, b]);
    return before && seen.join(',') == 'first,second';
  });
  await check('share_batch_failed_conversion_releases_next_batch', (s) async {
    var failures = 0;
    final seen = <String>[];
    final intake =
        ShareBatchIntake(onBatch: seen.addAll, onFailure: () => failures++);
    await intake.append(() async => throw StateError('fixture read failure'));
    await intake.append(() async => ['retained']);
    return failures == 1 && seen.single == 'retained';
  });
  await check('share_batch_conversion_queue_is_bounded_without_eviction',
      (s) async {
    final first = Completer<List<String>>();
    var failures = 0;
    final seen = <String>[];
    final intake = ShareBatchIntake(
        capacity: 2, onBatch: seen.addAll, onFailure: () => failures++);
    final a = intake.append(() => first.future),
        b = intake.append(() async => ['second']);
    await intake.append(() async => ['overflow']);
    first.complete(['first']);
    await Future.wait([a, b]);
    return failures == 1 && seen.join(',') == 'first,second';
  });
  await check('share_batch_cold_and_warm_batches_keep_separate_boundaries',
      (s) async {
    final intake = ShareBatchIntake(onBatch: s.enqueueShare, onFailure: () {});
    await intake.append(() async => ['image text one', 'image text two']);
    await intake.append(() async => ['warm share']);
    final head = s.pendingExternal!;
    return s.externalCount == 2 && head.shared.length == 2;
  });
  await check('external_arrival_preserves_identity_of_legacy_retry_button',
      (s) {
    s.handleUri(Uri.parse('nexus://new-chat?prompt=retained'));
    final failed = s.legacyRevision;
    s.markConsumptionFailed(failed);
    s.enqueueShare(['later share']);
    return !s.consumptionReady &&
        s.retryPending(failed) &&
        s.consumptionReady &&
        s.pendingPrompt == 'retained' &&
        s.externalCount == 1;
  });
  await check('external_context_monotonic_expiry_survives_wall_clock_rollback',
      (s) {
    var ticks = 0;
    final context = AssistantPageContext(
        id: 'clock-fixture',
        sourcePackage: 'com.example.fixture',
        sourceLabel: 'Fixture',
        text: 'literal',
        capturedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        monotonicMicros: () => ticks);
    s.enqueuePageContext(context);
    ticks = 121000000;
    s.discardExpiredContexts(DateTime(2000));
    return context.isExpired(DateTime(2000)) && !s.hasPending;
  });
  return cases;
}
