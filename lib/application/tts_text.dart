/// G1（长按朗读）：把消息正文（Markdown）转成适合 TTS 朗读的纯文本。
///
/// 朗读只关心「听到什么」，不关心排版，所以这里做的是**降噪**而不是渲染：
/// 代码块折叠为占位词、链接只留文字、图片只留 alt、各类标记符号全部剥离，
/// 最后折叠多余空白。纯函数（无 IO、无平台依赖），便于穷举单测。
library;

/// 代码块在朗读时的占位词。逐字符朗读源码没有意义，用一句话代替。
const String kCodeBlockPlaceholder = '代码块';

/// 把 Markdown 正文转成朗读文本。输入为空或纯空白时返回空串。
String speakableText(String markdown) {
  if (markdown.trim().isEmpty) return '';

  var text = markdown.replaceAll('\r\n', '\n');

  // 1. 围栏代码块（``` / ~~~，含未闭合的流式半截块）→ 占位词。
  text = text.replaceAll(
      RegExp(r'```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)'),
      kCodeBlockPlaceholder);

  // 2. 行内 HTML 标签（模型偶尔输出 <br> / <b>）→ 空格。只在同行内匹配，
  //    避免把数学表达式里的比较符误伤成跨行删除。
  text = text.replaceAll(
      RegExp(r'</?[a-zA-Z][a-zA-Z0-9]*(?:[ \t][^<>]*)?/?>'), ' ');

  // 3. 图片 ![alt](url) → alt（url 不发音）。
  text = text.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');

  // 4. 链接 [文字](url) → 文字。
  text = text.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');

  // 5. 行内代码 `x` → x（反引号不发音）。
  text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');

  // 6. 行首标记：标题 / 引用 / 列表 / 任务框。
  //    列表符必须先于任务框剥离：`- [ ] 待办` 去掉 `- ` 后才剩下 `[ ] 待办`。
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}#{1,6}[ \t]+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}>[ \t]?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}[-*+][ \t]+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}\d+[.)][ \t]+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}\[[ xX]\][ \t]*', multiLine: true), '');

  // 7. 分隔线（--- / *** / ___）。
  text = text.replaceAll(
      RegExp(r'^[ \t]{0,3}(?:[-*_][ \t]*){3,}$', multiLine: true), '');

  // 8. 表格：分隔行整行丢弃，其余行的竖线读作停顿（换成空格）。
  text = text.replaceAll(
      RegExp(r'^[ \t]{0,3}\|?[ \t:|-]*\|[ \t:|-]*$', multiLine: true), '');
  text = text.replaceAllMapped(
      RegExp(r'^[ \t]{0,3}\|(.+)\|[ \t]{0,3}$', multiLine: true),
      (m) => (m.group(1) ?? '').replaceAll('|', ' '));

  // 9. 强调标记：只在成对出现时剥离，避免破坏 snake_case 这类标识符。
  //    注意 Dart 的 `replaceAll` 不展开 `$1`，必须用 replaceAllMapped 取分组。
  text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'\*([^*\n]+)\*'), (m) => m.group(1)!);
  text = text.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9_])_([^_\n]+)_(?![A-Za-z0-9_])'),
      (m) => m.group(1)!);

  // 10. 折叠空白：行内连续空白折一，空行折成一个换行。
  text = text.replaceAll(RegExp(r'[ \t\u3000]+'), ' ');
  text = text.replaceAll(RegExp(r'[ \t\u3000]*\n[ \t\u3000]*'), '\n');
  text = text.replaceAll(RegExp(r'\n{2,}'), '\n');

  return text.trim();
}
