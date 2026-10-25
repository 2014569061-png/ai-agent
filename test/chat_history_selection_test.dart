import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

void main() {
  final messages = [
    ChatMessage(
        id: 'user',
        role: MessageRole.user,
        parts: [const MessagePart.text('alpha BRAVO charlie')]),
    ChatMessage(
        id: 'reply',
        role: MessageRole.assistant,
        parts: [const MessagePart.text('delta ECHO foxtrot')]),
  ];
  Widget app(Widget child, {bool desktop = true}) => MaterialApp(
        theme:
            desktop ? DesktopTheme.apply(ThemeData.light()) : ThemeData.light(),
        home: Scaffold(body: child),
      );
  Widget list(ScrollController scroll,
          {void Function(int, Offset)? onContextMenu}) =>
      ChatMessageList(
        messages: messages,
        sessionKey: 'selection',
        controller: scroll,
        running: false,
        onLongPress: (_) {},
        onRegenerate: () {},
        onContextMenu: onContextMenu,
      );

  testWidgets('desktop history shares one region while keeping action tooltips',
      (tester) async {
    final scroll = ScrollController();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(list(scroll)));
    await tester.pumpAndSettle();
    final tree = tester
        .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!
        .toStringDeep();
    expect(tree, contains('alpha BRAVO charlie'));
    expect(tree, contains('delta ECHO foxtrot'));
    semantics.dispose();
    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byTooltip('分享'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('shared selection copies both messages and survives list rebuild',
      (tester) async {
    final scroll = ScrollController();
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(app(list(scroll)));
    await tester.pumpAndSettle();
    final region =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed
        ?.call();
    await tester.pump();
    expect(copied, contains('alpha BRAVO charlie'));
    expect(copied, contains('delta ECHO foxtrot'));
    // Material copySelection clears the selection; select again before rebuild.
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    await tester.pumpWidget(app(list(scroll)));
    await tester.pump();
    expect(tester.state<SelectableRegionState>(find.byType(SelectableRegion)),
        same(region));
    copied = null;
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed
        ?.call();
    await tester.pump();
    expect(copied, contains('alpha BRAVO charlie'));
    expect(copied, contains('delta ECHO foxtrot'));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('mouse drag still selects and copies message text',
      (tester) async {
    final scroll = ScrollController();
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(app(list(scroll)));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('alpha BRAVO charlie'));
    final mouse = await tester.startGesture(
        Offset(rect.left + 1, rect.center.dy),
        kind: PointerDeviceKind.mouse);
    await mouse.moveTo(Offset(rect.right - 1, rect.center.dy));
    await mouse.up();
    await tester.pump();
    final region =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed
        ?.call();
    await tester.pump();
    expect(copied, contains('BRAVO'));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('right-click still dispatches to the correct message',
      (tester) async {
    final scroll = ScrollController();
    int? target;
    await tester.pumpWidget(
        app(list(scroll, onContextMenu: (index, _) => target = index)));
    await tester.pumpAndSettle();
    final mouse = await tester.startGesture(
        tester.getCenter(find.text('alpha BRAVO charlie')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(target, 0);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('standalone, inherited and mobile selection scopes remain valid',
      (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(app(SelectionArea(child: list(scroll))));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    await tester.pumpWidget(app(MessageBubble(
        message: messages.last,
        isLast: true,
        running: false,
        onLongPress: () {},
        onRegenerate: () {})));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(list(scroll), desktop: false));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsNothing);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
