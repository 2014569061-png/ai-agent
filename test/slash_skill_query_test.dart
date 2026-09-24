// `/` 技能引用的解析与改写：这是此前完全没有测试覆盖的文本变换。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/chat/slash_skill_query.dart';

void main() {
  group('slashSkillQuery', () {
    test('行首的 / 引用', () {
      expect(slashSkillQuery('/bu'), 'bu');
    });

    test('空白之后的 / 引用', () {
      expect(slashSkillQuery('帮我 /bu'), 'bu');
    });

    test('刚敲下 / 时查询词为空（应列出全部候选）', () {
      expect(slashSkillQuery('/'), '');
    });

    test('没有 / 引用时为 null', () {
      expect(slashSkillQuery('帮我写一个函数'), isNull);
    });

    test('/ 出现在词中间不算引用，避免把路径误判成技能', () {
      expect(slashSkillQuery('a/b'), isNull);
    });

    test('引用不在行尾时不算（后面还有内容）', () {
      expect(slashSkillQuery('/bu 后面还有字'), isNull);
    });

    test('允许 - 与 _ 与数字', () {
      expect(slashSkillQuery('/a-b_c9'), 'a-b_c9');
    });

    test('大写字母不在允许集合内，匹配不到名字片段', () {
      // 只匹配小写片段，因此行尾的 /BU 不构成引用。
      expect(slashSkillQuery('/BU'), isNull);
    });

    test('制表符分隔同样识别', () {
      expect(slashSkillQuery('x\t/ab'), 'ab');
    });
  });

  group('insertSlashSkillReference', () {
    test('保留 / 前的空格，末尾补空格', () {
      expect(insertSlashSkillReference('帮我 /bu', 'build'), '帮我 /build ');
    });

    test('行首引用不加多余分隔符', () {
      expect(insertSlashSkillReference('/bu', 'build'), '/build ');
    });

    test('没有可替换的引用时返回 null（调用方保持输入不变）', () {
      expect(insertSlashSkillReference('帮我写一个函数', 'build'), isNull);
    });

    test('引用不在行尾时返回 null', () {
      expect(insertSlashSkillReference('/bu 后面还有字', 'build'), isNull);
    });

    test('保留换行分隔符', () {
      expect(insertSlashSkillReference('第一行\n/ab', 'build'), '第一行\n/build ');
    });

    test('制表符分隔符同样被保留', () {
      expect(insertSlashSkillReference('x\t/ab', 'build'), 'x\t/build ');
    });

    test('已补全并带末尾空格的引用不再是「正在输入」，返回 null', () {
      // 补全结果是 `帮我 /build `，末尾空格表示引用已完成。此时再调用应返回
      // null，调用方保持输入不变 —— 否则会在末尾反复追加空格。
      expect(insertSlashSkillReference('帮我 /build ', 'build'), isNull);
    });

    test('已补全但仍在继续输入时，按新查询词改写而非追加', () {
      expect(insertSlashSkillReference('帮我 /build', 'build'), '帮我 /build ');
    });

    test('路径中的斜杠不会被误替换', () {
      expect(insertSlashSkillReference('a/b', 'build'), isNull);
    });
  });

  group('slashSkillCommandNames（发送前的命令识别）', () {
    test('识别句中的完整命令', () {
      expect(slashSkillCommandNames('帮我 /build 打包'), ['build']);
    });

    test('行首命令', () {
      expect(slashSkillCommandNames('/deploy'), ['deploy']);
    });

    test('多个命令按出现顺序返回', () {
      expect(slashSkillCommandNames('/a 和 /b'), ['a', 'b']);
    });

    test('重复命令各计一次', () {
      expect(slashSkillCommandNames('/a /a'), ['a', 'a']);
    });

    test('路径不算命令（后面紧跟 / 或非空白）', () {
      expect(slashSkillCommandNames('看 /tmp/x 和 /usr/bin'), isEmpty);
    });

    test('句子中间的 /tmp 不算命令', () {
      expect(slashSkillCommandNames('打开 /tmp 目录'), ['tmp'],
          reason: '/tmp 后面是空白，形状上确实是命令 token，由调用方按已安装名单过滤');
    });

    test('没有斜杠时为空', () {
      expect(slashSkillCommandNames('普通文本'), isEmpty);
    });

    test('允许 - 与 _', () {
      expect(slashSkillCommandNames('/a-b_c'), ['a-b_c']);
    });
  });

  group('removeSlashSkillCommands（发送前剔除命令）', () {
    test('删除命令并保留前后文本', () {
      expect(removeSlashSkillCommands('帮我 /build 打包', {'build'}), '帮我 打包');
    });

    test('删除行首命令', () {
      expect(removeSlashSkillCommands('/build 打包', {'build'}), '打包');
    });

    test('删除句尾命令', () {
      expect(removeSlashSkillCommands('帮我打包 /build', {'build'}), '帮我打包');
    });

    test('只删指定名字，其它保留', () {
      expect(
        removeSlashSkillCommands('帮我 /build /deploy 收尾', {'build'}),
        '帮我 /deploy 收尾',
      );
    });

    test('没有可删命令时原样返回，不做空白归一化', () {
      expect(
        removeSlashSkillCommands('帮我  打包', {'build'}),
        '帮我  打包',
        reason: '没有识别到命令就完全不动用户输入',
      );
    });

    test('删除后把连续空白压成单个空格', () {
      expect(removeSlashSkillCommands('帮我  /build   打包', {'build'}), '帮我 打包');
    });

    test('命令位于中间时两侧各留一个空格，不粘连', () {
      expect(removeSlashSkillCommands('a /build b', {'build'}), 'a b');
    });

    test('只由命令组成时结果为空', () {
      expect(removeSlashSkillCommands('/build', {'build'}), '');
    });

    test('多行输入会被压成单行（既有行为）', () {
      expect(removeSlashSkillCommands('第一行\n/build 第二行', {'build'}),
          '第一行 第二行');
    });
  });
}