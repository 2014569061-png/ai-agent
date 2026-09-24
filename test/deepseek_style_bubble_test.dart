import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/mascot_avatar.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// DeepSeek 式聊天排版回归：AI 回复无头像 / 卡片 / 标题，模型名与耗时在操作行
/// 右侧弱化显示；用户气泡浅色无描边。
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(390, 900), disableAnimations: true),
      child: NexusMotionScope(
        level: MotionLevel.off,
        child: Scaffold(body: ListView(children: [child])),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('assistant reply is plain text with a muted meta action row',
      (tester) async {
    var regenerated = false;
    await _pump(
      tester,
      MessageBubble(
        message: ChatMessage(
          role: MessageRole.assistant,
          modelName: 'deepseek-chat',
          elapsed: const Duration(milliseconds: 3200),
          parts: [const MessagePart.text('这是一段回答。')],
        ),
        isLast: true,
        running: false,
        onLongPress: () {},
        onRegenerate: () => regenerated = true,
        onSpeak: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MascotAvatar), findsNothing);
    expect(find.text('NEXUS AI'), findsNothing);
    expect(find.text('deepseek-chat · 3.2s'), findsOneWidget);
    for (final tooltip in ['复制', '朗读', '分享', '重新生成']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    // 元信息在操作行右侧：占满分享与重新生成之间的空间并右对齐。
    final meta = tester.getRect(find.byKey(const ValueKey('reply-meta')));
    expect(meta.left,
        greaterThanOrEqualTo(tester.getRect(find.byTooltip('分享')).right));
    expect(meta.right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('重新生成')).left));
    final metaText =
        tester.widget<Text>(find.byKey(const ValueKey('reply-meta')));
    expect(metaText.textAlign, TextAlign.end);

    await tester.tap(find.byTooltip('重新生成'));
    expect(regenerated, isTrue);
  });

  testWidgets('older replies keep copy and share but not regenerate',
      (tester) async {
    await _pump(
      tester,
      MessageBubble(
        message: ChatMessage(
          role: MessageRole.assistant,
          parts: [const MessagePart.text('旧回答')],
        ),
        isLast: false,
        running: false,
        onLongPress: () {},
        onRegenerate: () {},
      ),
    );
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byTooltip('分享'), findsOneWidget);
    expect(find.byTooltip('重新生成'), findsNothing);
    expect(find.byTooltip('朗读'), findsNothing, reason: '平台不支持朗读时不显示');
    expect(find.byKey(const ValueKey('reply-meta')), findsNothing);
  });

  testWidgets('user bubble has a soft fill and no border', (tester) async {
    await _pump(
      tester,
      MessageBubble(
        message: ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('你好')],
        ),
        isLast: false,
        running: false,
        onLongPress: () {},
        onRegenerate: () {},
      ),
    );
    final bubble = tester.widget<Container>(find
        .ancestor(of: find.text('你好'), matching: find.byType(Container))
        .first);
    final decoration = bubble.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
    expect(decoration.color, isNotNull);
    expect(
      decoration.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(6),
      ),
    );
  });
}
