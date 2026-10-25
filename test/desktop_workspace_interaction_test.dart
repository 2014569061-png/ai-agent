import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/desktop_device_service.dart';
import 'package:mobile_agent/application/desktop_git_service.dart';
import 'package:mobile_agent/application/desktop_workbench_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/navigation/app_shell.dart';
import 'package:mobile_agent/presentation/navigation/desktop_workspace_chrome.dart';
import 'package:mobile_agent/presentation/navigation/desktop_workbench_panels.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

class WorkspaceFixtureChat extends ChatController {
  void emit(ChatState Function(ChatState) fn) => state = fn(state);
  @override
  ChatState build() => ChatState(
          loading: false,
          providerConfigured: true,
          currentWorkspacePath: 'D:/fixture',
          currentProjectId: 'project-fixture',
          conversationId: 'conversation-fixture',
          currentProjectName: 'mobile_agent',
          conversationTitle: '首页蓝白主题',
          activeModel: '测试模型',
          mode: ChatMode.agent,
          planState: const PlanState(status: 'executing', steps: [
            PlanStep(id: '1', description: '统一颜色与字体', status: 'completed'),
            PlanStep(id: '2', description: '优化任务卡片', status: 'completed'),
            PlanStep(id: '3', description: '验证响应式布局', status: 'running'),
          ]),
          messages: [
            ChatMessage(
                role: MessageRole.user,
                parts: const [MessagePart.text('统一蓝白配色，并优化任务卡片。')]),
            ChatMessage(
                role: MessageRole.assistant,
                parts: const [MessagePart.text('已完成主题调整，正在检查布局与交互。')]),
          ]);
}

class WorkspaceFixtureGit extends DesktopGitService {
  bool isStaged = false;
  int stageCalls = 0;
  @override
  Future<DesktopGitSnapshot> inspect(String workspace) async =>
      DesktopGitSnapshot(root: workspace, branch: 'ui/blue-white', files: [
        DesktopGitFile(
            'app_theme.dart', isStaged ? 'M' : ' ', isStaged ? ' ' : 'M')
      ]);
  @override
  Future<String> diff(DesktopGitSnapshot snapshot, DesktopGitFile file,
          {bool staged = false}) async =>
      '--- a/app_theme.dart\n+++ b/app_theme.dart\n@@ -1,2 +1,2 @@\n'
      '-const primary = oldColor;\n+const primary = blueColor;';
  @override
  Future<void> stage(DesktopGitSnapshot snapshot, DesktopGitFile file) async {
    stageCalls++;
    isStaged = true;
  }

  @override
  Future<void> unstage(DesktopGitSnapshot snapshot, DesktopGitFile file) async {
    isStaged = false;
  }
}

class WorkspaceFixtureFiles extends DesktopWorkspaceFiles {
  @override
  Future<List<DesktopFileEntry>> list(String root, String directory) async =>
      const [
        DesktopFileEntry(relativePath: 'app_theme.dart', directory: false)
      ];
  @override
  Future<String> preview(String root, String path) async =>
      'const primary = blueColor;';
}

class WorkspaceFixtureDevices extends DesktopDevicesController {
  @override
  Future<DesktopDeviceSnapshot> build() async => const DesktopDeviceSnapshot();
}

void main() {
  late ProviderContainer container;
  late AppDatabase database;
  late WorkspaceFixtureGit git;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'chat.provider_hint_dismissed': true,
      'desktop.layout.version': 2,
      'desktop.side.open': true,
      'desktop.terminal.open': false,
    });
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    git = WorkspaceFixtureGit();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => database),
      chatControllerProvider.overrideWith(WorkspaceFixtureChat.new),
      desktopGitServiceProvider.overrideWithValue(git),
      desktopWorkspaceFilesProvider.overrideWithValue(WorkspaceFixtureFiles()),
      desktopDevicesProvider.overrideWith(WorkspaceFixtureDevices.new),
    ]);
  });

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
            home: const DesktopShell())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('selected diff can stage, switch scope and unstage',
      (tester) async {
    try {
      await show(tester);
      expect(find.text('+const primary = blueColor;'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '暂存改动'));
      await tester.pump();
      await tester.pump();
      expect(git.stageCalls, 1);
      expect(find.text('工作区干净，没有未暂存改动'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '已暂存'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '取消暂存'));
      await tester.pump();
      await tester.pump();
      expect(git.isStaged, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('navigator loads older sessions beyond the first thirty',
      (tester) async {
    try {
      final now = DateTime(2026, 10, 14);
      for (var i = 0; i < 35; i++) {
        await database
            .into(database.conversations)
            .insert(ConversationsCompanion.insert(
              id: 'older-$i',
              title: Value('历史会话 $i'),
              projectId: const Value('project-fixture'),
              createdAt: now,
              updatedAt: now.subtract(Duration(minutes: i)),
            ));
      }
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
              home: Scaffold(
                  body: DesktopProjectNavigator(
                onProject: () {},
                onOpenProject: (_) {},
                onNew: () {},
                onSession: (_) {},
                onCite: (_) {},
                onDevices: () {},
              )))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final more = find.byKey(const ValueKey('desktop-load-older-sessions'));
      await tester.scrollUntilVisible(more, 500,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(more);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('desktop-session-older-34')), 500,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('历史会话 34'), findsOneWidget);
      expect(more, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('review prepares prompt and retains draft across navigation',
      (tester) async {
    try {
      await show(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '检查改动'));
      await tester.pump();
      expect(find.textContaining('请审查当前工作区的 Git 改动'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-nav-历史')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('desktop-nav-会话')));
      await tester.pump();
      expect(find.textContaining('请审查当前工作区的 Git 改动'), findsOneWidget);
      expect(container.read(chatControllerProvider).running, isFalse);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('task history makes records beyond thirty selectable',
      (tester) async {
    try {
      final now = DateTime(2026, 10, 14);
      for (var i = 0; i < 35; i++) {
        await database.into(database.tasks).insert(TasksCompanion.insert(
              id: 'history-task-$i',
              conversationId: 'conversation-fixture',
              requestJson: '{"title":"历史任务 $i"}',
              status: const Value('completed'),
              createdAt: now,
              updatedAt: now.subtract(Duration(minutes: i)),
            ));
      }
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
              home: Scaffold(body: DesktopChangesPanel(onProject: () {})))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final dropdown = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      expect(dropdown.items, hasLength(30));
      final more = find.byKey(const ValueKey('desktop-load-older-tasks'));
      await tester.tap(more);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final expanded = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      expect(expanded.items, hasLength(35));
      expect(expanded.items!.last.value, 'history-task-34');
      expanded.onChanged!('history-task-34');
      await tester.pump();
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byType(DropdownButton<String>))
              .value,
          'history-task-34');
      expect(more, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('file browser supplies removable real context chips',
      (tester) async {
    try {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('desktop-navigator-files')));
      await tester.pump();
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('desktop-file-app_theme.dart')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, '加入上下文').first);
      await tester.pump();
      await tester.pump();
      expect(
          container
              .read(chatControllerProvider)
              .pendingCitations
              .single
              .relativePath,
          'app_theme.dart');
      expect(find.byType(InputChip), findsOneWidget);
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      chip.onDeleted!();
      await tester.pump();
      expect(container.read(chatControllerProvider).pendingCitations, isEmpty);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets(
      'preview rejects non-web addresses and execution tabs show actual state',
      (tester) async {
    try {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('desktop-side-tab-1')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('desktop-preview-address')),
          'javascript:alert(1)');
      await tester.tap(find.byTooltip('打开预览地址'));
      await tester.pump();
      expect(
          find.textContaining('请输入完整的 http:// 或 https:// 地址'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-terminal-tab-2')));
      await tester.pump();
      expect(find.text('没有失败的工具调用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('desktop Shift+Enter inserts a newline', (tester) async {
    try {
      await show(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'first');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tester.widget<TextField>(field).controller!.text, contains('\n'));
      expect(container.read(chatControllerProvider).running, isFalse);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('navigator highlights active worktree thread with badge',
      (tester) async {
    try {
      final now = DateTime(2026, 10, 15);
      await database
          .into(database.conversations)
          .insert(ConversationsCompanion.insert(
            id: 'thread-conv-1',
            title: const Value('Worktree 线程任务'),
            projectId: const Value('project-fixture'),
            createdAt: now,
            updatedAt: now,
          ));

      final chat = container.read(chatControllerProvider.notifier) as WorkspaceFixtureChat;
      chat.emit((s) => s.copyWith(
            conversationId: 'thread-conv-1',
            currentWorkspacePath: 'D:/fixture/.nexus/worktrees/thread-conv-1',
          ));

      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
              home: Scaffold(
                  body: DesktopProjectNavigator(
                onProject: () {},
                onOpenProject: (_) {},
                onNew: () {},
                onSession: (_) {},
                onCite: (_) {},
                onDevices: () {},
              )))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
          find.byKey(const ValueKey('desktop-session-worktree-thread-conv-1')),
          findsOneWidget);
      expect(find.text('Worktree'), findsOneWidget);
      expect(find.byIcon(Icons.alt_route), findsOneWidget);
    } finally {
      await cleanup(tester);
    }
  });
}
