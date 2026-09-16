import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/chat/widgets/plan_panel.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

class _ActivityDockController extends ChatController {
  @override
  ChatState build() => ChatState(
        loading: false,
        running: false,
        conversationId: 'dock-test',
        messages: [
          ChatMessage(
            role: MessageRole.user,
            parts: [const MessagePart.text('请执行这项任务')],
          ),
          ChatMessage(
            role: MessageRole.assistant,
            parts: [const MessagePart.text('已收到')],
          ),
        ],
        planState: const PlanState(
          status: 'draft',
          steps: [PlanStep(id: 'step-1', description: '检查当前工作区')],
        ),
        toolActivities: const [
          ToolActivity(
            call: ToolCall(
              id: 'tool-1',
              name: 'terminal',
              arguments: {'command': 'pwd'},
            ),
            risk: ToolRisk.safe,
            status: '执行失败',
            ok: false,
            effect: ToolEffect.none,
          ),
        ],
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('activity dock sits above messages instead of at list tail',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith(_ActivityDockController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    final dock =
        tester.getRect(find.byKey(const ValueKey('chat_activity_dock')));
    final list = tester.getRect(find.byType(ChatMessageList));

    expect(dock.bottom, lessThanOrEqualTo(list.top + 1));
    expect(find.byType(PlanPanel), findsOneWidget);
    expect(find.text('1 项未完成，查看原因（点击展开）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
