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
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_bar.dart';
import 'package:mobile_agent/presentation/navigation/app_shell.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'desktop_workspace_interaction_test.dart'
    show WorkspaceFixtureDevices, WorkspaceFixtureGit, WorkspaceFixtureFiles;

class _CompactConversation extends ChatController {
  @override
  ChatState build() => ChatState(
        loading: false,
        providerConfigured: true,
        activeModel: '测试模型',
        currentProjectName: '布局验证',
        currentWorkspacePath: 'D:/fixture',
        messages: [
          ChatMessage(
              role: MessageRole.user,
              parts: const [MessagePart.text('减少输入框占位。')]),
          ChatMessage(
              role: MessageRole.assistant,
              parts: const [MessagePart.text('保留消息滚动空间与原有操作入口。')]),
        ],
      );
}

void main() {
  const surfaceKey = ValueKey('desktop-composer-surface');
  const fieldKey = ValueKey('desktop-composer-field');
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child, {bool desktop = true, double scale = 1}) =>
      MaterialApp(
        theme:
            desktop ? DesktopTheme.apply(ThemeData.light()) : ThemeData.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: child)),
      );
  Widget input(
    TextEditingController controller, {
    bool running = false,
    bool paused = false,
    VoidCallback? send,
    VoidCallback? pause,
    VoidCallback? resume,
    VoidCallback? stop,
    VoidCallback? session,
    ValueNotifier<bool>? attachments,
    ChatMode? mode,
    ValueChanged<ChatMode>? changeMode,
    int lines = 5,
    String modelLabel = '测试模型',
  }) =>
      FloatingCapsuleInput(
        controller: controller,
        isRunning: running,
        isPaused: paused,
        onSend: send ?? () {},
        onStop: stop ?? () {},
        onPause: pause,
        onResume: resume,
        onAttachmentMenu: () {},
        onModeTap: session,
        onModelTap: () {},
        onApprovalModeTap: () {},
        modelLabel: modelLabel,
        desktopChatMode: mode,
        onDesktopChatModeChanged: changeMode,
        desktopMaxLines: lines,
        hasAttachmentsListenable: attachments,
      );

  testWidgets('desktop empty composer is compact and grows only with content',
      (tester) async {
    await size(tester, const Size(1000, 700));
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(input(c)));
    final idle = tester.getSize(find.byKey(surfaceKey)).height;
    expect(idle, lessThanOrEqualTo(84));
    expect(tester.widget<TextField>(find.byKey(fieldKey)).minLines, 1);
    await tester.enterText(
        find.byKey(fieldKey), List.filled(12, '保留多行编辑能力').join('\n'));
    await tester.pump();
    final expanded = tester.getSize(find.byKey(surfaceKey)).height;
    expect(expanded, greaterThan(idle + 35));
    expect(expanded, lessThanOrEqualTo(170));
    c.clear();
    await tester.pump();
    // The focused empty state keeps its visible keyboard shortcut hint.
    expect(
        tester.getSize(find.byKey(surfaceKey)).height, lessThanOrEqualTo(96));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester.getSize(find.byKey(surfaceKey)).height, closeTo(idle, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Enter sends, Shift+Enter inserts a newline, IME composition never sends',
      (tester) async {
    await size(tester, const Size(1000, 700));
    final c = TextEditingController();
    addTearDown(c.dispose);
    var sends = 0;
    await tester.pumpWidget(app(input(c, send: () => sends++)));
    await tester.enterText(find.byKey(fieldKey), '布局');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(c.text, contains('\n'));
    expect(sends, 0);
    c.value = const TextEditingValue(
        text: '测试',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 0);
    c.value = const TextEditingValue(
        text: '测试', selection: TextSelection.collapsed(offset: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'attachment-only send remains enabled without reserving input lines',
      (tester) async {
    await size(tester, const Size(1000, 700));
    final c = TextEditingController();
    final attachments = ValueNotifier(false);
    addTearDown(c.dispose);
    addTearDown(attachments.dispose);
    var sends = 0;
    await tester.pumpWidget(
        app(input(c, attachments: attachments, send: () => sends++)));
    expect(find.byKey(const ValueKey('trailing_action_send_disabled')),
        findsOneWidget);
    attachments.value = true;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('trailing_action_send_active')));
    expect(sends, 1);
    expect(
        tester.getSize(find.byKey(surfaceKey)).height, lessThanOrEqualTo(84));
  });

  testWidgets('compact run actions preserve pause, resume and explicit stop',
      (tester) async {
    await size(tester, const Size(1000, 700));
    final c = TextEditingController();
    addTearDown(c.dispose);
    var pauses = 0, resumes = 0, stops = 0;
    await tester
        .pumpWidget(app(input(c, running: true, pause: () => pauses++)));
    await tester.tap(find.byKey(const ValueKey('trailing_action_pause')));
    expect(pauses, 1);
    await tester.pumpWidget(app(input(c,
        running: true,
        paused: true,
        resume: () => resumes++,
        stop: () => stops++)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('trailing_action_resume')));
    await tester
        .tap(find.byKey(const ValueKey('trailing_action_stop_when_paused')));
    expect(resumes, 1);
    expect(stops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'inline mode selection preserves plan warning, running lock and session menu',
      (tester) async {
    await size(tester, const Size(1000, 700));
    final c = TextEditingController();
    addTearDown(c.dispose);
    var mode = ChatMode.agent;
    var running = false;
    var sessions = 0;
    late StateSetter update;
    await tester.pumpWidget(app(StatefulBuilder(builder: (context, setState) {
      update = setState;
      return input(c,
          mode: mode,
          running: running,
          session: () => sessions++,
          changeMode: (value) => setState(() => mode = value));
    })));
    await tester.tap(find.byKey(const ValueKey('chat-mode-plan')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(mode, ChatMode.plan);
    expect(find.text('计划模式已开启 · 首轮需要确认'), findsOneWidget);
    update(() => running = true);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-mode-code')));
    expect(mode, ChatMode.plan);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会话设置'));
    await tester.pumpAndSettle();
    expect(sessions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow composer supports 2x text and short-window multiline bounds',
      (tester) async {
    await size(tester, const Size(480, 440));
    final c = TextEditingController(text: List.filled(10, '大字体长内容').join('\n'));
    addTearDown(c.dispose);
    await tester.pumpWidget(app(
        input(c, lines: 3, mode: ChatMode.plan, changeMode: (_) {}),
        scale: 2));
    expect(tester.widget<TextField>(find.byKey(fieldKey)).maxLines, 3);
    expect(tester.getSize(find.byKey(surfaceKey)).height, lessThan(240));
    expect(find.byKey(const ValueKey('composer-primary-action-slot')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop explains modes, approval and focused keyboard shortcuts',
      (tester) async {
    await size(tester, const Size(1000, 700));
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester
        .pumpWidget(app(input(c, mode: ChatMode.agent, changeMode: (_) {})));
    expect(find.text('编码'), findsOneWidget);
    expect(find.text('规划'), findsOneWidget);
    expect(find.text('操作前询问'), findsOneWidget);
    const hint = ValueKey('desktop-composer-shortcut-hint');
    expect(find.byKey(hint), findsNothing);
    await tester.tap(find.byKey(fieldKey));
    await tester.pump();
    expect(find.byKey(hint), findsOneWidget);
    expect(tester.getSize(find.byKey(surfaceKey)).width, closeTo(848, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long model names retain full hover labels at large text',
      (tester) async {
    await size(tester, const Size(480, 440));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const label = '项目专用模型 / extremely-long-model-name-with-version-2026';
    await tester
        .pumpWidget(app(input(controller, modelLabel: label), scale: 2));
    expect(find.byTooltip(label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop fields compact padding without changing mobile touch targets',
      (tester) async {
    await size(tester, const Size(1000, 700));
    await tester.pumpWidget(
        app(const Padding(padding: EdgeInsets.all(12), child: TextField())));
    expect(
        tester.getSize(find.byType(TextField)).height, lessThanOrEqualTo(42));
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(input(c), desktop: false));
    expect(find.byKey(fieldKey), findsNothing);
    expect(
        tester.getSize(
            find.byKey(const ValueKey('composer-primary-action-slot'))),
        const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real desktop shell gives conversation width and height back to messages',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'chat.provider_hint_dismissed': true});
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(_CompactConversation.new),
      desktopDevicesProvider.overrideWith(WorkspaceFixtureDevices.new),
      desktopGitServiceProvider.overrideWithValue(WorkspaceFixtureGit()),
      desktopWorkspaceFilesProvider.overrideWithValue(WorkspaceFixtureFiles()),
    ]);
    var disposed = false;
    addTearDown(() async {
      if (!disposed) {
        container.dispose();
      }
      await db.close();
    });
    await size(tester, const Size(1440, 900));
    for (final config in [
      (const Size(1440, 900), 1.0),
      (const Size(900, 640), 1.0),
      (const Size(1280, 720), 1.5),
      (const Size(1440, 900), 2.0)
    ]) {
      tester.view.physicalSize = config.$1;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: DesktopTheme.apply(ThemeData.light()),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$2)),
                child: child!),
            home: const DesktopShell(),
          )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final viewport =
          tester.getSize(find.byKey(const ValueKey('chat-message-viewport')));
      if (config.$1.width == 1440 && config.$2 == 1.0) {
        expect(tester.getSize(find.byKey(surfaceKey)).width, closeTo(848, 1));
        expect(tester.getSize(find.byKey(surfaceKey)).height,
            lessThanOrEqualTo(84));
        expect(viewport.height, greaterThan(580));
      } else {
        expect(viewport.height, greaterThan(260));
      }
      if (config.$1.width == 1440) {
        final resources =
            find.byKey(const ValueKey('desktop-resource-shortcuts'));
        final scrollbar = tester.widget<Scrollbar>(find
            .ancestor(of: resources, matching: find.byType(Scrollbar))
            .first);
        expect(scrollbar.thumbVisibility, isTrue);
        expect(scrollbar.trackVisibility, isTrue);
        await tester.ensureVisible(find.text('技能与 MCP'));
        await tester.pump();
        final resourceRect = tester.getRect(resources);
        expect(resourceRect.contains(tester.getCenter(find.text('技能与 MCP'))),
            isTrue);
        final messageList = find
            .descendant(
                of: find.byKey(const ValueKey('chat-message-viewport')),
                matching: find.byType(ListView))
            .first;
        expect(tester.getCenter(messageList).dx,
            closeTo(tester.getCenter(find.byKey(surfaceKey)).dx, 1));
        final summaryRect = tester.getRect(find.byType(SessionMetricsBar));
        final composerRect = tester.getRect(find.byKey(surfaceKey));
        expect(summaryRect.left, closeTo(composerRect.left, 1));
        expect(summaryRect.right, closeTo(composerRect.right, 1));
      }
      expect(tester.takeException(), isNull,
          reason: '${config.$1} / ${config.$2}x');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
    await tester.pump(const Duration(milliseconds: 100));
  });
}
