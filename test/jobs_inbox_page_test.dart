// 阶段 7b：任务与收件箱页面。
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/jobs/job_board_providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/jobs/jobs_inbox_page.dart';

void main() {
  testWidgets('shows inbox items, lists all jobs and marks everything seen',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final seen = InMemoryInboxSeenStore();
    final board = JobBoard(db, seen: seen);
    final now = DateTime.now();

    Future<void> task(String id, String status, String title) =>
        db.saveTask(Task(
          id: id,
          conversationId: 'conv-$id',
          projectId: null,
          stateRevision: 0,
          type: 'agent',
          status: status,
          requestJson: jsonEncode({'prompt': title, 'title': title}),
          progressJson: '{}',
          resumeCount: 0,
          createdAt: now,
          updatedAt: now,
        ));

    await tester.runAsync(() async {
      await task('t1', 'failed', '修复登录');
      await task('t2', 'running', '整理文档');
      await db.insertAuditLog(AuditLogsCompanion.insert(
        id: 'r1',
        type: JobBoard.scheduledRunAuditType,
        detail: jsonEncode(
            {'taskName': '每日简报', 'status': 'success', 'result': '完成'}),
        decision: const Value('success'),
        risk: const Value('background'),
        createdAt: now,
      ));
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [jobBoardProvider.overrideWith((ref) async => board)],
        child: const MaterialApp(home: JobsInboxPage()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // 收件箱：失败任务 + 定时运行；运行中的任务不在收件箱。
    expect(find.text('收件箱 2'), findsOneWidget);
    await tester.tap(find.text('收件箱 2'));
    await tester.pumpAndSettle();
    expect(find.text('修复登录'), findsOneWidget);
    expect(find.text('每日简报'), findsOneWidget);
    expect(find.text('整理文档'), findsNothing);

    // 全部任务：三条都在。
    await tester.tap(find.text('最近任务'));
    await tester.pumpAndSettle();
    expect(find.text('整理文档'), findsOneWidget);

    await tester.tap(find.byTooltip('更多任务操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部标为已读'));
    // Menu dismissal uses the test clock; SQLite refresh uses real async IO.
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      if (find.text('收件箱').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump();
    await tester.runAsync(() async {
      expect(await board.unreadCount(), 0);
      await db.close();
    });
    expect(find.text('收件箱'), findsOneWidget);
    // 让提示条的计时器走完。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
