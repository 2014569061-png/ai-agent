import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/tts_text.dart';

/// G1：朗读文本净化纯函数穷举。
///
/// 断言写死期望字符串，不写「包含」这类弱断言 —— 净化规则一旦被改动，
/// 这里必须红，否则朗读内容会静默带上 Markdown 标记。
void main() {
  group('speakableText 空输入', () {
    test('空串返回空串', () {
      expect(speakableText(''), '');
    });

    test('纯空白返回空串', () {
      expect(speakableText('   \n\t\n   '), '');
    });
  });

  group('speakableText 保留正文', () {
    test('普通中文原样保留', () {
      expect(speakableText('你好，世界。'), '你好，世界。');
    });

    test('行内连续空白折叠为一', () {
      expect(speakableText('甲    乙'), '甲 乙');
    });

    test('snake_case 标识符不被斜体规则破坏', () {
      expect(speakableText('用 snake_case_name 命名'), '用 snake_case_name 命名');
    });
  });

  group('speakableText 代码', () {
    test('围栏代码块折叠为占位词', () {
      const md = '说明\n'
          '```dart\n'
          'print(1);\n'
          '```\n'
          '结束';
      expect(speakableText(md), '说明\n$kCodeBlockPlaceholder\n结束');
    });

    test('流式未闭合的代码块同样折叠', () {
      expect(
        speakableText('结果如下\n```\nfinal a = 1;'),
        '结果如下\n$kCodeBlockPlaceholder',
      );
    });

    test('行内代码只去反引号', () {
      expect(speakableText('用 `flutter test` 跑'), '用 flutter test 跑');
    });
  });

  group('speakableText 链接与图片', () {
    test('链接取其文字', () {
      expect(speakableText('见 [文档](https://example.com) 说明'), '见 文档 说明');
    });

    test('图片取 alt', () {
      expect(speakableText('![架构图](img.png)'), '架构图');
    });
  });

  group('speakableText 标题与列表', () {
    test('标题符号与列表符被剥离', () {
      const md = '# 标题\n'
          '- 甲\n'
          '- 乙\n'
          '1. 丙';
      expect(speakableText(md), '标题\n甲\n乙\n丙');
    });

    test('引用与任务框被剥离', () {
      expect(speakableText('> 引用行\n- [ ] 待办'), '引用行\n待办');
    });
  });

  group('speakableText 强调与表格', () {
    test('加粗与斜体只留文字', () {
      expect(speakableText('**重点**与*轻量*及~~删除~~'), '重点与轻量及删除');
    });

    test('表格去掉分隔行并把竖线读作停顿', () {
      const md = '| 甲 | 乙 |\n'
          '| --- | --- |\n'
          '| 1 | 2 |';
      expect(speakableText(md), '甲 乙\n1 2');
    });
  });
}
