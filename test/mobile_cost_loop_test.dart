import 'dart:io';
import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/agent_loop/token_budget.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/cost_budget_ledger.dart';
import 'package:mobile_agent/infrastructure/providers/cost_budget_policy.dart';
import 'package:mobile_agent/infrastructure/providers/cost_budget_provider.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

class FixtureProvider implements LlmProvider {
  FixtureProvider(this.events, {this.throwAfter = false, this.onDispatch});
  List<UnifiedEvent> events;
  final bool throwAfter;
  final void Function()? onDispatch;
  final requests = <UnifiedRequest>[];
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    onDispatch?.call();
    yield* Stream.fromIterable(events);
    if (throwAfter) throw StateError('isolated failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clock = DateTime(2026, 10, 20, 12);
  const hard = CostBudgetPolicy(
      dailyLimitCents: 100000,
      monthlyLimitCents: 1000000,
      hardStopEnabled: true);
  const soft = CostBudgetPolicy(
      dailyLimitCents: 100000,
      monthlyLimitCents: 1000000,
      hardStopEnabled: false);
  const config = ProviderConfig(
      id: 'fixture',
      baseUrl: 'https://invalid.test',
      model: 'fixture',
      apiKey: 'DO_NOT_PERSIST',
      inputPricePerMillionCents: 1000000,
      outputPricePerMillionCents: 1000000);
  const request = UnifiedRequest(
      model: 'fixture',
      messages: [],
      maxTokens: 20,
      costRunId: 'run-fixture',
      costRequestId: 'request-fixture');
  late AppDatabase db;
  late CostBudgetLedger ledger;
  var primaryClosed = false;
  setUp(() {
    primaryClosed = false;
    db = AppDatabase(NativeDatabase.memory());
    ledger = CostBudgetLedger(db);
  });
  tearDown(() async {
    if (!primaryClosed) await db.close();
  });
  CostBudgetProvider wrap(FixtureProvider raw,
          {ProviderConfig settings = config, CostBudgetPolicy policy = hard}) =>
      CostBudgetProvider(raw, settings,
          database: () async => db,
          policy: () async => policy,
          now: () => clock);

  test(
      'successful usage persists correlation, estimate and no secrets or prompts',
      () async {
    final raw = FixtureProvider([
      const UsageEvent(promptTokens: 7, completionTokens: 5),
      const CompletedEvent(stopReason: StopReason.endOfTurn)
    ]);
    await wrap(raw).stream(request).toList();
    final row = (await ledger.entries(runId: 'run-fixture')).single;
    expect(row.state, 'settled');
    expect(row.amountCents, 12);
    expect(row.originalCents, greaterThan(12));
    expect(row.requestId, 'request-fixture');
    expect(row.providerId, 'fixture');
    expect(row.promptTokens, 7);
    final details =
        await db.customSelect('SELECT * FROM nexus_cost_request_details').get();
    expect(details.single.data.toString(), isNot(contains('DO_NOT_PERSIST')));
    expect(details.single.data.keys, isNot(contains('api_key')));
    expect(details.single.data.keys, isNot(contains('messages')));
  });
  test(
      'missing and explicitly synthetic usage remain pending, never free retries',
      () async {
    final raw = FixtureProvider([
      const UsageEvent(
          promptTokens: 0, completionTokens: 0, usageReported: false),
      const CompletedEvent()
    ]);
    final provider = wrap(raw);
    await provider.stream(request).toList();
    await provider.stream(request).toList();
    final rows = await ledger.entries();
    expect(rows.length, 2);
    expect(rows.map((r) => r.id).toSet().length, 2);
    expect(
        rows.every((r) =>
            r.state == 'pending' &&
            r.reason == 'missing_usage' &&
            r.requestId == 'request-fixture'),
        true);
    final snapshot = await ledger.snapshot(hard, now: clock);
    expect(snapshot.dailyReservedCents,
        rows.fold<int>(0, (sum, r) => sum + r.amountCents));
    expect(snapshot.dailySettledCents, 0);
  });
  test('provider failure retains at least observed cost even above reservation',
      () async {
    final raw = FixtureProvider([
      const UsageEvent(promptTokens: 20000, completionTokens: 1),
      const ProviderErrorEvent('fixture')
    ]);
    await wrap(raw).stream(request).toList();
    final row = (await ledger.entries()).single;
    expect(row.state, 'pending');
    expect(row.reason, 'provider_failure');
    expect(row.amountCents, 20001);
  });
  test('thrown stream failure is recorded as pending without swallowing error',
      () async {
    final raw = FixtureProvider([], throwAfter: true);
    await expectLater(wrap(raw).stream(request).toList(), throwsStateError);
    expect((await ledger.entries()).single.reason, 'provider_failure');
  });
  test('cancellation after dispatch does not settle reported usage', () async {
    final cancel = CancelToken();
    final raw = FixtureProvider([
      const UsageEvent(promptTokens: 1, completionTokens: 1),
      const CompletedEvent()
    ], onDispatch: () => cancel.cancel('fixture'));
    await wrap(raw).stream(request, cancelToken: cancel).toList();
    final row = (await ledger.entries()).single;
    expect(row.state, 'pending');
    expect(row.reason, 'cancelled');
    expect(row.amountCents, greaterThan(2));
  });
  test('cancelled before reserve sends nothing and creates no charge row',
      () async {
    final cancel = CancelToken()..cancel('fixture');
    final raw = FixtureProvider([]);
    await wrap(raw).stream(request, cancelToken: cancel).toList();
    expect(raw.requests, isEmpty);
    expect(await ledger.entries(), isEmpty);
  });
  test('unpriced soft-limit dispatch is unknown; later hard stop fails closed',
      () async {
    var policy = soft;
    final raw = FixtureProvider([const CompletedEvent()]);
    const unpriced = ProviderConfig(
        baseUrl: 'https://invalid.test',
        model: 'unknown',
        apiKey: 'DO_NOT_PERSIST');
    final first = CostBudgetProvider(raw, unpriced,
        database: () async => db, policy: () async => policy, now: () => clock);
    await first.stream(request).toList();
    final row = (await ledger.entries()).single;
    expect(row.priced, false);
    expect(row.state, 'pending');
    expect(row.reason, 'unpriced');
    policy = hard;
    expect((await ledger.snapshot(hard, now: clock)).allowed, false);
    final events = await wrap(raw).stream(request).toList();
    expect((events.single as ProviderErrorEvent).failureKind,
        CostBudgetProvider.pricingUnavailable);
    expect(raw.requests.length, 1);
    expect(
        await ledger.reconcile(row.id, 15,
            expectedRevision: 0, reference: 'fixture bill', now: clock),
        true);
    expect((await ledger.snapshot(hard, now: clock)).allowed, true);
    expect((await ledger.snapshot(hard, now: clock)).dailySpentCents, 15);
  });
  test('bill correction is atomic, revision fenced, auditable and not additive',
      () async {
    final id = (await ledger.reserve(hard, 100, now: clock)).id!;
    expect(
        await ledger.reconcile(id, 30, expectedRevision: 0, reference: 'bill'),
        false);
    await ledger.markPending(id, 'missing_usage');
    expect(
        await ledger.reconcile(id, 30,
            expectedRevision: 0, reference: 'bill', now: clock),
        true);
    expect(
        await ledger.reconcile(id, 70, expectedRevision: 0, reference: 'stale'),
        false);
    expect(
        await ledger.reconcile(id, 40,
            expectedRevision: 1, reference: 'bill correction', now: clock),
        true);
    final row = (await ledger.entries()).single;
    expect(row.state, 'reconciled');
    expect(row.amountCents, 40);
    expect(row.originalCents, 100);
    expect(row.revision, 2);
    final audits = await db
        .customSelect(
            'SELECT * FROM nexus_cost_reconciliations ORDER BY revision')
        .get();
    expect(audits.length, 2);
    expect(audits.first.read<int>('before_cents'), 100);
    expect(audits.last.read<int>('before_cents'), 30);
    final snapshot = await ledger.snapshot(hard, now: clock);
    expect(snapshot.dailySpentCents, 40);
    expect(snapshot.dailyReservedCents, 0);
    await ledger.settle(id, 1);
    expect((await ledger.entries()).single.amountCents, 40);
  });
  test('negative settlement and empty bill evidence cannot corrupt totals',
      () async {
    final id = (await ledger.reserve(hard, 100, now: clock)).id!;
    await expectLater(ledger.settle(id, -1), throwsArgumentError);
    await expectLater(
        ledger.markPending(id, 'missing_usage', observedCents: -1),
        throwsArgumentError);
    await ledger.markPending(id, 'missing_usage');
    await expectLater(
        ledger.reconcile(id, 0, expectedRevision: 0, reference: ' '),
        throwsArgumentError);
    expect((await ledger.entries()).single.amountCents, 100);
  });
  test('sidecar migration preserves existing reservations and is repeatable',
      () async {
    await ledger.ensureReady();
    await db.customStatement(
        "INSERT INTO nexus_cost_reservations VALUES ('old','2026-10-20','2026-10',50,'reserved')");
    await ledger.ensureReady();
    await ledger.ensureReady();
    final row = (await ledger.entries()).single;
    expect(row.id, 'old');
    expect(row.originalCents, 50);
    expect(row.runId, null);
    await ledger.markPending('old', 'interrupted_review');
    expect(
        await ledger.reconcile('old', 20,
            expectedRevision: 0, reference: 'legacy bill'),
        true);
    expect((await ledger.entries()).single.amountCents, 20);
  });
  test(
      'concurrent admission shares one durable allowance and pagination is bounded',
      () async {
    const small = CostBudgetPolicy(
        dailyLimitCents: 100, monthlyLimitCents: 100, hardStopEnabled: true);
    final admissions = await Future.wait(
        List.generate(4, (_) => ledger.reserve(small, 40, now: clock)));
    expect(admissions.where((r) => r.id != null).length, 2);
    expect((await ledger.entries(limit: 1)).length, 1);
    expect((await ledger.entries(limit: 1, offset: 1)).length, 1);
    await expectLater(ledger.entries(limit: 201), throwsArgumentError);
    expect((await ledger.snapshot(small, now: clock)).dailySpentCents, 80);
  });
  test('token bound wrapper preserves local correlation', () async {
    final raw = FixtureProvider([const CompletedEvent()]);
    await TokenBudgetProvider(raw, 10000).stream(request).toList();
    expect(raw.requests.single.costRunId, 'run-fixture');
    expect(raw.requests.single.costRequestId, 'request-fixture');
  });
  test('executor stamps durable run and local request correlation', () async {
    final raw = FixtureProvider([
      const TextDeltaEvent('fixture'),
      const CompletedEvent(stopReason: StopReason.endOfTurn)
    ]);
    final executor = AgentExecutor(provider: raw, tools: ToolRegistry());
    await executor.run(
        history: [],
        model: 'fixture',
        costRunId: 'durable-run',
        totalTokenBudget: 10000).toList();
    expect(raw.requests.single.costRunId, 'durable-run');
    expect(raw.requests.single.costRequestId, isNotEmpty);
  });
  test('settlement is idempotent for both amount and token evidence', () async {
    final id = (await ledger.reserve(hard, 100, now: clock)).id!;
    await ledger.settle(id, 10, promptTokens: 4, completionTokens: 6);
    await ledger.settle(id, 5, promptTokens: 1, completionTokens: 4);
    final row = (await ledger.entries()).single;
    expect(row.amountCents, 10);
    expect(row.promptTokens, 4);
    expect(row.completionTokens, 6);
  });
  test('pre-dispatch cancellation is a documented zero rather than usage',
      () async {
    final cancel = CancelToken();
    final raw = FixtureProvider([]);
    final provider = CostBudgetProvider(raw, config,
        database: () async {
          cancel.cancel('fixture');
          return db;
        },
        policy: () async => hard,
        now: () => clock);
    await provider.stream(request, cancelToken: cancel).toList();
    final row = (await ledger.entries()).single;
    expect(raw.requests, isEmpty);
    expect(row.amountCents, 0);
    expect(row.state, 'settled');
    expect(row.reason, 'cancelled_before_dispatch');
  });
  test('media without reliable pricing remains unknown even with text rates',
      () async {
    final raw = FixtureProvider([
      const UsageEvent(promptTokens: 1, completionTokens: 1),
      const CompletedEvent()
    ]);
    final media = UnifiedRequest(model: 'fixture', messages: [
      ChatMessage(
          role: MessageRole.user,
          parts: const [MessagePart.image('fixture-no-network')])
    ]);
    await wrap(raw, policy: soft).stream(media).toList();
    final row = (await ledger.entries()).single;
    expect(row.state, 'pending');
    expect(row.priced, false);
    expect(row.reason, 'unpriced');
    expect((await ledger.snapshot(hard, now: clock)).allowed, false);
  });
  test(
      'explicit privacy wipe clears review references; legacy restore preservation does not',
      () async {
    final id = (await ledger.reserve(hard, 100, now: clock)).id!;
    await ledger.markPending(id, 'missing_usage');
    await ledger.reconcile(id, 20,
        expectedRevision: 0, reference: 'private-local-bill', now: clock);
    await db.clearAllUserData(preserveMobileData: true);
    expect((await ledger.entries()).single.amountCents, 20);
    expect(
        (await db
                .customSelect('SELECT * FROM nexus_cost_reconciliations')
                .get())
            .length,
        1);
    await db.clearAllUserData();
    expect(await ledger.entries(), isEmpty);
    expect(
        await db.customSelect('SELECT * FROM nexus_cost_reconciliations').get(),
        isEmpty);
    expect(
        await db.customSelect('SELECT * FROM nexus_cost_request_details').get(),
        isEmpty);
  });
  test(
      'pending reservation survives closing and reopening a fixture-only database',
      () async {
    await db.close();
    primaryClosed = true;
    final root = await Directory.systemTemp.createTemp('nexus-cost-isolated-');
    final path = File('${root.path}/cost.sqlite');
    AppDatabase? first, second;
    try {
      first = AppDatabase(NativeDatabase(path));
      final one = CostBudgetLedger(first);
      final id =
          (await one.reserve(hard, 80, now: clock, runId: 'persisted-run')).id!;
      await one.markPending(id, 'missing_usage');
      await first.close();
      first = null;
      second = AppDatabase(NativeDatabase(path));
      final two = CostBudgetLedger(second);
      expect((await two.entries()).single.runId, 'persisted-run');
      expect((await two.entries()).single.state, 'pending');
      expect((await two.snapshot(hard, now: clock)).dailyReservedCents, 80);
    } finally {
      if (first != null) await first.close();
      if (second != null) await second.close();
      await root.delete(recursive: true);
    }
  });
  test('late observed cost raises pending hold and fences an old review dialog',
      () async {
    final id = (await ledger.reserve(hard, 100, now: clock)).id!;
    await ledger.markPending(id, 'interrupted_review');
    await ledger.markPending(id, 'provider_failure', observedCents: 200);
    final row = (await ledger.entries()).single;
    expect(row.amountCents, 200);
    expect(row.revision, 1);
    expect(
        await ledger.reconcile(id, 0,
            expectedRevision: 0, reference: 'stale dialog'),
        false);
    expect(
        await ledger.reconcile(id, 40,
            expectedRevision: 1, reference: 'verified bill'),
        true);
    await ledger.markPending(id, 'provider_failure', observedCents: 300);
    expect((await ledger.entries()).single.amountCents, 40);
  });
  test(
      'executor retry keeps request identity but each attempt holds its own cost',
      () async {
    late FixtureProvider raw;
    raw = FixtureProvider([], onDispatch: () {
      raw.events = raw.requests.length == 1
          ? [const ProviderErrorEvent('isolated retry', statusCode: 503)]
          : [
              const TextDeltaEvent('fixture'),
              const UsageEvent(promptTokens: 7, completionTokens: 5),
              const CompletedEvent(stopReason: StopReason.endOfTurn)
            ];
    });
    final executor = AgentExecutor(provider: wrap(raw), tools: ToolRegistry());
    await executor.run(
        history: [],
        model: 'fixture',
        costRunId: 'retry-run',
        maxRetries: 1,
        retryBackoff: Duration.zero,
        totalTokenBudget: 10000).toList();
    expect(raw.requests.length, 2);
    expect(raw.requests.map((r) => r.costRequestId).toSet().length, 1);
    final rows = await ledger.entries(runId: 'retry-run');
    expect(rows.length, 2);
    expect(rows.map((r) => r.id).toSet().length, 2);
    expect(rows.map((r) => r.requestId).toSet().length, 1);
    expect(rows.where((r) => r.state == 'pending').length, 1);
    expect(rows.where((r) => r.state == 'settled').length, 1);
  });
}
