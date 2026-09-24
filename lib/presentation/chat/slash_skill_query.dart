/// 输入框里 `/` 技能引用的解析与改写。
///
/// 为什么单独抽出来：`/` 补全的文本变换混在 `ChatPage` 的 State 里，既依赖
/// `TextEditingController` 又依赖 `setState`，因此此前**完全没有测试覆盖**。
/// 其中「保留 `/` 前面的分隔符」是用 `matchedText.startsWith(RegExp(r'\s'))`
/// 实现的，可读性差且容易在改动时悄悄丢掉分隔符。这里把它变成纯字符串函数，
/// 行为可以直接断言。
///
/// 纯 Dart 实现（不导入 Flutter），便于单测。
library;

/// 匹配行尾正在输入的 `/` 查询词，捕获 `/` 之后的名字片段。
///
/// 允许名字片段为空（用户刚敲下 `/`），也要求 `/` 位于行首或空白之后，避免把
/// `a/b` 这种路径误判成技能引用。
final _slashQueryPattern = RegExp(r'(?:^|\s)/([a-z0-9_-]*)$');

/// 匹配行尾待替换的 `/` 引用整体（含前导空白）。
final _slashReferencePattern = RegExp(r'(?:^|\s)/[a-z0-9_-]*$');

final _whitespacePattern = RegExp(r'\s');

/// 取出正在输入的 `/` 查询词；当前光标处没有 `/` 引用时返回 null。
///
/// 返回空字符串表示用户刚敲下 `/`（此时应列出全部候选）。
String? slashSkillQuery(String input) =>
    _slashQueryPattern.firstMatch(input)?.group(1);

/// 把行尾的 `/` 引用替换为选中的技能名，返回改写后的文本。
///
/// 没有可替换的引用时返回 null，调用方应保持输入不变。
///
/// 前导分隔符会被保留：`帮我 /bu` 选中 `build` 后得到 `帮我 /build `（注意 `/`
/// 前那个空格仍在，且末尾补一个空格便于继续输入）。若不保留，`帮我` 和 `/build`
/// 会被粘成 `帮我/build`。
String? insertSlashSkillReference(String current, String skillName) {
  final match = _slashReferencePattern.firstMatch(current);
  if (match == null) return null;
  final prefix = current.substring(0, match.start);
  final matchedText = match.group(0)!;
  final separator = matchedText.startsWith(_whitespacePattern)
      ? matchedText.substring(0, 1)
      : '';
  return '$prefix$separator/$skillName ';
}

/// 匹配句中完整的 `/skill` 命令 token，捕获 `/` 之前的分隔空白与命令名。
///
/// 与 [_slashReferencePattern] 的区别：那个只匹配**行尾正在输入**的引用（补全用），
/// 这个匹配**整句里任何位置**的完整命令（发送前解析用）。名字限 1-64 个
/// `[a-z0-9_-]` 字符，且后面必须是空白或结束，避免把 `/tmp/x` 这类路径当成命令。
final _slashCommandPattern = RegExp(r'(^|\s)/([a-z0-9_-]{1,64})(?=\s|$)');

/// 列出输入里出现的全部 `/skill` 命令名（按出现顺序，可能重复）。
List<String> slashSkillCommandNames(String input) => _slashCommandPattern
    .allMatches(input)
    .map((match) => match.group(2)!)
    .toList(growable: false);

/// 从输入里删除 [names] 中的 `/skill` 命令，保留其余文本。
///
/// 被删命令位于文本之后时保留一个分隔空格，避免把前后词粘在一起
/// （`帮我 /build 打包` → `帮我 打包`，而不是 `帮我打包`）。删除后把连续空白压成
/// 单个空格并 trim。
///
/// 注意：没有任何可删除的命令时**原样返回**（不做空白归一化），与调用方「没有识别
/// 到命令就完全不动用户输入」的既有语义一致。
String removeSlashSkillCommands(String input, Set<String> names) {
  final matches =
      _slashCommandPattern.allMatches(input).toList(growable: false);
  if (matches.isEmpty) return input;
  final buffer = StringBuffer();
  var cursor = 0;
  var removed = false;
  for (final match in matches) {
    final name = match.group(2)!;
    if (!names.contains(name)) continue;
    buffer.write(input.substring(cursor, match.start));
    final prefix = match.group(1) ?? '';
    if (prefix.isNotEmpty &&
        buffer.isNotEmpty &&
        !buffer.toString().endsWith(' ')) {
      buffer.write(' ');
    }
    cursor = match.end;
    removed = true;
  }
  if (!removed) return input;
  buffer.write(input.substring(cursor));
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}