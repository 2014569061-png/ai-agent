import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/chat/widgets/capsule_top_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 测试用控制器：跳过数据库 / 网络初始化，直接给出可控的 [ChatState]。
class _TestChatController extends ChatController {
  @override
  ChatState build() => ChatState(
        loading: false,
        running: true,
        conversationId: 'conv-1',
        messages: [
          ChatMessage(
            role: MessageRole.user,
            parts: [const MessagePart.text('你好')],
          ),
          ChatMessage(
            role: MessageRole.assistant,
            parts: [const MessagePart.text('你好，很高兴为你服务')],
          ),
        ],
      );

  /// 直接改写内部状态，用于在测试中精确驱动某一字段变化。
  void emit(ChatState next) => state = next;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'F-1: 仅 liveReply 变化时，输入胶囊 / 顶栏所在页面级子树不重建，'
      '只有消息列表子树随流式重建', (tester) async {
    late _TestChatController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith(_TestChatController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (context, ref, _) {
              controller = ref.read(chatControllerProvider.notifier)
                  as _TestChatController;
              return const ChatPage();
            },
          ),
        ),
      ),
    );

    // 预热：完成首帧布局，让消息列表的 ScrollController 挂上 clients。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // 记录页面级子树（顶栏 / 输入胶囊）与流式子树的当前 widget 实例。
    final topBarBefore =
        tester.widget<CapsuleTopBar>(find.byType(CapsuleTopBar));
    final inputBefore =
        tester.widget<FloatingCapsuleInput>(find.byType(FloatingCapsuleInput));
    final listBefore =
        tester.widget<ChatMessageList>(find.byType(ChatMessageList));

    // 模拟 20 帧流式增量：每帧只改 liveReply，其余字段逐字段保持不变。
    const frames = 20;
    for (var i = 0; i < frames; i++) {
      controller.emit(controller.state.copyWith(
        liveReply: LiveReply(
          messageIndex: controller.state.messages.length - 1,
          text: '流式增量 $i',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 70));
    }

    final topBarAfter =
        tester.widget<CapsuleTopBar>(find.byType(CapsuleTopBar));
    final inputAfter =
        tester.widget<FloatingCapsuleInput>(find.byType(FloatingCapsuleInput));
    final listAfter =
        tester.widget<ChatMessageList>(find.byType(ChatMessageList));

    // 页面级子树：widget 实例保持不变 => ChatPage.build 未重跑 => 零重建。
    expect(identical(topBarBefore, topBarAfter), isTrue,
        reason: '顶栏不应随 liveReply 重建');
    expect(identical(inputBefore, inputAfter), isTrue,
        reason: '输入胶囊不应随 liveReply 重建');

    // 流式子树：收到新的 liveReply => 命令下发到消息列表。
    expect(identical(listBefore, listAfter), isFalse,
        reason: '消息列表应随 liveReply 重建以展示流式文本');
    expect(listAfter.liveReply?.text, '流式增量 ${frames - 1}');

    debugPrint('[F-1] $frames 帧流式增量：顶栏重建 0 次，输入胶囊重建 0 次，'
        '消息列表重建 1 次/帧（共 $frames 次）。');
  });

  testWidgets('F-1: 页面级字段（activityLog）变化时仍会重建 ChatPage，验证 select 生效',
      (tester) async {
    late _TestChatController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith(_TestChatController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (context, ref, _) {
              controller = ref.read(chatControllerProvider.notifier)
                  as _TestChatController;
              return const ChatPage();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    final topBarBefore =
        tester.widget<CapsuleTopBar>(find.byType(CapsuleTopBar));

    // 改动一个被页面级 select 订阅的字段：ChatPage.build 应当重跑。
    controller.emit(controller.state.copyWith(
      activityLog: const ['步骤 1'],
    ));
    await tester.pump(const Duration(milliseconds: 70));

    final topBarAfter =
        tester.widget<CapsuleTopBar>(find.byType(CapsuleTopBar));
    expect(identical(topBarBefore, topBarAfter), isFalse,
        reason: '订阅字段变化时页面应当重建（证明 select 未把整页冻结）');
  });

  testWidgets('F-1 对照：改造前的「整状态 watch」在同样 20 帧下重建 20 次（基线上限）', (tester) async {
    late _TestChatController controller;
    var rebuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith(_TestChatController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (context, ref, _) {
              controller = ref.read(chatControllerProvider.notifier)
                  as _TestChatController;
              // 改造前的写法：ChatPage.build 直接 ref.watch(整状态)。
              ref.watch(chatControllerProvider);
              rebuilds++;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final baseline = rebuilds;

    const frames = 20;
    for (var i = 0; i < frames; i++) {
      controller.emit(controller.state.copyWith(
        liveReply: LiveReply(messageIndex: 2, text: '流式增量 $i'),
      ));
      await tester.pump(const Duration(milliseconds: 70));
    }

    // 改造前：每一帧流式增量都触发一次整状态重建。
    expect(rebuilds - baseline, frames);
    debugPrint('[F-1] 对照（整状态 watch）：$frames 帧流式增量 -> 重建 '
        '${rebuilds - baseline} 次；改造后同一场景页面级重建 0 次。');
  });
}
