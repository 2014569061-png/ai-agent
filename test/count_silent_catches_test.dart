// 守卫静默 catch 门槛本身：这个脚本是 CI ratchet 的判定器，
// 一旦它静默漏计，门槛就会假装通过。
import 'package:flutter_test/flutter_test.dart';

import '../tool/count_silent_catches.dart';

void main() {
  List<CatchSite> scan(String source) => scanSource(source, path: 'x.dart');

  group('scanSource', () {
    test('catch (_) {} 记为未记录意图', () {
      final sites = scan('void f() { try { a(); } catch (_) {} }');
      expect(sites, hasLength(1));
      expect(sites.single.hasComment, isFalse);
      expect(sites.single.location, 'x.dart:1');
    });

    test('catch (__) {} 同样记为未记录意图', () {
      expect(scan('void f() { try { a(); } catch (__) {} }'), hasLength(1));
    });

    test('体内只有注释时记为已记录意图', () {
      final sites = scan('void f() {\n'
          '  try { a(); } catch (_) {\n'
          '    // 为什么可以吞\n'
          '  }\n'
          '}');
      expect(sites, hasLength(1));
      expect(sites.single.hasComment, isTrue);
      expect(sites.single.line, 2);
    });

    test('体内有代码时不计入', () {
      expect(scan('void f() { try { a(); } catch (_) { log(); } }'), isEmpty);
    });

    test('体内含嵌套花括号且有代码时不计入', () {
      expect(
        scan('void f() { try { a(); } catch (_) { if (x) { y(); } } }'),
        isEmpty,
      );
    });

    test('体内只有注释但注释含花括号时仍记为已记录意图', () {
      final sites = scan('void f() { try { a(); } catch (_) { /* { } */ } }');
      expect(sites, hasLength(1));
      expect(sites.single.hasComment, isTrue);
    });

    test('命名参数的 catch 交给静态分析，不计入', () {
      expect(scan('void f() { try { a(); } catch (error) {} }'), isEmpty);
      expect(
        scan('void f() { try { a(); } on StateError catch (e) {} }'),
        isEmpty,
      );
    });

    test('注释里的示例不算站点', () {
      final sites = scan('// catch (_) {}\n'
          '/// catch (_) {}\n'
          '/* catch (_) {} */\n');
      expect(sites, isEmpty);
    });

    test('字符串里的示例不算站点', () {
      final sites = scan('const a = "catch (_) {}";\n'
          "const b = 'catch (_) {}';\n"
          "const c = r'catch (_) {}';\n");
      expect(sites, isEmpty);
    });

    test('字符串里的花括号不会破坏体判定', () {
      expect(scan('void f() { try { a(); } catch (_) { "}"; } }'), isEmpty);
    });

    test('三引号字符串里的示例不算站点', () {
      final sites = scan('const a = """\ncatch (_) {}\n""";\n');
      expect(sites, isEmpty);
    });

    test('多站点时行号各自正确', () {
      final sites = scan('void f() {\n'
          '  try { a(); } catch (_) {}\n'
          '  try { b(); } catch (_) { // 有说明\n'
          '  }\n'
          '}');
      expect(sites, hasLength(2));
      expect(sites[0].line, 2);
      expect(sites[0].hasComment, isFalse);
      expect(sites[1].line, 3);
      expect(sites[1].hasComment, isTrue);
    });

    test('箭头体 catch 不计入', () {
      expect(scan('void f() { try { a(); } catch (_) => b(); }'), isEmpty);
    });
  });

  group('maskCommentsAndStrings', () {
    test('屏蔽后长度与换行保持不变', () {
      const source = 'a // 注释\nb /* 块 */ c\n';
      final masked = maskCommentsAndStrings(source);
      expect(masked.length, source.length);
      expect('\n'.allMatches(masked).length, 2);
      // 注释文本不再出现在残文里，但非注释字符保持原位。
      expect(masked.contains('注释'), isFalse);
      expect(masked.contains('块'), isFalse);
      expect(masked.startsWith('a '), isTrue);
      expect(masked.endsWith(' c\n'), isTrue);
      // 屏蔽后的行数与原文一致，因此报出的行号可以直接使用。
      expect(
        masked.split('\n').length,
        source.split('\n').length,
      );
    });

    test('屏蔽不会漏掉转义引号后的代码', () {
      // 字符串里的转义引号不能提前结束字面量，否则后面的代码会被误屏蔽。
      const source = r"final s = 'it\'s'; final t = 1;";
      final masked = maskCommentsAndStrings(source);
      expect(masked.length, source.length);
      expect(masked.contains('final t'), isTrue);
      expect(masked.contains('it'), isFalse);
    });
  });
}