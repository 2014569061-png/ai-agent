import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/desktop_search_service.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/navigation/desktop_command_center.dart';

class _CommandFixtureChat extends ChatController {
  @override
  ChatState build() => const ChatState(loading: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 15, 12);

  Future<AppDatabase> seedDatabase() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.conversations).insert(
          ConversationsCompanion.insert(
            id: 'c-1',
            title: const Value('登录页改造'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            id: 'p-1',
            name: 'Nexus 桌面',
            canonicalRootPath: 'D:/nexus',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: 't-1',
            conversationId: 'c-1',
            requestJson: jsonEncode({'title': '登录接口联调'}),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return db;
  }

  Future<void> openCenter(
    WidgetTester tester, {
    required AppDatabase db,
    required List<DesktopCommandAction> actions,
    required void Function(DesktopSearchResult result) onResult,
  }) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(_CommandFixtureChat.new),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => DesktopCommandCenter(
                    actions: actions,
                    onOpenResult: (result) async => onResult(result),
                  ),
                ),
                child: const Text('打开命令中心'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开命令中心'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('命令按分组展示，输入过滤后用键盘执行', (tester) async {
    var ranNav = false;
    var ranSettings = false;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await openCenter(
      tester,
      db: db,
      actions: [
        DesktopCommandAction(
          icon: Icons.dashboard_outlined,
          label: '转到工作台',
          group: '导航',
          hint: 'Ctrl+2',
          onRun: () => ranNav = true,
        ),
        DesktopCommandAction(
          icon: Icons.settings_outlined,
          label: '打开设置',
          onRun: () => ranSettings = true,
        ),
      ],
      onResult: (_) {},
    );

    expect(find.text('导航'), findsOneWidget);
    expect(find.text('命令'), findsOneWidget);
    expect(find.text('转到工作台'), findsOneWidget);
    expect(find.text('打开设置'), findsOneWidget);
    expect(find.text('↑↓ 选择 · Enter 执行 · Esc 关闭'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('command-center-input')), '设');
    await tester.pump();

    expect(find.text('转到工作台'), findsNothing);
    expect(find.text('打开设置'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(ranSettings, isTrue);
    expect(ranNav, isFalse);
    expect(find.byType(DesktopCommandCenter), findsNothing);
  });

  testWidgets('输入关键词检索会话与任务并跳转', (tester) async {
    final db = await seedDatabase();
    addTearDown(db.close);
    DesktopSearchResult? opened;
    await openCenter(
      tester,
      db: db,
      actions: const [],
      onResult: (result) => opened = result,
    );

    await tester.enterText(
        find.byKey(const ValueKey('command-center-input')), '登录');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('登录页改造'), findsOneWidget);
    expect(find.text('登录接口联调'), findsOneWidget);

    await tester.tap(find.text('登录页改造'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(opened?.kind, DesktopSearchKind.conversation);
    expect(opened?.id, 'c-1');
    expect(find.byType(DesktopCommandCenter), findsNothing);
  });

  testWidgets('方向键移动高亮后 Enter 执行，Esc 关闭', (tester) async {
    var first = 0;
    var second = 0;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await openCenter(
      tester,
      db: db,
      actions: [
        DesktopCommandAction(
          icon: Icons.add,
          label: '第一个命令',
          onRun: () => first++,
        ),
        DesktopCommandAction(
          icon: Icons.remove,
          label: '第二个命令',
          onRun: () => second++,
        ),
      ],
      onResult: (_) {},
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(first, 0);
    expect(second, 1);
    expect(find.byType(DesktopCommandCenter), findsNothing);

    await tester.tap(find.text('打开命令中心'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(DesktopCommandCenter), findsNothing);
  });
}
