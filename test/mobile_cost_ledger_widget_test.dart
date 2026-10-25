import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_agent/application/providers.dart' show databaseProvider;
import 'package:mobile_agent/presentation/dashboard/widgets/token_usage_hero.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/cost_budget_ledger.dart';
import 'package:mobile_agent/infrastructure/providers/cost_budget_policy.dart';
import 'package:mobile_agent/presentation/dashboard/cost_ledger_page.dart';

void main() {
  const policy = CostBudgetPolicy(
      dailyLimitCents: 1000, monthlyLimitCents: 10000, hardStopEnabled: true);
  for (final layout in <(double, double, double, Brightness)>[
    (360, 800, 1.6, Brightness.light),
    (360, 800, 2.0, Brightness.light),
    (360, 800, 1.6, Brightness.dark),
    (640, 360, 1.6, Brightness.dark)
  ]) {
    testWidgets(
        'cost ledger layout ${layout.$1}/${layout.$2}/${layout.$3}/${layout.$4}',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ledger = CostBudgetLedger(db);
      final id = (await ledger.reserve(policy, 100,
              runId: 'run-fixture',
              requestId: 'request-fixture',
              model: 'fixture'))
          .id!;
      await ledger.markPending(id, 'missing_usage');
      tester.view.physicalSize = Size(layout.$1, layout.$2);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: layout.$4),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(layout.$3)),
              child: child!),
          home: CostLedgerPage(database: () async => db)));
      await tester.pumpAndSettle();
      expect(find.textContaining('待确认（仍占预算）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('账本记录说明'));
      await tester.pumpAndSettle();
      expect(find.textContaining('跨机备份'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'bill review requires explicit confirmation and persists correction',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ledger = CostBudgetLedger(db);
    final id = (await ledger.reserve(policy, 100)).id!;
    await ledger.markPending(id, 'missing_usage');
    await tester.pumpWidget(
        MaterialApp(home: CostLedgerPage(database: () async => db)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按账单人工核对'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('cost-review-save')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const ValueKey('cost-review-amount')), '0.25');
    await tester.enterText(find.byKey(const ValueKey('cost-review-reference')),
        'isolated bill reference');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cost-review-save')));
    await tester.pumpAndSettle();
    final row = (await ledger.entries()).single;
    expect(row.state, 'reconciled');
    expect(row.amountCents, 25);
    expect(row.revision, 1);
    expect(find.textContaining('已人工核对账单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('interrupted reservation review never releases its money',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ledger = CostBudgetLedger(db);
    await ledger.reserve(policy, 100);
    await tester.pumpWidget(
        MaterialApp(home: CostLedgerPage(database: () async => db)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行已停止？标记待确认'));
    await tester.pumpAndSettle();
    expect(find.text('确认关联运行已经停止？'), findsOneWidget);
    await tester.tap(find.text('已停止，标记待确认'));
    await tester.pumpAndSettle();
    final row = (await ledger.entries()).single;
    expect(row.state, 'pending');
    expect(row.amountCents, 100);
    expect((await ledger.snapshot(policy)).dailyReservedCents, 100);
    expect(tester.takeException(), isNull);
  });
  testWidgets('database failure is disclosed rather than shown as empty/zero',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home:
            CostLedgerPage(database: () async => throw StateError('fixture'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('账本读取失败'), findsOneWidget);
    expect(find.text('本页没有费用记录'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final settled in [0, 50]) {
    testWidgets(
        'hero displays ledger settlement $settled instead of old run estimate',
        (tester) async {
      final evaluation = CostBudgetService.evaluatePolicy(
          policy: policy,
          dailySpentCents: settled + 25,
          monthlySpentCents: settled + 25,
          dailyReservedCents: 25,
          monthlyReservedCents: 25);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: TokenUsageHero(
                      days: const [], costBudget: evaluation)))));
      await tester.pumpAndSettle();
      expect(find.text('结算估算 ¥${(settled / 100).toStringAsFixed(2)}'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('hero discloses unpriced calls rather than displaying zero cost',
      (tester) async {
    final evaluation = CostBudgetService.evaluatePolicy(
        policy: policy,
        dailySpentCents: 0,
        monthlySpentCents: 0,
        unpricedPendingRequests: 1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child:
                    TokenUsageHero(days: const [], costBudget: evaluation)))));
    await tester.pumpAndSettle();
    expect(find.text('费用未知'), findsOneWidget);
    expect(find.text('结算估算 ¥0.00'), findsNothing);
    expect(find.textContaining('未定价待确认 1 笔'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'hero navigation keeps the scoped fixture database, not singleton data',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await CostBudgetLedger(db)
        .reserve(policy, 100, runId: 'scoped-fixture-only');
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: const MaterialApp(
            home: Scaffold(
                body:
                    SingleChildScrollView(child: TokenUsageHero(days: []))))));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('dashboard-cost-ledger'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('逐请求费用账本'), findsOneWidget);
    expect(find.textContaining('scoped-fixture-only'), findsNothing);
    await tester.tap(find.text('运行与请求编号'));
    await tester.pumpAndSettle();
    expect(find.textContaining('scoped-fixture-only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
