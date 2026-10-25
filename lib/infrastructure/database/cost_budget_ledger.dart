import 'package:drift/drift.dart';

import '../../domain/unique_id.dart';
import '../providers/cost_budget_policy.dart';
import 'app_database.dart';

/// Local estimates only. No prompt, credentials or provider URL is persisted.
class CostLedgerEntry {
  const CostLedgerEntry(
      {required this.id,
      required this.day,
      required this.amountCents,
      required this.state,
      required this.revision,
      required this.originalCents,
      this.runId,
      this.requestId,
      this.providerId,
      this.model,
      this.purpose,
      this.reason,
      this.priced,
      this.promptTokens,
      this.completionTokens,
      this.createdAt});
  final String id, day, state;
  final int amountCents, originalCents, revision;
  final String? runId, requestId, providerId, model, purpose, reason;
  final bool? priced;
  final int? promptTokens, completionTokens;
  final DateTime? createdAt;
}

/// Durable admission before dispatch; ambiguous outcomes never release budget.
class CostBudgetLedger {
  const CostBudgetLedger(this.db);
  final AppDatabase db;

  Future<void> ensureReady() async {
    await db
        .customStatement('CREATE TABLE IF NOT EXISTS nexus_cost_reservations ('
            'id TEXT PRIMARY KEY, day TEXT NOT NULL, month TEXT NOT NULL, '
            'amount_cents INTEGER NOT NULL, state TEXT NOT NULL)');
    await db
        .customStatement('CREATE TABLE IF NOT EXISTS nexus_cost_ledger_meta ('
            'id INTEGER PRIMARY KEY, imported INTEGER NOT NULL)');
    // Sidecar migration preserves old rows and does not change positional INSERTs
    // in older builds. Legacy estimates remain identifiable, never re-imported.
    await db.customStatement(
        'CREATE TABLE IF NOT EXISTS nexus_cost_request_details ('
        'id TEXT PRIMARY KEY, run_id TEXT, request_id TEXT, provider_id TEXT, '
        'model TEXT, purpose TEXT, priced INTEGER NOT NULL, '
        'input_rate INTEGER, output_rate INTEGER, original_cents INTEGER NOT NULL, '
        'prompt_tokens INTEGER, completion_tokens INTEGER, reason TEXT, '
        'created_at INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0)');
    await db
        .customStatement('CREATE INDEX IF NOT EXISTS nexus_cost_request_run '
            'ON nexus_cost_request_details(run_id)');
    await db.customStatement(
        'CREATE TABLE IF NOT EXISTS nexus_cost_reconciliations ('
        'id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, before_cents INTEGER NOT NULL, '
        'after_cents INTEGER NOT NULL, previous_state TEXT NOT NULL, '
        'reference TEXT NOT NULL, created_at INTEGER NOT NULL, revision INTEGER NOT NULL)');
    await db.transaction(() async {
      await db.customStatement(
          'INSERT OR IGNORE INTO nexus_cost_ledger_meta VALUES (1, 0)');
      final row = await db
          .customSelect(
              'SELECT imported FROM nexus_cost_ledger_meta WHERE id=1')
          .getSingle();
      if (row.read<int>('imported') != 0) return;
      await db.customStatement('INSERT OR IGNORE INTO nexus_cost_reservations '
          "SELECT 'legacy:' || run_id, strftime('%Y-%m-%d', started_at, 'unixepoch', 'localtime'), "
          "strftime('%Y-%m', started_at, 'unixepoch', 'localtime'), estimated_cost_cents, 'settled' "
          'FROM run_records WHERE estimated_cost_cents IS NOT NULL AND estimated_cost_cents >= 0');
      await db.customStatement(
          'UPDATE nexus_cost_ledger_meta SET imported=1 WHERE id=1');
    });
  }

  Future<CostBudgetEvaluation> _snapshot(
      CostBudgetPolicy policy, DateTime clock,
      {int nextCents = 0}) async {
    final date = clock.toLocal().toIso8601String().substring(0, 10);
    final row = await db.customSelect(
        'SELECT '
        'COALESCE(SUM(CASE WHEN r.day=? THEN amount_cents ELSE 0 END),0) AS daily, '
        'COALESCE(SUM(CASE WHEN r.month=? THEN amount_cents ELSE 0 END),0) AS monthly, '
        "COALESCE(SUM(CASE WHEN r.day=? AND state IN ('reserved','pending') THEN amount_cents ELSE 0 END),0) AS daily_reserved, "
        "COALESCE(SUM(CASE WHEN r.month=? AND state IN ('reserved','pending') THEN amount_cents ELSE 0 END),0) AS monthly_reserved, "
        "COALESCE(SUM(CASE WHEN r.month=? AND d.priced=0 AND state IN ('reserved','pending') THEN 1 ELSE 0 END),0) AS unpriced "
        'FROM nexus_cost_reservations r LEFT JOIN nexus_cost_request_details d ON d.id=r.id',
        variables: [
          Variable<String>(date),
          Variable<String>(date.substring(0, 7)),
          Variable<String>(date),
          Variable<String>(date.substring(0, 7)),
          Variable<String>(date.substring(0, 7))
        ]).getSingle();
    return CostBudgetService.evaluatePolicy(
        policy: policy,
        dailySpentCents: row.read<int>('daily'),
        monthlySpentCents: row.read<int>('monthly'),
        dailyReservedCents: row.read<int>('daily_reserved'),
        monthlyReservedCents: row.read<int>('monthly_reserved'),
        unpricedPendingRequests: row.read<int>('unpriced'),
        estimatedNextCallCents: nextCents);
  }

  Future<CostBudgetEvaluation> snapshot(CostBudgetPolicy policy,
      {DateTime? now}) async {
    await ensureReady();
    return _snapshot(policy, now ?? DateTime.now());
  }

  Future<({String? id, CostBudgetEvaluation evaluation})> reserve(
      CostBudgetPolicy policy, int cents,
      {DateTime? now,
      String? runId,
      String? requestId,
      String? providerId,
      String? model,
      String purpose = 'inference',
      bool priced = true,
      int? inputRate,
      int? outputRate}) async {
    if (cents < 0 ||
        (inputRate != null && inputRate < 0) ||
        (outputRate != null && outputRate < 0)) {
      throw ArgumentError('Negative cost or price');
    }
    await ensureReady();
    final clock = now ?? DateTime.now();
    return db.transaction(() async {
      await db.customStatement(
          'UPDATE nexus_cost_ledger_meta SET imported=imported WHERE id=1');
      final evaluation = await _snapshot(policy, clock, nextCents: cents);
      if (!evaluation.allowed) return (id: null, evaluation: evaluation);
      final date = clock.toLocal().toIso8601String().substring(0, 10);
      final id = UniqueId.generate('cost');
      await db.customStatement(
          'INSERT INTO nexus_cost_reservations VALUES (?, ?, ?, ?, ?)',
          [id, date, date.substring(0, 7), cents, 'reserved']);
      await db.customStatement(
          'INSERT INTO nexus_cost_request_details '
          '(id,run_id,request_id,provider_id,model,purpose,priced,input_rate,output_rate,original_cents,created_at) '
          'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [
            id,
            runId,
            requestId,
            providerId,
            model,
            purpose,
            priced ? 1 : 0,
            inputRate,
            outputRate,
            cents,
            clock.millisecondsSinceEpoch
          ]);
      return (id: id, evaluation: evaluation);
    });
  }

  Future<void> settle(String id, int cents,
      {int? promptTokens,
      int? completionTokens,
      String reason = 'usage_estimate'}) async {
    if (cents < 0 || (promptTokens ?? 0) < 0 || (completionTokens ?? 0) < 0) {
      throw ArgumentError('Negative settlement or usage');
    }
    if (!const {'usage_estimate', 'cancelled_before_dispatch'}
        .contains(reason)) {
      throw ArgumentError.value(reason);
    }
    await db.transaction(() async {
      final changed = await db.customUpdate(
          "UPDATE nexus_cost_reservations SET amount_cents=?, state='settled' WHERE id=? AND state='reserved'",
          variables: [Variable<int>(cents), Variable<String>(id)]);
      if (changed == 0) return;
      await db.customStatement(
          "UPDATE nexus_cost_request_details SET prompt_tokens=?,completion_tokens=?,reason=? WHERE id=? AND EXISTS (SELECT 1 FROM nexus_cost_reservations r WHERE r.id=? AND r.state='settled')",
          [promptTokens, completionTokens, reason, id, id]);
    });
  }

  Future<void> markPending(String id, String reason,
      {int? observedCents}) async {
    if (observedCents != null && observedCents < 0) {
      throw ArgumentError('Negative observed cost');
    }
    if (!const {
      'missing_usage',
      'provider_failure',
      'cancelled',
      'unpriced',
      'interrupted_review'
    }.contains(reason)) {
      throw ArgumentError.value(reason);
    }
    await db.transaction(() async {
      await db.customStatement(
          "UPDATE nexus_cost_request_details SET revision=revision+1 WHERE id=? AND EXISTS "
          "(SELECT 1 FROM nexus_cost_reservations r WHERE r.id=? AND r.state='pending' AND r.amount_cents<?)",
          [id, id, observedCents ?? 0]);
      await db.customStatement(
          "UPDATE nexus_cost_reservations SET state='pending',amount_cents=MAX(amount_cents,?) WHERE id=? AND state IN ('reserved','pending')",
          [observedCents ?? 0, id]);
      await db.customStatement(
          "UPDATE nexus_cost_request_details SET reason=? WHERE id=? AND EXISTS (SELECT 1 FROM nexus_cost_reservations r WHERE r.id=? AND r.state='pending')",
          [reason, id, id]);
    });
  }

  /// Each ledger id is one dispatch attempt. requestId groups retries; runId
  /// groups main requests and summaries. Pagination is bounded, not all-time RAM.
  Future<List<CostLedgerEntry>> entries(
      {String? runId, int limit = 50, int offset = 0}) async {
    if (limit < 1 || limit > 200 || offset < 0) {
      throw ArgumentError('Invalid page');
    }
    await ensureReady();
    final rows = await db.customSelect(
        'SELECT r.*,d.run_id,d.request_id,d.provider_id,d.model,d.purpose,d.priced,'
        'd.prompt_tokens,d.completion_tokens,d.reason,d.created_at,COALESCE(d.revision,0) AS revision,'
        'COALESCE(d.original_cents,r.amount_cents) AS original_cents '
        'FROM nexus_cost_reservations r LEFT JOIN nexus_cost_request_details d ON d.id=r.id '
        '${runId == null ? '' : 'WHERE d.run_id=? '}ORDER BY r.day DESC,COALESCE(d.created_at,0) DESC,r.id DESC LIMIT ? OFFSET ?',
        variables: [
          if (runId != null) Variable<String>(runId),
          Variable<int>(limit),
          Variable<int>(offset)
        ]).get();
    return rows.map((r) {
      final created = r.readNullable<int>('created_at');
      final priced = r.readNullable<int>('priced');
      return CostLedgerEntry(
          id: r.read<String>('id'),
          day: r.read<String>('day'),
          amountCents: r.read<int>('amount_cents'),
          state: r.read<String>('state'),
          revision: r.read<int>('revision'),
          originalCents: r.read<int>('original_cents'),
          runId: r.readNullable<String>('run_id'),
          requestId: r.readNullable<String>('request_id'),
          providerId: r.readNullable<String>('provider_id'),
          model: r.readNullable<String>('model'),
          purpose: r.readNullable<String>('purpose'),
          reason: r.readNullable<String>('reason'),
          priced: priced == null ? null : priced == 1,
          promptTokens: r.readNullable<int>('prompt_tokens'),
          completionTokens: r.readNullable<int>('completion_tokens'),
          createdAt: created == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(created));
    }).toList(growable: false);
  }

  /// User-confirmed local bill correction, never automatic or an invoice fetch.
  /// Compare-and-set revision prevents a stale dialog overwriting newer review.
  Future<bool> reconcile(String id, int cents,
      {required int expectedRevision,
      required String reference,
      DateTime? now}) async {
    reference = reference.trim();
    if (cents < 0 ||
        expectedRevision < 0 ||
        reference.isEmpty ||
        reference.length > 200) {
      throw ArgumentError(
          'Amount, revision and non-secret bill reference required');
    }
    await ensureReady();
    return db.transaction(() async {
      await db.customStatement(
          'UPDATE nexus_cost_ledger_meta SET imported=imported WHERE id=1');
      final row = await db.customSelect(
          'SELECT r.*,COALESCE(d.revision,0) AS revision '
          'FROM nexus_cost_reservations r LEFT JOIN nexus_cost_request_details d ON d.id=r.id WHERE r.id=?',
          variables: [Variable<String>(id)]).getSingleOrNull();
      if (row == null ||
          row.read<int>('revision') != expectedRevision ||
          !const {'pending', 'settled', 'reconciled'}
              .contains(row.read<String>('state'))) {
        return false;
      }
      final clock = now ?? DateTime.now();
      final before = row.read<int>('amount_cents');
      await db.customStatement(
          'INSERT OR IGNORE INTO nexus_cost_request_details '
          '(id,priced,original_cents,created_at) VALUES (?,1,?,?)',
          [id, before, clock.millisecondsSinceEpoch]);
      await db.customStatement(
          "UPDATE nexus_cost_reservations SET amount_cents=?,state='reconciled' WHERE id=?",
          [cents, id]);
      await db.customStatement(
          "UPDATE nexus_cost_request_details SET revision=revision+1,reason='manual_bill_review' WHERE id=?",
          [id]);
      await db.customStatement(
          'INSERT INTO nexus_cost_reconciliations VALUES (?,?,?,?,?,?,?,?)', [
        UniqueId.generate('review'),
        id,
        before,
        cents,
        row.read<String>('state'),
        reference,
        clock.millisecondsSinceEpoch,
        expectedRevision + 1
      ]);
      return true;
    });
  }
}
