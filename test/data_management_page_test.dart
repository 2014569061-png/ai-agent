import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/data_management_stats_query.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/data_management_stats.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/l10n/app_strings.dart';
import 'package:mobile_agent/presentation/settings/data_management_page.dart';

class _Query extends DataManagementStatsQuery {
  _Query(this.loader) : super(database: _unusedDatabase);
  Future<DataManagementStats> Function() loader;
  int calls = 0;
  static Future<AppDatabase> _unusedDatabase() async =>
      throw UnimplementedError();
  @override
  Future<DataManagementStats> load() {
    calls++;
    return loader();
  }
}

DataManagementStats counts(int memories, int docs, int schedules) =>
    DataManagementStats(
        memoryCount: memories, knowledgeCount: docs, scheduledCount: schedules);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester, _Query? query,
      {AppDatabase? db, double width = 800, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          if (query != null)
            dataManagementStatsQueryProvider.overrideWithValue(query),
          if (db != null) databaseProvider.overrideWith((ref) async => db),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const DataManagementPage())));
    await tester.pump();
  }

  testWidgets('initial pending counts are unknown, not false empty states',
      (tester) async {
    final pending = Completer<DataManagementStats>();
    await mount(tester, _Query(() => pending.future));
    expect(find.text('正在读取统计信息'), findsOneWidget);
    expect(find.text('统计中…'), findsNWidgets(3));
    expect(find.text('空'), findsNothing);
    expect(find.text('未建立'), findsNothing);
    expect(find.text('无计划'), findsNothing);
    pending.complete(counts(0, 0, 0));
    await tester.pumpAndSettle();
    expect(find.text('空'), findsOneWidget);
    expect(find.text('未建立'), findsOneWidget);
    expect(find.text('无计划'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
      'initial error persists, never claims empty data, and retry recovers',
      (tester) async {
    final query =
        _Query(() async => throw StateError('private internal error'));
    await mount(tester, query);
    await tester.pumpAndSettle();
    expect(find.text('统计信息读取失败，尚无法确认数据量'), findsOneWidget);
    expect(find.text('未读取'), findsNWidgets(3));
    expect(find.text('空'), findsNothing);
    expect(find.text('未建立'), findsNothing);
    expect(find.textContaining('private internal'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('统计信息读取失败，尚无法确认数据量'), findsOneWidget);
    query.loader = () async => counts(4, 5, 6);
    await tester.tap(find.text('重试统计'));
    await tester.pumpAndSettle();
    expect(find.text('4 条'), findsOneWidget);
    expect(find.text('5 条文档'), findsOneWidget);
    expect(find.text('6 个计划'), findsOneWidget);
    expect(find.text('重试统计'), findsNothing);
    expect(query.calls, 2);
  });

  testWidgets(
      'refresh keeps the last valid counts and labels failure until a successful retry',
      (tester) async {
    final query = _Query(() async => counts(7, 8, 9));
    await mount(tester, query);
    await tester.pumpAndSettle();
    final pending = Completer<DataManagementStats>();
    query.loader = () => pending.future;
    await tester.tap(find.byTooltip('刷新统计'));
    await tester.pump();
    expect(find.text('正在刷新统计，暂时显示上次结果'), findsOneWidget);
    expect(find.text('7 条'), findsOneWidget);
    pending.completeError(StateError('refresh failed'));
    await tester.pumpAndSettle();
    expect(find.text('统计刷新失败，当前显示上次成功结果'), findsOneWidget);
    expect(find.text('7 条'), findsOneWidget);
    query.loader = () async => counts(10, 11, 12);
    await tester.tap(find.text('重试统计'));
    await tester.pumpAndSettle();
    expect(find.text('10 条'), findsOneWidget);
    expect(find.text('统计刷新失败，当前显示上次成功结果'), findsNothing);
  });

  for (final olderFails in [false, true]) {
    testWidgets(
        'latest request wins when an older request ${olderFails ? "fails" : "succeeds"} late',
        (tester) async {
      final older = Completer<DataManagementStats>();
      final newer = Completer<DataManagementStats>();
      final query = _Query(() => older.future);
      await mount(tester, query);
      query.loader = () => newer.future;
      await tester.tap(find.byTooltip('刷新统计'));
      await tester.pump();
      newer.complete(counts(11, 22, 33));
      await tester.pumpAndSettle();
      if (olderFails) {
        older.completeError(StateError('stale'));
      } else {
        older.complete(counts(99, 99, 99));
      }
      await tester.pumpAndSettle();
      expect(find.text('11 条'), findsOneWidget);
      expect(find.text('22 条文档'), findsOneWidget);
      expect(find.text('33 个计划'), findsOneWidget);
      expect(find.textContaining('统计信息读取失败'), findsNothing);
      expect(find.text('99 条'), findsNothing);
    });
  }

  testWidgets(
      'an old success cannot hide a newer failure or overwrite the last successful result',
      (tester) async {
    final query = _Query(() async => counts(1, 2, 3));
    await mount(tester, query);
    await tester.pumpAndSettle();
    final older = Completer<DataManagementStats>();
    final newer = Completer<DataManagementStats>();
    query.loader = () => older.future;
    await tester.tap(find.byTooltip('刷新统计'));
    await tester.pump();
    query.loader = () => newer.future;
    await tester.tap(find.byTooltip('刷新统计'));
    await tester.pump();
    newer.completeError(StateError('new failure'));
    await tester.pumpAndSettle();
    older.complete(counts(99, 99, 99));
    await tester.pumpAndSettle();
    expect(find.text('统计刷新失败，当前显示上次成功结果'), findsOneWidget);
    expect(find.text('1 条'), findsOneWidget);
    expect(find.text('99 条'), findsNothing);
  });

  for (final entry in [
    () => AppStrings.memorySectionTitle,
    () => AppStrings.knowledgeSectionTitle,
    () => AppStrings.scheduledTasksEntry,
    () => AppStrings.dataBackup,
  ]) {
    testWidgets('return from counted feature ${entry()} refreshes all counts',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final query = _Query(() async => counts(1, 2, 3));
      await mount(tester, query, db: db);
      await tester.pumpAndSettle();
      final target = find.text(entry());
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(query.calls, 1);
      query.loader = () async => counts(0, 0, 0);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(query.calls, 2);
      expect(find.text('未建立'), findsOneWidget);
      expect(find.text('空'), findsOneWidget);
      expect(find.text('无计划'), findsOneWidget);
    });
  }

  testWidgets(
      'real database query refreshes after changes made while a child page is open',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() => db.customStatement(
        "INSERT INTO memories(id,content,created_at,updated_at) VALUES('stats-ui','owned fixture',1,1)"));
    await mount(tester, null, db: db);
    await tester.pumpAndSettle();
    expect(find.text('1 条'), findsOneWidget);
    await tester.tap(find.text(AppStrings.memorySectionTitle));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => db.customStatement("DELETE FROM memories WHERE id='stats-ui'"));
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('未建立'), findsOneWidget);
    expect(find.text('1 条'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets('completion after dispose is ignored, error=$fails',
        (tester) async {
      final pending = Completer<DataManagementStats>();
      await mount(tester, _Query(() => pending.future));
      await tester.pumpWidget(const SizedBox.shrink());
      if (fails) {
        pending.completeError(StateError('late failure'));
      } else {
        pending.complete(counts(1, 2, 3));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'persistent error and retry remain usable at narrow width and large text',
      (tester) async {
    final query = _Query(() async => throw StateError('load failed'));
    await mount(tester, query, width: 320, scale: 2);
    await tester.pumpAndSettle();
    expect(find.text('统计信息读取失败，尚无法确认数据量'), findsOneWidget);
    expect(tester.takeException(), isNull);
    query.loader = () async => counts(1, 2, 3);
    await tester.tap(find.text('重试统计'));
    await tester.pumpAndSettle();
    expect(query.calls, 2);
    expect(tester.takeException(), isNull);
  });
}
