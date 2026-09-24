import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/chat_scroll_coordinator.dart';

List<ChatMessage> _messages(int count, {String prefix = 'm'}) => List.generate(
    count,
    (i) => ChatMessage(
          id: '$prefix-$i',
          role: MessageRole.assistant,
          parts: [MessagePart.text('$prefix-$i')],
        ));

Future<void> _pumpList(WidgetTester tester, ChatScrollCoordinator scroll,
    List<ChatMessage> messages,
    {double itemHeight = 80}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(
    child: SizedBox(
      width: 400,
      height: 240,
      child: NotificationListener<Notification>(
        onNotification: scroll.handleNotification,
        child: ListView(
          controller: scroll.controller,
          children: [
            for (final message in messages)
              SizedBox(height: itemHeight, child: Text(message.text))
          ],
        ),
      ),
    ),
  ))));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScrollController controller;
  late ChatScrollCoordinator scroll;
  setUp(() {
    controller = ScrollController();
    scroll = ChatScrollCoordinator(controller, isRunning: () => false);
  });
  tearDown(() {
    scroll.dispose();
    controller.dispose();
  });

  testWidgets('unattached and first-layout short messages are not unread',
      (tester) async {
    final messages = _messages(2);
    scroll.messagesChanged(
        previous: [],
        next: messages,
        resetSession: false,
        running: false,
        completed: false);
    expect(controller.hasClients, isFalse);
    expect(scroll.isNearBottom, isTrue);
    expect(scroll.unreadCount, 0);
    await _pumpList(tester, scroll, messages);
    expect(scroll.unreadCount, 0);
    expect(scroll.showScrollToBottom, isFalse);
  });

  testWidgets('append while away counts once; manually reaching tail clears it',
      (tester) async {
    final messages = _messages(30);
    scroll.reset();
    await _pumpList(tester, scroll, messages);
    controller.jumpTo(0);
    final next = [...messages, ..._messages(1, prefix: 'new')];
    scroll.messagesChanged(
        previous: messages,
        next: next,
        resetSession: false,
        running: false,
        completed: false);
    await _pumpList(tester, scroll, next);
    expect(scroll.showScrollToBottom, isTrue);
    expect(scroll.unreadCount, 1);
    expect(controller.offset, 0);
    controller.jumpTo(controller.position.maxScrollExtent);
    expect(scroll.showScrollToBottom, isFalse);
    expect(scroll.unreadCount, 0);
  });

  testWidgets('history prepend is not a new message', (tester) async {
    final messages = _messages(30);
    await _pumpList(tester, scroll, messages);
    final previousPage = _messages(10, prefix: 'older');
    scroll.messagesChanged(
        previous: messages,
        next: [...previousPage, ...messages],
        resetSession: false,
        running: false,
        completed: false);
    expect(scroll.unreadCount, 0);
  });

  testWidgets(
      'session change clears unread and cannot leak counts to next chat',
      (tester) async {
    final messages = _messages(30);
    await _pumpList(tester, scroll, messages);
    final next = [...messages, ..._messages(1, prefix: 'new')];
    scroll.messagesChanged(
        previous: messages,
        next: next,
        resetSession: false,
        running: false,
        completed: false);
    expect(scroll.unreadCount, 1);
    final other = _messages(2, prefix: 'other');
    scroll.messagesChanged(
        previous: next,
        next: other,
        resetSession: true,
        running: false,
        completed: false);
    await _pumpList(tester, scroll, other);
    expect(scroll.unreadCount, 0);
    expect(scroll.showScrollToBottom, isFalse);
  });

  testWidgets('a large append follows the pre-layout tail', (tester) async {
    final messages = _messages(2);
    await _pumpList(tester, scroll, messages);
    final next = [...messages, ..._messages(8, prefix: 'new')];
    scroll.messagesChanged(
        previous: messages,
        next: next,
        resetSession: false,
        running: true,
        completed: false);
    await _pumpList(tester, scroll, next);
    expect(controller.position.extentAfter, lessThan(2));
    expect(scroll.unreadCount, 0);
    expect(scroll.showScrollToBottom, isFalse);
  });

  testWidgets('shrinking content clears badge even without user scrolling',
      (tester) async {
    final messages = _messages(30);
    await _pumpList(tester, scroll, messages);
    final next = [...messages, ..._messages(1, prefix: 'new')];
    scroll.messagesChanged(
        previous: messages,
        next: next,
        resetSession: false,
        running: false,
        completed: false);
    expect(scroll.unreadCount, 1);
    await _pumpList(tester, scroll, next, itemHeight: 1);
    expect(scroll.unreadCount, 0);
    expect(scroll.showScrollToBottom, isFalse);
  });

  testWidgets('stale post-frame tail follow does not affect a replaced session',
      (tester) async {
    final first = _messages(2);
    await _pumpList(tester, scroll, first);
    scroll.messagesChanged(
        previous: first,
        next: [...first, ..._messages(15, prefix: 'new')],
        resetSession: false,
        running: true,
        completed: false);
    scroll.reset();
    await _pumpList(tester, scroll, _messages(1, prefix: 'other'));
    expect(scroll.unreadCount, 0);
    expect(scroll.showScrollToBottom, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('same-length streaming changes and range replacement are not append',
      () {
    final previous = _messages(2);
    final streamed = [...previous]..[1] =
        previous[1].copyWith(parts: [const MessagePart.text('updated text')]);
    expect(ChatScrollCoordinator.appendedCount(previous, streamed), 0);
    expect(
        ChatScrollCoordinator.appendedCount(
            previous, _messages(3, prefix: 'replacement')),
        0);
    expect(
        ChatScrollCoordinator.appendedCount(
            previous, [...streamed, ..._messages(1, prefix: 'tail')]),
        1);
  });
}
