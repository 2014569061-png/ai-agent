import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/tts/tts_service.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/l10n/app_strings.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// G1（长按朗读）的可测面：
/// 1. 平台护栏 —— 非 Android 平台必须「不可用且不抛异常」，否则桌面/Web 会崩；
/// 2. 读屏动作 —— 只有助手气泡暴露朗读动作，且标签随朗读状态切换。
///
/// 真机朗读音质与引擎行为无法在单测覆盖，属 G2 真机回归项。

/// 子树内所有朗读类读屏动作的标签（「复制 / 重新生成」不在收集范围）。
List<String> _speakLabels(WidgetTester tester) {
  const wanted = {AppStrings.speakAloud, AppStrings.stopSpeaking};
  final labels = <String>[];
  void collect(SemanticsNode node) {
    final ids = node.getSemanticsData().customSemanticsActionIds;
    for (final id in ids ?? const <int>[]) {
      final label = CustomSemanticsAction.getAction(id)?.label;
      if (label != null && wanted.contains(label)) labels.add(label);
    }
    node.visitChildren((child) {
      collect(child);
      return true;
    });
  }

  collect(tester.getSemantics(find.byType(Scaffold)));
  return labels;
}

ChatMessage _message(MessageRole role, String text) =>
    ChatMessage(role: role, parts: [MessagePart.text(text)]);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  ));
  // 气泡正文可能延后一帧才解析 Markdown，多泵两帧让语义树稳定。
  await tester.pump();
  await tester.pump();
}

void main() {
  group('TtsService 平台护栏', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('桌面平台不可用：isAvailable=false，speak 返回 false 且不抛异常', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final tts = TtsService.instance;
      expect(tts.isAvailable, isFalse);
      expect(await tts.speak('你好'), isFalse);
      expect(tts.isSpeaking, isFalse);
      expect(tts.speakingListenable.value, isFalse);
    });

    test('stop 幂等，未朗读时调用无副作用', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final tts = TtsService.instance;
      await tts.stop();
      await tts.stop();
      expect(tts.isSpeaking, isFalse);
    });

    test('空白文本不视为可朗读内容（不触碰平台通道）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await TtsService.instance.speak('  \n\t '), isFalse);
    });
  });

  group('气泡朗读读屏动作', () {
    testWidgets('暴露朗读动作，并在朗读中切换为停止朗读', (tester) async {
      // 语义句柄必须在测试体内显式释放：tearDown 阶段晚于框架的句柄校验。
      final handle = tester.ensureSemantics();
      final speaking = ValueNotifier<bool>(false);
      addTearDown(speaking.dispose);

      await _pump(
        tester,
        MessageBubble(
          message: _message(MessageRole.assistant, '你好，NEXUS'),
          isLast: true,
          running: false,
          onLongPress: () {},
          onRegenerate: () {},
          onSpeak: () {},
          speakingListenable: speaking,
        ),
      );
      expect(_speakLabels(tester), [AppStrings.speakAloud]);

      speaking.value = true;
      await tester.pump();
      expect(_speakLabels(tester), [AppStrings.stopSpeaking]);
      handle.dispose();
    });

    testWidgets('未提供朗读回调时不暴露该动作', (tester) async {
      final handle = tester.ensureSemantics();

      await _pump(
        tester,
        MessageBubble(
          message: _message(MessageRole.assistant, '你好，NEXUS'),
          isLast: true,
          running: false,
          onLongPress: () {},
          onRegenerate: () {},
        ),
      );
      expect(_speakLabels(tester), isEmpty);
      handle.dispose();
    });

    testWidgets('消息列表中只有助手气泡带朗读动作', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = ScrollController();
      final speaking = ValueNotifier<bool>(false);
      addTearDown(controller.dispose);
      addTearDown(speaking.dispose);

      await _pump(
        tester,
        ChatMessageList(
          messages: [
            _message(MessageRole.user, '问题'),
            _message(MessageRole.assistant, '回答'),
            _message(MessageRole.tool, '工具结果'),
          ],
          controller: controller,
          running: false,
          onLongPress: (_) {},
          onRegenerate: () {},
          onSpeak: (_) {},
          speakingListenable: speaking,
        ),
      );
      expect(_speakLabels(tester), [AppStrings.speakAloud]);
      handle.dispose();
    });
  });
}
