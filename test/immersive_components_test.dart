import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_empty_state.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/navigation/immersive_navigation_bar.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/brand_mark.dart';

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

  testWidgets('chat empty state renders only brand mark and greeting',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: ChatEmptyState()),
    ));
    await tester.pumpAndSettle();

    // 对标 DeepSeek 首页：只有品牌 Logo + 一句问候，
    // 不再渲染起点建议卡（问候语从随机池中抽取，故用正则匹配）。
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.textContaining(RegExp(r'[？吧]$')), findsOneWidget);

    // 起点建议卡已移除
    expect(find.text('总结这段文字'), findsNothing);
    expect(find.text('写一个页面/脚本'), findsNothing);
    expect(find.text('直接输入需求，或试试这些起点建议'), findsNothing);

    // 小屏下不应出现溢出
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat empty state has no overflow on a short viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: ChatEmptyState()),
    ));
    await tester.pumpAndSettle();

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

  testWidgets('long assistant reply defers Markdown parsing by one frame',
      (tester) async {
    final longText = 'plain text **bold**\n' * 450;
    final message = ChatMessage(
      role: MessageRole.assistant,
      parts: [MessagePart.text(longText)],
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MessageBubble(
            message: message,
            isLast: true,
            running: false,
            onLongPress: () {},
            onRegenerate: () {},
          ),
        ),
      ),
    ));

    // 延迟帧的占位必须是**普通 Text**：占位若用 SelectableText，长按会被文本选择器
    // 截走，长消息这一类气泡的消息菜单就会时灵时不灵（见 message_longpress_test.dart）。
    expect(find.byType(Text), findsWidgets);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(MarkdownBody), findsNothing);

    await tester.pump();
    await tester.pump();
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
