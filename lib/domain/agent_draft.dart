import 'models.dart';

/// 「对话式创建 Agent」用的工具摘要。
///
/// 刻意不依赖 `AgentTool`：草稿的组装与解析因此是纯数据变换，单测可以用一份
/// 假工具列表驱动，不需要真实运行时、插件或 MCP 连接。
class AgentToolSpec {
  const AgentToolSpec({
    required this.name,
    required this.description,
    required this.risk,
  });

  final String name;
  final String description;
  final ToolRisk risk;
}

/// AI 根据一句话目标生成的 Agent 草稿。
///
/// **它不落库。** 这里只是「待用户确认的预填内容」：真正写库只发生在
/// `AgentEditorPage._save()`，用户可以在保存前修改任何字段。生成阶段既不创建
/// 会话或任务，也不授予任何运行时权限。
class AgentDraft {
  const AgentDraft({
    required this.goal,
    required this.name,
    required this.systemPrompt,
    this.grantedTools = const <String>{},
    this.pendingTools = const <String>[],
    this.unknownTools = const <String>[],
    this.maxSteps = defaultMaxSteps,
    this.temperature = defaultTemperature,
    this.maxTokens = defaultMaxTokens,
    this.topP = defaultTopP,
    this.notes = const <String>[],
    this.fromModel = true,
  });

  static const defaultMaxSteps = 8;
  static const defaultTemperature = 0.7;
  static const defaultMaxTokens = 2048;
  static const defaultTopP = 1.0;

  /// 用户输入的原始目标。
  final String goal;

  /// 智能体名称。
  final String name;

  /// 最终会写进 `Agent.systemPrompt` 的正文。工作步骤、约束边界与验收条件都被
  /// 折进这里，因为 Agent 表没有单独的列来承载它们；这份文本就是用户在编辑器
  /// 里要审阅的东西。
  final String systemPrompt;

  /// 默认勾选的工具，只包含风险等级为安全的项。
  final Set<String> grantedTools;

  /// 模型想要、但风险等级高于安全级因而**不默认勾选**的工具，交用户在编辑器里决定。
  final List<String> pendingTools;

  /// 模型给出但当前工具目录里不存在的名称，已被剔除。
  final List<String> unknownTools;

  final int maxSteps;
  final double temperature;
  final int maxTokens;
  final double topP;

  /// 生成与解析过程中的如实说明（回退原因、被剔除的工具、未默认勾选的工具），
  /// 用于在界面上告知用户发生了什么，而不是让它悄悄发生。
  final List<String> notes;

  /// false 表示模型输出不可用、已回退到本地确定性草稿。
  final bool fromModel;

  bool get hasPendingTools => pendingTools.isNotEmpty;
}
