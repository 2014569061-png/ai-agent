// 静默吞掉异常的计数与门槛检查。
//
// 用法：`dart run tool/count_silent_catches.dart [lib 目录] [上限]`
// 省略上限时只打印统计，不设门槛。
//
// 为什么需要这个脚本：`catch (_) {}` 在静态分析里是**隐形**的。
// `empty_catches` 会报出 `catch (error) {}`，但只要异常参数名是纯下划线
// （`catch (_) {}`、`catch (__) {}`）就被豁免 —— 实测确认过这一点。仓库里绝大多数
// 站点恰好都用下划线，于是这类写法既没有日志也没有遥测，失败与成功在数据上不可
// 区分，而 `flutter analyze` 全绿。
//
// 为什么不能直接用 grep：`catch (_) {}` 这个字面量本身会出现在**注释**里（例如
// 解释本设计时举例），朴素 grep 会把它算进来（虚高）；而把注释剥掉再数，又会把
// `catch (_) { // 说明 }` 的括号变成「空」（反向虚高）。两种误报方向相反，因此必须
// 按 catch 体本身来判断。
//
// 实现方式：先把注释与字符串整体屏蔽成空白（保留换行以便报行号），再用配平方式
// 截取 catch 体。相比单行正则，这样能正确处理体内含花括号的写法，例如
// `catch (_) { if (x) { y(); } }` 不会被漏计。
//
// 分类：
// - undocumented：catch 体里既没有语句也没有注释 —— 没人知道为什么可以吞。
// - documented  ：catch 体里只有注释 —— 意图已记录，属于「有意忽略」。
//
// 门槛只卡 undocumented：要驱动下降的是「没人知道为什么能吞」的数量。写法上留了
// 出口 —— 在 catch 体里写下为什么可以吞，即视为已记录意图。这不是漏洞，而是有意
// 的设计：本门槛挡的是**顺手吞掉**，不是**敷衍地吞掉**。
//
// 命名参数的 catch（`catch (error) {}`）不在统计范围内：静态分析本来就会报出它们，
// 由 `flutter analyze` 负责。
import 'dart:io';

/// 一个「catch 体为空或只含注释」的站点。
class CatchSite {
  const CatchSite({
    required this.path,
    required this.line,
    required this.hasComment,
  });

  final String path;
  final int line;

  /// true 表示体内有注释（意图已记录）；false 表示体内既无代码也无注释。
  final bool hasComment;

  /// 便于打印与断言的 `路径:行号` 形式。
  String get location => '$path:$line';

  @override
  String toString() => 'CatchSite($location, hasComment: $hasComment)';
}

final _catchPattern = RegExp(r'\bcatch\s*\(([^)]*)\)');
final _underscoreName = RegExp(r'^_+$');

/// 扫描一段 Dart 源码，返回所有「catch 体为空或只含注释」的站点。
///
/// [path] 只用于生成站点位置，便于调用方区分来源。
List<CatchSite> scanSource(String source, {String path = '<source>'}) {
  final masked = maskCommentsAndStrings(source);
  final sites = <CatchSite>[];
  for (final match in _catchPattern.allMatches(masked)) {
    // 只看异常参数为纯下划线的 catch：其余写法由 empty_catches 负责。
    final parameter = (match.group(1) ?? '').split(',').first.trim();
    if (!_underscoreName.hasMatch(parameter)) continue;

    var cursor = match.end;
    while (cursor < masked.length && _isWhitespace(masked[cursor])) {
      cursor++;
    }
    // 只处理块体 catch；箭头体或语法异常一律跳过。
    if (cursor >= masked.length || masked[cursor] != '{') continue;
    final close = _matchingBrace(masked, cursor);
    if (close == null) continue;

    final maskedBody = masked.substring(cursor + 1, close);
    if (maskedBody.trim().isNotEmpty) continue; // 体内有代码，不是「吞掉」

    final rawBody = source.substring(cursor + 1, close);
    sites.add(CatchSite(
      path: path,
      line: _lineNumberAt(source, match.start),
      hasComment: rawBody.contains('//') || rawBody.contains('/*'),
    ));
  }
  return sites;
}

/// 把注释与字符串字面量整体替换为空白，保留换行与总长度。
///
/// 用途：只有屏蔽之后，花括号配平才不会把字符串或注释里的 `{`、`}` 当成代码结构。
/// 同时，屏蔽后的残文可以安全地用来判断「体内是否还有代码」。
String maskCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];

    // 行注释
    if (char == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    // 块注释（保留换行）
    if (char == '/' && i + 1 < source.length && source[i + 1] == '*') {
      out.write('  ');
      i += 2;
      while (i < source.length) {
        if (source[i] == '*' &&
            i + 1 < source.length &&
            source[i + 1] == '/') {
          break;
        }
        out.write(_keepNewline(source[i]));
        i++;
      }
      if (i < source.length) {
        out.write('  ');
        i += 2;
      }
      continue;
    }

    // 字符串字面量（含 raw 前缀与三引号）
    final rawPrefix = char == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    if (char == "'" || char == '"' || rawPrefix) {
      final quoteIndex = rawPrefix ? i + 1 : i;
      final quote = source[quoteIndex];
      final triple = quoteIndex + 2 < source.length &&
          source[quoteIndex + 1] == quote &&
          source[quoteIndex + 2] == quote;
      final delimiterLength = triple ? 3 : 1;
      for (var k = i; k < quoteIndex + delimiterLength; k++) {
        out.write(_keepNewline(source[k]));
      }
      i = quoteIndex + delimiterLength;
      while (i < source.length) {
        if (!rawPrefix && source[i] == '\\' && i + 1 < source.length) {
          out.write('  ');
          i += 2;
          continue;
        }
        if (triple) {
          if (source[i] == quote &&
              i + 2 < source.length &&
              source[i + 1] == quote &&
              source[i + 2] == quote) {
            out.write('   ');
            i += 3;
            break;
          }
        } else if (source[i] == quote) {
          out.write(' ');
          i++;
          break;
        }
        out.write(_keepNewline(source[i]));
        i++;
      }
      continue;
    }

    out.write(char);
    i++;
  }
  return out.toString();
}

void main(List<String> args) {
  final root = Directory(args.isEmpty ? 'lib' : args.first);
  final maximum = args.length > 1 ? int.tryParse(args[1]) : null;

  if (!root.existsSync()) {
    stderr.writeln('目录不存在：${root.path}');
    exitCode = 2;
    return;
  }
  if (args.length > 1 && maximum == null) {
    stderr.writeln('上限必须是整数，收到：${args[1]}');
    exitCode = 2;
    return;
  }

  final undocumented = <String>[];
  final documented = <String>[];

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final site in scanSource(source, path: entity.path)) {
      (site.hasComment ? documented : undocumented).add(site.location);
    }
  }

  final undocumentedCount = undocumented.length;
  final total = undocumentedCount + documented.length;

  stdout.writeln('未记录意图的空 catch（门槛对象）: $undocumentedCount 处');
  stdout.writeln('已记录意图的注释型 catch        : ${documented.length} 处');
  stdout.writeln('合计静默吞掉的异常              : $total 处');

  if (undocumentedCount > 0) {
    stdout.writeln('\n未记录意图的位置：');
    for (final location in undocumented.toList()..sort()) {
      stdout.writeln('  $location');
    }
  }

  if (maximum != null && undocumentedCount > maximum) {
    stderr.writeln(
      '\n未记录意图的空 catch 为 $undocumentedCount 处，超过上限 $maximum 处。',
    );
    stderr.writeln(
      '请二选一：① 在 catch 体里写下为什么可以吞（即视为已记录意图）；'
      '② 用 NexusGuard.degradeAsync / degradeCaught 把失败接入诊断日志。',
    );
    exitCode = 1;
    return;
  }
  if (maximum != null) {
    stdout.writeln('\n门槛通过：$undocumentedCount <= $maximum。');
  }
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

String _keepNewline(String char) => char == '\n' ? '\n' : ' ';

/// 从 [openIndex] 处的 `{` 找配对的 `}`，返回其下标；找不到返回 null。
///
/// 只能对 [maskCommentsAndStrings] 处理过的文本使用。
int? _matchingBrace(String masked, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < masked.length; i++) {
    if (masked[i] == '{') {
      depth++;
    } else if (masked[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

int _lineNumberAt(String source, int index) =>
    '\n'.allMatches(source.substring(0, index)).length + 1;