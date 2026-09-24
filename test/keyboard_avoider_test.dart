import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/utils/keyboard_avoider.dart';

/// 键盘回归：底部白块 / 输入框悬在半空。键盘高度只作用于输入区，并按输入
/// 焦点门控；失焦后残留的 inset 超时即按 0 处理。
class _EmptyChatController extends ChatController {
  @override
  ChatState build() => const ChatState(
        loading: false,
        running: false,
        conversationId: 'conv-empty',
        messages: [],
      );
}

const _spacerKey = ValueKey('keyboard-spacer');

Future<void> _pumpScope(WidgetTester tester, {FocusNode? focusNode}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      resizeToAvoidBottomInset: false,
      body: KeyboardInsetScope(
        child: Column(children: [
          const Expanded(child: SizedBox()),
          if (focusNode != null) TextField(focusNode: focusNode),
          const KeyboardSpacer(key: _spacerKey),
        ]),
      ),
    ),
  ));
}

double _spacerHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_spacerKey)).height;

Future<void> _pumpChatPage(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatControllerProvider.overrideWith(_EmptyChatController.new)
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ChatPage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('KeyboardInsetScope', () {
    testWidgets('focused text field: spacer follows the keyboard inset',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 20);
      addTearDown(tester.view.reset);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await _pumpScope(tester, focusNode: focusNode);
      expect(_spacerHeight(tester), 20, reason: '键盘收起时占位底部安全区');

      focusNode.requestFocus();
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(_spacerHeight(tester), 300);

      tester.view.resetViewInsets();
      await tester.pump();
      expect(_spacerHeight(tester), 20);
    });

    testWidgets('stale inset without focus falls back and hides the IME',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 20);
      addTearDown(tester.view.reset);
      await _pumpScope(tester);
      tester.testTextInput.log.clear();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(_spacerHeight(tester), 300, reason: '宽限期内先跟随，保证收起动画平滑');

      await tester.pump(const Duration(milliseconds: 450));
      expect(_spacerHeight(tester), 20, reason: '失焦残留超时后按 0 处理');
      expect(
        tester.testTextInput.log.map((call) => call.method),
        contains('TextInput.hide'),
      );

      tester.view.resetViewInsets();
      await tester.pump();
      expect(_spacerHeight(tester), 20);
    });

    testWidgets('backgrounding the app releases text focus', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await _pumpScope(tester, focusNode: focusNode);
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('maybeOf is null outside a scope', (tester) async {
      double? inset = -1;
      await tester.pumpWidget(Builder(builder: (context) {
        inset = KeyboardInsetScope.maybeOf(context);
        return const SizedBox();
      }));
      expect(inset, isNull);
    });
  });

  group('聊天页：输入框始终贴底或贴在键盘上方', () {
    testWidgets('无输入焦点的残留 inset 超时后输入框回到底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpChatPage(tester);
      final composer = find.byType(FloatingCapsuleInput);
      final restingBottom = tester.getBottomLeft(composer).dy;

      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();

      expect(tester.getBottomLeft(composer).dy, restingBottom);
    });

    testWidgets('输入框获得焦点时被键盘顶起，收起后回到底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpChatPage(tester);
      final composer = find.byType(FloatingCapsuleInput);
      final restingBottom = tester.getBottomLeft(composer).dy;

      await tester
          .tap(find.descendant(of: composer, matching: find.byType(TextField)));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      await tester.pump();
      expect(tester.getBottomLeft(composer).dy, restingBottom - 336);

      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump();
      expect(tester.getBottomLeft(composer).dy, restingBottom);
    });
  });
}
