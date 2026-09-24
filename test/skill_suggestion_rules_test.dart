// 技能建议选择规则：/ 补全候选、意图建议触发条件、去重比较。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/skill_suggestion_rules.dart';

class _Skill {
  const _Skill(this.id, this.name);
  final String id;
  final String name;
}

void main() {
  const build = _Skill('build', 'build');
  const deploy = _Skill('deploy', 'deploy');
  const buildTools = _Skill('build-tools', 'build-tools');

  group('selectSlashSkillSuggestions', () {
    List<_Skill> select(
      String? query, {
      Set<String> loaded = const {},
      List<_Skill> skills = const [build, deploy, buildTools],
    }) =>
        selectSlashSkillSuggestions<_Skill>(
          skills: skills,
          query: query,
          nameOf: (item) => item.name,
          isLoaded: (item) => loaded.contains(item.id),
        );

    test('query 为 null 时没有候选', () {
      expect(select(null), isEmpty);
    });

    test('空 query（刚敲下 /）列出全部未加载候选', () {
      expect(select('').map((s) => s.id), ['build', 'deploy', 'build-tools']);
    });

    test('按前缀过滤', () {
      expect(select('bu').map((s) => s.id), ['build', 'build-tools']);
    });

    test('排除已加载的技能', () {
      expect(select('bu', loaded: {'build'}).map((s) => s.id), ['build-tools']);
    });

    test('无匹配时为空白列表', () {
      expect(select('zzz'), isEmpty);
    });

    test('最多 5 条', () {
      final many = [
        for (var i = 0; i < 9; i++) _Skill('s$i', 'skill$i'),
      ];
      final result = select('', skills: many);
      expect(result, hasLength(maxSlashSkillSuggestions));
    });

    test('恰好 5 条时不截断', () {
      final five = [
        for (var i = 0; i < 5; i++) _Skill('s$i', 'skill$i'),
      ];
      expect(select('', skills: five), hasLength(5));
    });

    test('保持原有顺序', () {
      expect(select('', skills: const [deploy, build]).map((s) => s.id),
          ['deploy', 'build']);
    });
  });

  group('shouldOfferIntentSkillSuggestions', () {
    test('两个字符起才给建议', () {
      expect(shouldOfferIntentSkillSuggestions(input: 'ab', dismissed: false),
          isTrue);
    });

    test('单个字符不给', () {
      expect(shouldOfferIntentSkillSuggestions(input: 'a', dismissed: false),
          isFalse);
    });

    test('空输入不给', () {
      expect(shouldOfferIntentSkillSuggestions(input: '', dismissed: false),
          isFalse);
    });

    test('用户已关闭提示时不给（即使输入够长）', () {
      expect(
        shouldOfferIntentSkillSuggestions(input: '帮我构建', dismissed: true),
        isFalse,
      );
    });

    test('中文按字符长度计数', () {
      expect(shouldOfferIntentSkillSuggestions(input: '构建', dismissed: false),
          isTrue);
    });
  });

  group('sameSkillSuggestionOrder', () {
    bool same(List<_Skill> a, List<_Skill> b) =>
        sameSkillSuggestionOrder<_Skill>(a, b, idOf: (item) => item.id);

    test('完全相同时为真', () {
      expect(same(const [build, deploy], const [build, deploy]), isTrue);
    });

    test('长度不同为假', () {
      expect(same(const [build], const [build, deploy]), isFalse);
    });

    test('顺序不同为假（顺序即展示顺序）', () {
      expect(same(const [build, deploy], const [deploy, build]), isFalse);
    });

    test('同名但不同实例、id 相同视为相同', () {
      expect(same(const [_Skill('a', 'x')], const [_Skill('a', 'x')]), isTrue);
    });

    test('两个空列表相同（用于跳过首次重建）', () {
      expect(same(const [], const []), isTrue);
    });
  });
}