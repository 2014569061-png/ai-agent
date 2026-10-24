// 聊天系统提示与模式判定的纯函数规则。
//
// 从 ChatController 抽出，行为保持不变；ChatController 上的同名静态方法
// 保留为委托，避免改动既有调用方与测试。

import '../domain/models.dart';
import '../infrastructure/tools/sub_agent_tool.dart';

bool chatRequiresAgentModeForRequest(
  String text, {
  String taskType = 'general',
}) {
  if (taskType != 'general') return true;
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  final hasAction = RegExp(
    r'创建|新建|生成|制作|做|开发|实现|修改|编辑|修复|构建|编译|写一个|create|build|implement|edit|fix',
  ).hasMatch(normalized);
  final hasDevelopmentTarget = RegExp(
    r'html|网页|网站|页面|项目|代码|程序|应用|文件|exe|flutter|react|vue|python|go|node|file|app',
  ).hasMatch(normalized);
  final isDeviceAction = RegExp(
    r'打开.{0,12}(应用|软件|微信|支付宝|相机|设置|浏览器)|'
    r'(搜索|查找|找一下|找找).{0,16}(本地|手机|文件|照片|图片|pdf)|'
    r'(本地|手机).{0,10}(搜索|查找|找一下|找找).{0,12}(文件|照片|图片|pdf)|'
    r'找.{0,10}(本地|手机)?(文件|照片|图片)',
  ).hasMatch(normalized);
  return (hasAction && hasDevelopmentTarget) || isDeviceAction;
}

String chatDelegationRules(bool autonomous) {
  if (autonomous) {
    return '[自主委派规则]\n'
        '- 单项只读任务用 sub_agent；独立任务可用 sub_agents 一次并行1–3项，每轮输出上限之和不超过12000。\n'
        '- 子任务各有独立上下文，共享只读工作区，不会继承父对话；prompt 必须包含目标和约束。\n'
        '- 通过 maxTokens 设置每个子任务的单次模型输出上限（上限 ${SubAgentTool.maxBudget}），不要超预算。\n'
        '- 每项累计输入+输出预算为 maxTokens 的4倍，重试和摘要共同扣除；预算耗尽后汇总已有结果，不得重派同一任务来重置预算。\n'
        '- sub_agent/sub_agents 只读。可用 sub_agent_edit 经审批在隔离 worktree 委派文件编辑；返回的提案必须读取审阅，再通过父工作区编辑工具应用并验证。终端、提交、发布不得委派。\n'
        '- 委派只是优化手段，你仍对最终结果负责，应核实并汇总子 Agent 返回。';
  }
  return '[委派规则]\n'
      '- 委派子任务前必须先获得用户确认（sub_agent 调用需审批）。\n'
      '- sub_agent/sub_agents 只读；sub_agent_edit 经审批只在隔离 worktree 编辑提案，不自动合入。应用提案后由父工作区验证。终端、提交、发布不得委派。\n'
      '- 通过 maxTokens 设置每个子任务的单次模型输出上限（上限 ${SubAgentTool.maxBudget}），不要超预算；委派后应核实并汇总结果。';
}

String chatWorkspaceToolRules({
  String? workspacePath,
  required bool fileToolsAvailable,
  required bool terminalAvailable,
  ChatMode mode = ChatMode.agent,
}) {
  final ws = workspacePath?.trim() ?? '';
  if (mode == ChatMode.chat) {
    return '[工作区环境]\n'
        '- 当前会话为“聊天”模式，未装配文件或终端工具；这不是设置或设备能力问题。\n'
        '- 用户要求创建、修改、保存文件或执行构建时，请引导其切换到 Agent 模式并选择项目目录后重试。\n'
        '- 不要要求用户寻找不存在的“文件/终端开关”，也不要编造文件已创建。';
  }
  if (ws.isEmpty) {
    return '[工作区环境]\n'
        '- 当前未选择工作区，文件读写与终端工具未启用。这是应用内配置，不是设备能力缺失。\n'
        '- 若任务需要读写文件或执行命令（编译、脚本、构建等），请先简短告诉用户：'
        '点击聊天页顶栏的工作区入口选择一个项目目录，然后重发任务。\n'
        '- 不要声称设备无法完成，也不要在无工具时编造执行结果。';
  }
  if (!fileToolsAvailable) {
    return '[工作区环境]\n'
        '- 工作区：$ws，但工作区文件工具未启用，相关文件操作不可用。\n'
        '- 若任务需要读写文件，请提示用户到“设置 → 扩展与环境 → 工具列表”开启“允许 Agent 读写当前工作区文件”后再试。';
  }
  if (!terminalAvailable) {
    return '[工作区环境]\n'
        '- 工作区目录：$ws，文件工具可用，可创建、读取和编辑项目文件。\n'
        '- 终端命令当前不可用。静态 HTML/CSS/JS、Markdown 等文件任务仍应直接完成；仅安装依赖、构建或运行命令需要用户开启终端或配置运行环境。';
  }
  return '[工作区环境]\n'
      '- 工作区目录：$ws（文件工具与终端的默认工作目录；仅默认目录，不是完整文件系统沙箱）。\n'
      '- 可用工具：read_file / write_file / edit_file / list_directory / search_files / '
      'move_file / delete_file / terminal。\n'
      '- 终端命令运行在 Android Linux 运行时中（优先内置 Alpine PRoot 环境，回落 Termux 或系统 '
      'shell），可在环境内用 apk 等包管理器安装工具链（需网络）；单条命令默认 120s 超时，'
      '可用 timeoutSeconds 参数放宽。\n'
      '- 手机开发任务（编译、构建、运行脚本）必须基于真实命令输出汇报结果，禁止伪造成功。';
}
