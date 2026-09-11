/// 输入区上方「技能提示槽位」的解析规则。
///
/// 三种技能提示——`/` 命令补全、自动匹配建议、已加载的会话技能——在视觉上是
/// 同一种 36dp 单行条（各自 44dp 含间距），且都以「非运行中」为前提。
/// 三者若同时渲染，在 360dp 屏上会白占 3×44dp，把输入框与消息区一起挤扁。
///
/// 因此它们**共用一个槽位**：任一时刻只渲染即时性最高的那一条。
/// 这不是删功能——未渲染的两条都只是暂时让位，条件变化即回来。
enum ComposerSkillSlot {
  /// `/` 命令补全：用户刚打出 `/`，是显式手势，因此优先级最高。
  /// 放在建议之上很关键：否则打出「/rea」被自动建议顶掉补全，等于帮倒忙。
  slash,

  /// 自动匹配建议：由 [SkillIntentMatcher] 推断，用户并未主动索取。
  suggestion,

  /// 已加载到当前会话的技能：状态类提示，最不紧急，排最后。
  loaded,

  /// 无内容，不占高度。
  none,
}

/// 按优先级选出当前应渲染的技能提示槽位。纯函数，便于穷举单测。
ComposerSkillSlot resolveComposerSkillSlot({
  required bool running,
  required bool hasSlashMatches,
  required bool hasSuggestions,
  required bool hasLoadedSkills,
}) {
  // 运行中不展示任何技能提示：输入区此时已被运行状态条占用，且不适合改技能。
  if (running) return ComposerSkillSlot.none;
  if (hasSlashMatches) return ComposerSkillSlot.slash;
  if (hasSuggestions) return ComposerSkillSlot.suggestion;
  if (hasLoadedSkills) return ComposerSkillSlot.loaded;
  return ComposerSkillSlot.none;
}
