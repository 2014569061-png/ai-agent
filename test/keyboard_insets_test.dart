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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatControllerProvider.overrideWith(controller)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ChatPage(),
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

  group('聊天空态：键盘弹出时隐藏建议 chips（真机可见行为）', () {
    testWidgets('键盘收起 → 显示建议 chips', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester);

      expect(find.text('解读项目'), findsOneWidget);
      expect(find.text('修复问题'), findsOneWidget);
    });

    testWidgets('键盘弹出 → 建议 chips 与状态行一并隐藏', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester);
      expect(find.text('解读项目'), findsOneWidget);

      // 弹出键盘：TestFlutterView 的 setter 会派发 metrics 变化。
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('解读项目'),
        findsNothing,
        reason: '键盘弹出时空态建议必须隐藏，否则小屏下会与键盘挤在一起',
      );
      expect(find.text('修复问题'), findsNothing);

      // 收起键盘应当恢复。
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump();
      expect(find.text('解读项目'), findsOneWidget);
    });
  });

  group('会话指标条：键盘弹起时收缩为 2 组（省出键盘上方空间）', () {
    testWidgets('键盘收起 → maxGroups 不收缩', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester, controller: _BusyChatController.new);

      final bar =
          tester.widget<SessionMetricsBar>(find.byType(SessionMetricsBar));
      expect(bar.maxGroups, isNull);
    });

    testWidgets('键盘弹出 → maxGroups 收缩为 2', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester, controller: _BusyChatController.new);
      expect(
        tester
            .widget<SessionMetricsBar>(find.byType(SessionMetricsBar))
            .maxGroups,
        isNull,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<SessionMetricsBar>(find.byType(SessionMetricsBar))
            .maxGroups,
        2,
        reason: '键盘弹起时指标条应收窄，避免挤占键盘上方空间',
      );
    });
  });
}
