import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('ChatMessageList resets window when sessionKey changes',
      (tester) async {
    final scrollController = ScrollController();
    final messages1 = List.generate(
      50,
      (i) => ChatMessage(
        role: MessageRole.user,
        parts: [MessagePart.text('Session 1 Msg $i')],
      ),
    );

    final messages2 = List.generate(
      50,
      (i) => ChatMessage(
        role: MessageRole.user,
        parts: [MessagePart.text('Session 2 Msg $i')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChatMessageList(
            sessionKey: 'conv-1',
            messages: messages1,
            controller: scrollController,
            running: false,
            onLongPress: (_) {},
            onRegenerate: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // With 50 messages and initialWindow=40, starts at index 10
    expect(find.text('Session 1 Msg 10'), findsOneWidget);

    // Now update widget with sessionKey 'conv-2'
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChatMessageList(
            sessionKey: 'conv-2',
            messages: messages2,
            controller: scrollController,
            running: false,
            onLongPress: (_) {},
            onRegenerate: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify session 2 messages are shown and starts at index 10 of session 2
    expect(find.text('Session 2 Msg 10'), findsOneWidget);
    expect(find.text('Session 1 Msg 10'), findsNothing);
  });
}
