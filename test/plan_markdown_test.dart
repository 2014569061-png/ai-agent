import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/plan_markdown.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  group('parsePlanStepsFromMarkdown', () {
    test('解析编号、短横、星号与 checkbox 步骤', () {
      final steps = parsePlanStepsFromMarkdown('''
目标：重构登录模块

1. 抓取首页结构
2、修改鉴权接口
3) 写入数据库
- 补充错误处理
* 增加集成测试
- [ ] 通知用户完成
''');
      expect(steps.map((s) => s.description).toList(), [
        '抓取首页结构',
        '修改鉴权接口',
        '写入数据库',
        '补充错误处理',
        '增加集成测试',
        '通知用户完成',
      ]);
      expect(steps.map((s) => s.id).toList(),
          ['s1', 's2', 's3', 's4', 's5', 's6']);
      expect(steps.every((s) => s.status == 'pending'), isTrue);
    });

    test('无视说明行并容忍空行', () {
      final steps = parsePlanStepsFromMarkdown('''
目标：修 bug
这是一段说明文字

- 做一件事
''');
      expect(steps.single.description, '做一件事');
    });

    test('没有任何步骤时返回空列表', () {
      expect(parsePlanStepsFromMarkdown('   \n\n目标：空'), isEmpty);
    });
  });

  group('planStepsToMarkdown', () {
    test('渲染目标与编号步骤', () {
      final text = planStepsToMarkdown(
        goal: '重构登录模块',
        steps: const [
          PlanStep(id: 's1', description: '抓取首页结构'),
          PlanStep(id: 's2', description: '写入数据库'),
        ],
      );
      expect(text, '目标：重构登录模块\n\n1. 抓取首页结构\n2. 写入数据库');
    });

    test('渲染结果可被重新解析（忽略目标行）', () {
      const steps = [
        PlanStep(id: 's1', description: '第一步'),
        PlanStep(id: 's2', description: '第二步'),
      ];
      final text = planStepsToMarkdown(goal: '目标说明', steps: steps);
      final back = parsePlanStepsFromMarkdown(text);
      expect(back.length, 2);
      expect(back.first.description, '第一步');
    });

    test('无目标时只有编号步骤', () {
      final text = planStepsToMarkdown(
          steps: const [PlanStep(id: 's1', description: '唯一一步')]);
      expect(text, '1. 唯一一步');
    });
  });
}
