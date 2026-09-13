import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/chat/composer_skill_slot.dart';
import 'package:mobile_agent/presentation/chat/widgets/session_metrics_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/skill_suggestion_bar.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

ChatState _state({
  required bool running,
  required List<SessionSkillInstruction> skills,
}) =>
    ChatState(
      loading: false,
      running: running,
      conversationId: 'conv-1',
      totalSteps: 3,
      messages: [
        ChatMessage(
          role: MessageRole.user,
          parts: [const MessagePart.text('你好')],
        ),
        ChatMessage(
          role: MessageRole.assistant,
          parts: [const MessagePart.text('你好，很高兴为你服务')],
          elapsed: const Duration(seconds: 8),
          ttft: const Duration(seconds: 3),
          usage: const Usage(promptTokens: 1000, completionTokens: 500),
        ),
      ],
      sessionSkillInstructions: skills,
    );

const _loadedSkill = SessionSkillInstruction(
  id: 'build',
  name: 'build',
  content: '## build\n\nrun gradle',
);

class _IdleWithLoadedSkill extends ChatController {
  @override
  ChatState build() => _state(running: false, skills: const [_loadedSkill]);
}

class _RunningWithLoadedSkill extends ChatController {
  @override
  ChatState build() => _state(running: true, skills: const [_loadedSkill]);
}

Future<void> _pumpChatPage(
  WidgetTester tester,
  ChatController Function() controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatControllerProvider.overrideWith(controller)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ChatPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
}

/// 输入区上方的技能类横条总数。改造前三条可同时出现（3×44dp）。
int _skillBarCount(WidgetTester tester) =>
    tester.widgetList(find.byType(LoadedSkillBar)).length +
    tester.widgetList(find.byType(SlashSkillReferenceBar)).length +
    tester.widgetList(find.byType(SkillSuggestionBar)).length;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resolveComposerSkillSlot：技能提示槽位优先级', () {
    test('运行中一律不出技能提示，即使三类条件同时成立', () {
      expect(
        resolveComposerSkillSlot(
          running: true,
          hasSlashMatches: true,
          hasSuggestions: true,
          hasLoadedSkills: true,
        ),
        ComposerSkillSlot.none,
      );
    });

    test('/ 补全优先于自动建议（否则打「/rea」会被建议顶掉补全）', () {
      expect(
        resolveComposerSkillSlot(
          running: false,
          hasSlashMatches: true,
          hasSuggestions: true,
          hasLoadedSkills: true,
        ),
        ComposerSkillSlot.slash,
      );
    });

    test('无 / 补全时优先自动建议', () {
      expect(
        resolveComposerSkillSlot(
          running: false,
          hasSlashMatches: false,
          hasSuggestions: true,
          hasLoadedSkills: true,
        ),
        ComposerSkillSlot.suggestion,
      );
    });

    test('只有已加载技能时退回 loaded', () {
      expect(
        resolveComposerSkillSlot(
          running: false,
          hasSlashMatches: false,
          hasSuggestions: false,
          hasLoadedSkills: true,
        ),
        ComposerSkillSlot.loaded,
      );
    });

    test('三类都为空则不出提示', () {
      expect(
        resolveComposerSkillSlot(
          running: false,
          hasSlashMatches: false,
          hasSuggestions: false,
          hasLoadedSkills: false,
        ),
        ComposerSkillSlot.none,
      );
    });
  });

  group('ChatPage 输入区：技能条不超过一条', () {
    testWidgets('已加载会话技能时，只渲染一条技能条', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester, _IdleWithLoadedSkill.new);

      expect(find.byType(LoadedSkillBar), findsOneWidget);
      expect(
        _skillBarCount(tester),
        1,
        reason: '同类技能提示必须共用一个槽位，改造前最多可同时出现 3 条',
      );
      expect(find.text('build'), findsOneWidget);
    });

    testWidgets('运行中不渲染技能条与独立运行状态卡', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester, _RunningWithLoadedSkill.new);

      expect(_skillBarCount(tester), 0);
    });

    testWidgets('运行中指标条收窄为 2 组，让出输入区上方空间', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester, _RunningWithLoadedSkill.new);

      expect(
        tester
            .widget<SessionMetricsBar>(find.byType(SessionMetricsBar))
            .maxGroups,
        2,
        reason: '运行中输入区自带状态行，指标条应收窄避免叠加占高',
      );
    });

    testWidgets('空闲时指标条不收缩（保留完整信息）', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpChatPage(tester, _IdleWithLoadedSkill.new);

      expect(
        tester
            .widget<SessionMetricsBar>(find.byType(SessionMetricsBar))
            .maxGroups,
        isNull,
      );
    });
  });
}
