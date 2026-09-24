/// 技能建议的选择规则：`/` 补全候选、意图建议的触发条件、以及避免多余重建的去重比较。
///
/// 为什么单独抽出来：这三段规则此前内联在 `ChatPage` 的 State 里，与
/// `TextEditingController`、`setState`、`_skillMatcher` 混在一起，因此没有单测。
/// 抽成纯函数后，「最多 5 条」「至少 2 个字符」「顺序相同就不重建」这些规则可以
/// 直接断言，改动时也不会悄悄失效。
///
/// 纯 Dart 实现（泛型不绑定具体类型），便于单测。
library;

/// `/` 补全最多展示的候选数量。
const int maxSlashSkillSuggestions = 5;

/// 触发「意图建议」所需的最短输入长度。
///
/// 单个字符几乎会命中所有技能，制造噪音；两个字符起才有区分度。
const int minIntentSuggestionInputLength = 2;

/// 计算 `/` 补全候选。
///
/// [query] 为 null 表示当前不是 `/` 引用；为空字符串表示刚敲下 `/`（应列出全部
/// 候选）。候选需满足：名字以 [query] 开头、且尚未加载到当前会话，最多
/// [maxSlashSkillSuggestions] 条。
List<T> selectSlashSkillSuggestions<T>({
  required List<T> skills,
  required String? query,
  required String Function(T) nameOf,
  required bool Function(T) isLoaded,
}) {
  if (query == null) return const [];
  return skills
      .where((item) => nameOf(item).startsWith(query) && !isLoaded(item))
      .take(maxSlashSkillSuggestions)
      .toList(growable: false);
}

/// 是否应给出「意图建议」。
///
/// 输入太短，或用户已经主动关掉提示（[_dismissed]）时都不给。
bool shouldOfferIntentSkillSuggestions({
  required String input,
  required bool dismissed,
}) {
  if (dismissed) return false;
  return input.length >= minIntentSuggestionInputLength;
}

/// 两条建议列表是否「条目相同且顺序相同」。
///
/// 用途：内容没变时跳过 `setState`，避免每次按键都重建输入区。
bool sameSkillSuggestionOrder<T>(
  List<T> left,
  List<T> right, {
  required Object Function(T) idOf,
}) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (idOf(left[index]) != idOf(right[index])) return false;
  }
  return true;
}