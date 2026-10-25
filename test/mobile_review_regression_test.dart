import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mobile_agent/domain/research_artifact.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/cost_budget_ledger.dart';
import 'package:mobile_agent/infrastructure/providers/cost_budget_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 19);
  EvidenceCitation citation(
          {String excerpt = 'quoted',
          String uri = 'https://example.org/source',
          bool conflict = false,
          DateTime? verified}) =>
      EvidenceCitation(
          id: 'c',
          sourceTitle: 'source',
          sourceUri: uri,
          excerpt: excerpt,
          capturedAt: now,
          verifiedAt: verified ?? now,
          contradictsClaim: conflict);
  ResearchClaim claim(List<EvidenceCitation> citations) => ResearchClaim(
      id: 'claim', statement: 'unproven assertion', citations: citations);
  test('freshness label never promises semantic truth', () {
    expect(EvidenceSupportLevel.supported.label, contains('结论待复核'));
    expect(claim([citation()]).evaluateSupport(now: now),
        EvidenceSupportLevel.supported);
  });
  test('missing or invalid evidence cannot be supported', () {
    for (final citations in <List<EvidenceCitation>>[
      [],
      [citation(excerpt: '')],
      [citation(uri: 'file:///secret')],
      [citation(uri: 'https:relative')]
    ]) {
      expect(claim(citations).evaluateSupport(now: now),
          EvidenceSupportLevel.partial);
    }
  });
  test('conflict and stale sources remain visible', () {
    expect(claim([citation(conflict: true)]).evaluateSupport(now: now),
        EvidenceSupportLevel.conflicting);
    expect(
        claim([citation(verified: now.subtract(const Duration(days: 15)))])
            .evaluateSupport(now: now),
        EvidenceSupportLevel.stale);
    expect(
        claim([citation(verified: now.add(const Duration(days: 1)))])
            .evaluateSupport(now: now),
        EvidenceSupportLevel.stale);
  });
  const policy = CostBudgetPolicy(
      dailyLimitCents: 100, monthlyLimitCents: 1000, hardStopEnabled: true);
  test('reserved and settled remain distinct on allowed and stopped decisions',
      () {
    for (final daily in [50, 100]) {
      final value = CostBudgetService.evaluatePolicy(
          policy: policy,
          dailySpentCents: daily,
          monthlySpentCents: 200,
          dailyReservedCents: 30,
          monthlyReservedCents: 40);
      expect(value.dailyReservedCents, 30);
      expect(value.dailySettledCents, daily - 30);
      expect(value.monthlySettledCents, 160);
      expect(value.allowed, daily < 100);
    }
    final month = CostBudgetService.evaluatePolicy(
        policy: policy,
        dailySpentCents: 50,
        monthlySpentCents: 1000,
        dailyReservedCents: 30,
        monthlyReservedCents: 40);
    expect(month.allowed, false);
    expect(month.monthlyReservedCents, 40);
  });
  test('invalid reservation accounting is rejected', () {
    expect(
        () => CostBudgetService.evaluatePolicy(
            policy: policy,
            dailySpentCents: 10,
            monthlySpentCents: 10,
            dailyReservedCents: 11),
        throwsFormatException);
  });
  test('ledger distinguishes durable reservations and settlement', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ledger = CostBudgetLedger(db);
    final first = await ledger.reserve(policy, 30, now: now);
    final second = await ledger.reserve(policy, 40, now: now);
    expect((await ledger.snapshot(policy, now: now)).dailyReservedCents, 70);
    await ledger.settle(first.id!, 10);
    final value = await ledger.snapshot(policy, now: now);
    expect(value.dailySpentCents, 50);
    expect(value.dailyReservedCents, 40);
    expect(value.dailySettledCents, 10);
    expect(second.id, isNotNull);
    expect((await ledger.reserve(policy, 60, now: now)).id, isNull);
  });
}
