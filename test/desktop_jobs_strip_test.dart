import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/navigation/desktop_jobs_strip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  Future<void> insertTask(
    AppDatabase db, {
    required String id,
    required String title,
    required String status,
    DateTime? updatedAt,
  }) async {
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: id,
            conversationId: 'c-1',
            requestJson: jsonEncode({'title': title}),
            status: Value(status),
            createdAt: now,
            updatedAt: updatedAt ?? now,
          ),
        );
  }

  Future<(ProviderContainer, AppDatabase)> pumpStrip(
    WidgetTester tester, {
    required AppDatabase db,
    VoidCallback? onOpenAll,
    ValueChanged<JobSummary>? onOpenJob,
  }) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: DesktopTheme.apply(ThemeData.light()),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: DesktopJobsStrip(
            onOpenAll: onOpenAll,
            onOpenJob: onOpenJob,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (container, db);
  }

  testWidgets('有进行中任务时显示状态条，点击展开浮层面板', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await insertTask(db, id: 't-run', title: '重构登录模块', status: 'running');
    await insertTask(db, id: 't-fail', title: '同步远端分支', status: 'failed');

    var openedAll = false;
    final opened = <String>[];
    await pumpStrip(
      tester,
      db: db,
      onOpenAll: () => openedAll = true,
      onOpenJob: (job) => opened.add(job.id),
    );

    expect(find.byKey(const ValueKey('desktop-jobs-strip')), findsOneWidget);
    expect(find.text('1 个任务进行中'), findsOneWidget);
    expect(find.textContaining('待处理'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-jobs-strip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('任务与待处理'), findsOneWidget);
    expect(find.text('重构登录模块'), findsOneWidget);
    expect(find.text('同步远端分支'), findsWidgets);

    await tester.tap(find.text('重构登录模块').first);
    await tester.pump();
    expect(opened, ['t-run']);
    expect(find.text('任务与待处理'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop-jobs-strip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('jobs-panel-open-all')));
    await tester.pump();
    expect(openedAll, isTrue);
  });

  testWidgets('无任务无待处理时完全隐藏', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpStrip(tester, db: db);

    expect(find.byKey(const ValueKey('desktop-jobs-strip')), findsNothing);
  });

  testWidgets('只有待处理任务时状态条显示待处理计数', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await insertTask(db, id: 't-fail', title: '失败的构建', status: 'failed');

    await pumpStrip(tester, db: db);

    expect(find.byKey(const ValueKey('desktop-jobs-strip')), findsOneWidget);
    expect(find.textContaining('待处理'), findsWidgets);
  });
}
