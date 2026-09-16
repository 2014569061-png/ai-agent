/// Agent 系统提示词的统一拼装顺序。
///
/// 顺序直接影响 Provider 前缀缓存命中率：OpenAI/DeepSeek/Gemini 的隐式
/// 前缀缓存与 Anthropic 的显式缓存断点都要求“请求前缀字节级一致”。
/// 知识库检索片段按当前问题生成、长期记忆带 revision，一旦排在稳定内容
/// 之前，每一轮请求的前缀都会被改写，缓存全部失效（用户反馈“缓存命中
/// 低、花费高”的主因）。
///
/// 因此固定为：稳定段在前（人格 → 技能索引 → 会话技能 → 委派规则 →
/// 工作区规则），动态段垫底（长期记忆 → 知识库检索）。AgentExecutor 追加
/// 的运行环境说明与计划模式后缀位于更尾部，属于稳定段之后的常量后缀，
/// 不破坏本顺序。
///
/// 调整顺序前先跑 `test/system_prompt_assembly_test.dart` 与
/// `memory_knowledge_test.dart`，并评估对前缀缓存的影响。
String assembleAgentSystemPrompt({
  String personaPrompt = '',
  String skillIndexBlock = '',
  Iterable<String> sessionSkillBlocks = const [],
  String delegationRules = '',
  String workspaceRules = '',
  String projectContextBlock = '',
  String memoryBlock = '',
  String knowledgeBlock = '',
}) {
  final sections = [
    personaPrompt,
    skillIndexBlock,
    ...sessionSkillBlocks,
    delegationRules,
    workspaceRules,
    projectContextBlock,
    memoryBlock,
    knowledgeBlock,
  ].map((section) => section.trim()).where((section) => section.isNotEmpty);
  return sections.join('\n\n');
}
