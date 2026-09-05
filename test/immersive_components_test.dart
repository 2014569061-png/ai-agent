import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_empty_state.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/navigation/immersive_navigation_bar.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets(
      'immersive navigation renders four destinations and selected glow',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ImmersiveNavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (value) => selected = value,
          destinations: const [
            ImmersiveNavigationDestination(icon: Icons.chat, label: '对话'),
            ImmersiveNavigationDestination(icon: Icons.smart_toy, label: '智能体'),
            ImmersiveNavigationDestination(icon: Icons.history, label: '历史'),
            ImmersiveNavigationDestination(icon: Icons.settings, label: '设置'),
          ],
        ),
      ),
    ));
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat empty state accepts a suggestion without overflow',
      (tester) async {
    String? value;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ChatEmptyState(
          suggestions: const ['写一个页面/脚本', '总结这段文字'],
          onSuggestionTap: (text) => value = text,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('总结这段文字'));
    expect(value, '总结这段文字');
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant message bubble renders text and action controls',
      (tester) async {
    final message = ChatMessage(
      role: MessageRole.assistant,
      parts: const [MessagePart.text('你好，NEXUS')],
      modelName: '演示模型',
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MessageBubble(
          message: message,
          isLast: true,
          running: false,
          onLongPress: () {},
          onRegenerate: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('你好，NEXUS'), findsOneWidget);
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
