import 'package:mobile_agent/presentation/navigation/mobile_shell.dart';
import 'package:mobile_agent/presentation/chat/widgets/attachment_drawer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_bar.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/utils/keyboard_insets.dart';

/// 空会话控制器：跳过数据库 / 网络初始化，直接给出空态 [ChatState]。
class _EmptyChatController extends ChatController {
  @override
  ChatState build() => const ChatState(
        loading: false,
        running: false,
        conversationId: 'conv-empty',
        messages: [],
      );
}

/// 有内容会话控制器：让会话指标条不为空（isEmpty == rounds==0 && steps==0）。
class _BusyChatController extends ChatController {
  @override
  ChatState build() => ChatState(
        loading: false,
        running: false,
        conversationId: 'conv-busy',
        totalSteps: 3,
        messages: [
          ChatMessage(
            role: MessageRole.user,
            parts: [const MessagePart.text('你好')],
          ),
          ChatMessage(
            role: MessageRole.assistant,
            parts: [const MessagePart.text('你好，很高兴为你服务')],
            elapsed: const Duration(seconds: 8),
            ttft: const Duration(seconds: 3),
            usage: const Usage(promptTokens: 1000, completionTokens: 500),
          ),
        ],
      );
}

Future<void> _pumpChatPage(
  WidgetTester tester, {
  ChatController Function() controller = _EmptyChatController.new,
  bool nestedShell = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatControllerProvider.overrideWith(controller)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: nestedShell
            ? MobileShell(pageBuilders: [
                (_) => const ChatPage(),
                for (var index = 1; index < 4; index++) (_) => const Scaffold(),
              ])
            : const ChatPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('keyboardInset：Scaffold body 内的 inset 遮蔽回归', () {
    testWidgets(
        'body 内 MediaQuery.viewInsetsOf 恒为 0（根因），'
        'keyboardInset 在 body 内外都取到真实值', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      double? helperAboveScaffold;
      double? helperInBody;
      double? mediaQueryInBody;
      bool? visibleInBody;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (outer) {
              // 外层 context：位于 Scaffold 之上
              helperAboveScaffold = keyboardInset(outer);
              return Scaffold(
                body: LayoutBuilder(
                  builder: (inner, _) {
                    // 复刻 chat_page 的真实位置：Scaffold body 内的 LayoutBuilder 回调。
                    // 这里内层参数命名为 inner，正是为了不遮蔽外层 context——
                    // 生产代码里它就叫 context，这是本 bug 隐蔽的原因。
                    mediaQueryInBody = MediaQuery.viewInsetsOf(inner).bottom;
                    helperInBody = keyboardInset(inner);
                    visibleInBody = isKeyboardVisible(inner);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(helperAboveScaffold, 300);
      expect(
        mediaQueryInBody,
        0,
        reason: 'Scaffold 会消费底部 inset。这条断言是 keyboardInset 存在的理由；'
            '若它开始返回非 0，说明 Flutter 行为变了，可重新评估是否还需要 helper。',
      );
      expect(helperInBody, 300, reason: 'helper 必须绕过 Scaffold 的作用域');
      expect(visibleInBody, isTrue);
    });

    testWidgets('键盘收起时 keyboardInset 为 0、isKeyboardVisible 为 false',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var visible = true;
      var inset = -1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                visible = isKeyboardVisible(c);
                inset = keyboardInset(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(inset, 0);
      expect(visible, isFalse);
    });
  });

  group('聊天首页：键盘弹出时收起欢迎建议', () {
    testWidgets('键盘收起 → 显示快捷建议和配置入口', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester);

      expect(find.text('整理一份资料'), findsOneWidget);
      expect(find.text('配置模型'), findsOneWidget);
    });

    testWidgets('键盘弹出 → 快捷建议与配置入口一并隐藏', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester);
      expect(find.text('整理一份资料'), findsOneWidget);

      // Focus is required: the app deliberately ignores stale keyboard insets.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('整理一份资料'),
        findsNothing,
        reason: '键盘弹出时空态建议必须隐藏，否则小屏下会与键盘挤在一起',
      );
      expect(find.text('配置模型'), findsNothing);

      // 收起键盘应当恢复。
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump();
      expect(find.text('整理一份资料'), findsOneWidget);
    });
  });

  for (final nestedShell in [false, true]) {
    testWidgets(
        'back closes the attachment panel before leaving chat nested=$nestedShell',
        (tester) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpChatPage(tester, nestedShell: nestedShell);
      await tester.tap(find.byTooltip('添加附件或更多工具'));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentDrawerPanel), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentDrawerPanel), findsNothing);
      expect(find.byType(ChatPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'shared navigation closes before the attachment panel on Android back',
      (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpChatPage(tester, nestedShell: true);
    await tester.tap(find.byTooltip('添加附件或更多工具'));
    // A pending local-history load keeps the skeleton animating in this seam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('打开导航菜单'));
    // A pending local-history load keeps the skeleton animating in this seam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('助手与工具'), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    await tester.binding.handlePopRoute();
    // A pending local-history load keeps the skeleton animating in this seam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('助手与工具'), findsNothing);
    expect(find.byType(AttachmentDrawerPanel), findsOneWidget);
    await tester.binding.handlePopRoute();
    // A pending local-history load keeps the skeleton animating in this seam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AttachmentDrawerPanel), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sidebar tools panel preserves the draft and closes independently',
      (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpChatPage(tester, nestedShell: true);
    await tester.enterText(find.byType(TextField).first, '保留这份草稿');
    await tester.tap(find.byTooltip('打开导航菜单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('助手与工具'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    // A shell/theme rebuild must not consult a disposed drawer State.
    final reassembly = tester.binding.reassembleApplication();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await reassembly;
    expect(find.text('MCP 与工具'), findsOneWidget);
    expect(find.text('提示词'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MCP 与工具'), findsNothing);
    expect(find.text('保留这份草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('会话指标：保持更多菜单入口，不挤占键盘上方空间', () {
    testWidgets('键盘收起时仍可从更多菜单查看指标', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpChatPage(tester, controller: _BusyChatController.new);
      expect(find.byType(SessionMetricsBar), findsNothing);
      expect(find.byType(SessionMetricsHud), findsNothing);
      await tester.tap(find.byTooltip('更多输入工具'));
      await tester.pumpAndSettle();
      expect(find.text('用量与上下文'), findsOneWidget);
    });

    testWidgets('键盘弹出时不恢复常驻指标，入口仍可用', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpChatPage(tester, controller: _BusyChatController.new);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SessionMetricsBar), findsNothing);
      expect(find.byType(SessionMetricsHud), findsNothing);
      await tester.tap(find.byTooltip('更多输入工具'));
      await tester.pumpAndSettle();
      expect(find.text('用量与上下文'), findsOneWidget);
    });
  });
}
