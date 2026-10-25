import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 会话目录抽屉与系统返回键的交互回归。
///
/// 背景（2026-10-17 模拟器实测）：Flutter 框架不会自动用系统返回键关闭
/// Scaffold 抽屉，而 chat_page 原先没有接管返回事件 —— 抽屉打开时按返回键
/// 直接退到桌面，不符合 Android「先关浮层、再退出页面」的导航约定。
/// 修复在 chat_page 的 Scaffold 外层加了 `_DrawerBackGuard`（自行注册
/// PopEntry：抽屉开着时挡下返回并关抽屉）。
ChatState _state() => const ChatState(
      loading: false,
      running: false,
      conversationId: 'conv-1',
      messages: [],
    );

class _StaticChatController extends ChatController {
  @override
  ChatState build() => _state();
}

Future<ScaffoldState> _pumpChatPage(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [chatControllerProvider.overrideWith(_StaticChatController.new)],
    child: MaterialApp(theme: AppTheme.light(), home: const ChatPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
  await tester.pump(const Duration(milliseconds: 32));
  return tester.state<ScaffoldState>(find.byType(Scaffold).first);
}

/// 聊天页有常驻动效（玻璃质感、流式指示），pumpAndSettle 永远等不到静止，
/// 因此按消息长按测试的既有做法用显式短泵推进动画。路由退场动画在重页面下
/// 需要多帧才走完，这里多泵几帧，避免把动画中态误判成没退出。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('抽屉打开时系统返回键只关闭抽屉，页面留在栈内', (tester) async {
    final scaffold = await _pumpChatPage(tester);
    scaffold.openDrawer();
    await _settle(tester);
    expect(scaffold.isDrawerOpen, isTrue);
    expect(find.text('搜索最近对话...'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('抽屉关闭时系统返回键不误拦二级页面', (tester) async {
    await _pumpChatPage(tester);

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('二级页面')),
    ));
    await _settle(tester);
    expect(find.text('二级页面'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(find.text('二级页面'), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
