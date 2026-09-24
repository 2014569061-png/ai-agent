import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/widgets/conversation_restore_skeleton.dart';

void main() {
  testWidgets('announces conversation restoration while showing skeleton',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ConversationRestoreSkeleton()),
    ));

    expect(find.text('正在恢复会话…'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('正在恢复会话')), findsOneWidget);
    semantics.dispose();
  });
}
