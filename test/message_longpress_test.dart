import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/l10n/app_strings.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 消息长按菜单的**可达性**回归。
///
/// 背景（2026-09-12 实测）：气泡正文原本是 `SelectableText`，外层又套了
/// `Tooltip(triggerMode: longPress)` —— 两者都会在**手势竞技场**里赢过气泡外层的
/// `GestureDetector(onLongPress)`，而那个长按是消息菜单的**唯一入口**
/// （`chat_page.dart::_showMessageActions`）。结果是"朗读 / 复制全文 / 编辑并重发"
/// 在真机上根本点不出来，且不报任何错。
///
/// 所以这里的断言必须落在「**菜单真的出现了**」上。只断言"回调被调用"的弱断言
/// 抓不到这个缺陷 —— 缺陷的本质正是回调根本没被调用。
ChatState _state() => ChatState(
      loading: false,
      running: false,
      conversationId: 'conv-1',
      totalSteps: 3,
      messages: [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('用户提问内容')],
        ),
        ChatMessage(
          role: MessageRole.assistant,
          parts: [const MessagePart.text('这是助手的回答内容。')],
          elapsed: const Duration(seconds: 8),
        ),
      ],
    );

class _StaticChatController extends ChatController {
  @override
  ChatState build() => _state();
}

Future<void> _pumpChatPage(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [chatControllerProvider.overrideWith(_StaticChatController.new)],
    child: MaterialApp(theme: AppTheme.light(), home: const ChatPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('正文默认可选文本数为 0（长按不会被文本选择器截走）', (tester) async {
    await _pumpChatPage(tester);
    // 一旦有人把正文改回 SelectableText，这条会立即变红 —— 它是上面那个
    // 缺陷的根因守卫，比"菜单能弹出来"更早一层的保险。
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('长按助手气泡弹出消息菜单', (tester) async {
    await _pumpChatPage(tester);
    await tester.longPress(find.byType(MessageBubble).last);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.messageActions), findsOneWidget);
    expect(find.text(AppStrings.copyFullText), findsOneWidget);
  });

  testWidgets('长按用户气泡弹出消息菜单（含编辑并重发）', (tester) async {
    await _pumpChatPage(tester);
    // 用户气泡内容右对齐，而 MessageBubble 的盒子是整行宽 —— 按盒子中心会落在
    // 空白处，所以这里必须按到正文上。
    await tester.longPress(find.text('用户提问内容'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.messageActions), findsOneWidget);
    expect(find.text('编辑并重发'), findsOneWidget);
  });

  testWidgets('菜单选「选择文本」进入选择模式，可「完成选择」退出', (tester) async {
    await _pumpChatPage(tester);
    await tester.longPress(find.byType(MessageBubble).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.selectText));
    await tester.pumpAndSettle();

    // 进入选择模式：该气泡出现退出按钮，且正文变为可选
    expect(find.text(AppStrings.finishSelecting), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);

    await tester.tap(find.text(AppStrings.finishSelecting));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.finishSelecting), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
  });
}
