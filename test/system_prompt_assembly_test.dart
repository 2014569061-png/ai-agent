import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/system_prompt_assembly.dart';

void main() {
  group('assembleAgentSystemPrompt', () {
    test('stable sections precede dynamic sections', () {
      final prompt = assembleAgentSystemPrompt(
        personaPrompt: '人格',
        skillIndexBlock: '技能索引',
        sessionSkillBlocks: const ['会话技能'],
        delegationRules: '委派规则',
        workspaceRules: '工作区规则',
        memoryBlock: '长期记忆',
        knowledgeBlock: '知识片段',
      );

      expect(
        prompt,
        '人格\n\n技能索引\n\n会话技能\n\n委派规则\n\n工作区规则\n\n长期记忆\n\n知识片段',
      );
    });

    test('knowledge retrieval block stays last across turns', () {
      // 知识库片段按当前问题检索、每轮都不同，必须垫底；记忆 revision
      // 次之。稳定段在前保证跨轮请求的前缀一致，前缀缓存才能命中。
      final first = assembleAgentSystemPrompt(
        personaPrompt: 'P',
        memoryBlock: 'M1',
        knowledgeBlock: 'K1',
      );
      final second = assembleAgentSystemPrompt(
        personaPrompt: 'P',
        memoryBlock: 'M1',
        knowledgeBlock: 'K2',
      );

      expect(first.startsWith('P\n\nM1'), isTrue);
      expect(second.startsWith('P\n\nM1'), isTrue);
      expect(first.endsWith('K1'), isTrue);
      expect(second.endsWith('K2'), isTrue);
    });

    test('empty sections are skipped', () {
      final prompt = assembleAgentSystemPrompt(
        personaPrompt: '人格',
        knowledgeBlock: '知识片段',
      );

      expect(prompt, '人格\n\n知识片段');
    });

    test('all empty yields empty prompt', () {
      expect(assembleAgentSystemPrompt(), '');
    });
  });
}
