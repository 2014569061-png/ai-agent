import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/share/deep_link_service.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

class _ControlledChat extends ChatController {
  _ControlledChat({this.loading = false});
  final bool loading;
  int newChats = 0;

  @override
  ChatState build() =>
      ChatState(loading: loading, conversationId: 'original', messages: [
        ChatMessage(
            id: 'existing-message',
            role: MessageRole.assistant,
            parts: [const MessagePart.text('existing history')])
      ]);

  void finishRestore() => state = state.copyWith(loading: false);

  @override
  Future<void> newConversation() async {
    newChats++;
    state = state.copyWith(
      conversationId: 'link-chat-$newChats',
      conversationTitle: 'link chat',
      loading: false,
      restoringConversation: false,
      messages: [],
      mode: ChatMode.chat,
    );
  }
}

Future<void> _pumpChat(WidgetTester tester, _ControlledChat controller) async {
  SharedPreferences.setMockInitialValues({});
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const ChatPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
}

Iterable<String> _drafts(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .map((field) => field.controller.text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final links = DeepLinkService.instance;
  setUp(links.reset);
  tearDown(links.reset);

  testWidgets('cold pending link waits for restored controller before prefill',
      (tester) async {
    links.handleUri(Uri.parse('nexus://new-chat?prompt=cold%20draft'));
    final controller = _ControlledChat(loading: true);
    await _pumpChat(tester, controller);
    expect(controller.newChats, 0);
    expect(links.hasPending, isTrue);
    controller.finishRestore();
    await _settle(tester);
    expect(controller.newChats, 1);
    expect(_drafts(tester), contains('cold draft'));
    expect(links.hasPending, isFalse);
    expect(find.text('existing history'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late cold or warm link is delivered to an already mounted page',
      (tester) async {
    final controller = _ControlledChat();
    await _pumpChat(tester, controller);
    links.handleUri(Uri.parse('nexus://new-chat?prompt=warm%20draft'));
    await _settle(tester);
    expect(controller.newChats, 1);
    expect(_drafts(tester), contains('warm draft'));
    expect(find.text('existing history'), findsNothing);
    expect(find.byKey(const ValueKey('back_to_latest')), findsNothing);
    // Prefill must never send: the new conversation still has no messages.
    final context = tester.element(find.byType(ChatPage));
    expect(
        ProviderScope.containerOf(context)
            .read(chatControllerProvider)
            .messages,
        isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('new-chat without prompt still opens a new empty conversation',
      (tester) async {
    final controller = _ControlledChat();
    await _pumpChat(tester, controller);
    links.handleUri(Uri.parse('nexus://new-chat'));
    await _settle(tester);
    expect(controller.newChats, 1);
    expect(_drafts(tester), everyElement(isEmpty));
    expect(find.text('existing history'), findsNothing);
    expect(links.hasPending, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unsupported links neither change chats nor replace drafts',
      (tester) async {
    final controller = _ControlledChat();
    await _pumpChat(tester, controller);
    links.handleUri(Uri.parse('nexus://unsupported?prompt=ignored'));
    await _settle(tester);
    expect(controller.newChats, 0);
    expect(find.text('existing history'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposed page stops consuming links and next page drains them',
      (tester) async {
    final first = _ControlledChat();
    await _pumpChat(tester, first);
    await tester.pumpWidget(const SizedBox.shrink());
    links.handleUri(Uri.parse('nexus://new-chat?prompt=next%20page'));
    await _settle(tester);
    expect(first.newChats, 0);
    expect(links.hasPending, isTrue);
    final second = _ControlledChat();
    await _pumpChat(tester, second);
    await _settle(tester);
    expect(second.newChats, 1);
    expect(_drafts(tester), contains('next page'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
