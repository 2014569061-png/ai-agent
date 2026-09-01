/// 全局文案集中表。
///
/// 当前默认中文。将零散的硬编码文案收敛到这里，
/// 后续接入 ARB + intl 时，把这些常量替换为
/// `AppLocalizations.of(context).xxx` 即可，无需改动调用点。
abstract final class AppStrings {
  // --- 导航与标题 ---
  static const appTitle = 'NEXUS Agent';
  static const newConversation = '新会话';
  static const settings = '设置';
  static const agentManagement = 'Agent 管理';
  static const promptLibrary = 'Prompt 库';
  static const history = '历史会话';

  // --- 聊天页 ---
  static const startNewAgentTask = '开始一个新的 Agent 任务';
  static const pickDirectionOrTypeTask = '选择一个方向，或者直接输入你的任务';
  static const inputTaskHint = '输入任务…';
  static const addFile = '添加文件';
  static const send = '发送';
  static const stopGenerating = '停止生成';
  static const demoModeUnconfigured = '演示模式（未配置）';
  static const currentAgent = '当前 Agent';
  static const localDirectMode = '本地直连模式';
  static const copyConversation = '复制会话';
  static const exportMarkdown = '导出 Markdown';
  static const regenerate = '重新生成';
  static const switchModel = '切换模型';
  static const conversationCopied = '当前会话已复制到剪贴板';
  static const copiedToClipboard = '已复制 Markdown 到剪贴板';
  static String exportedTo(String path) => '已导出到 $path';
  static const switchProvider = '切换模型服务商';
  static const noProviderConfigured = '尚未配置 Provider，请前往「设置」添加。';
  static String switchedTo(String name, String model) => '已切换到 $name / $model';
  static const selectAgent = '选择 Agent';
  static const agentPersistenceDisabled = '浏览器预览暂不启用 Agent 持久化。';
  static const conversationPersistenceDisabled = '浏览器预览暂不启用会话持久化。';
  static const applyAsSystemPrompt = '已应用为系统提示词';
  static const insertedToInput = '已插入到输入框';
  static const confirmToolCall = '确认工具调用';
  static const requiresAuthorization = '执行前需要你的授权';
  static const toolArguments = '调用参数';
  static const reject = '拒绝';
  static const allowOnce = '允许一次';
  static const dangerOperation = '危险操作';
  static const requiresConfirmation = '需要确认';
  static const awaitExecution = '等待执行';
  static const awaitConfirmation = '等待确认';
  static const executed = '已完成';
  static const executionFailed = '执行失败';
  static const toolExecutionFailed = '工具执行失败';
  static const executing = '执行中';
  static String attachmentExceedsLimit(String name) => '附件 $name 超过 8MB，已跳过';
  static String pdfNoTextExtracted(String name) => 'PDF 文件 $name 未提取到可用文本';
  static String fileContent(String name) => '文件 $name 内容';
  static const contentTruncated = '内容已截断';
  static const imageAttachment = '[图片附件]';
  static const fileAttachment = '[文件附件]';
  static const codeCopied = '代码已复制';
  static const genericAssistant = '通用助手';
  static const youAreHelpfulAgent = '你是一个有帮助的 AI Agent。';
  static const error = '错误：';

  // --- 设置页 ---
  static const providerSettings = 'Provider 设置';
  static const modelServiceConfig = '模型服务配置';
  static const quickApplyTemplate = '快速套用服务商模板';
  static const protocolType = '协议类型';
  static const savedProviders = '已保存 Provider';
  static const providerName = 'Provider 名称';
  static const baseUrl = 'Base URL';
  static const modelName = '模型名称';
  static const apiKey = 'API Key';
  static const tavilyApiKey = 'Tavily API Key（联网搜索，可选）';
  static const saveConfig = '保存配置';
  static const saving = '保存中…';
  static const testConnection = '测试连接';
  static const testing = '测试中…';
  static const connectionSuccess = '连接成功';
  static String connectionFailed(String error) => '连接失败：$error';
  static const providerConfigSaved = 'Provider 配置已保存';
  static const fillBaseUrlAndKey = '请先填写 Base URL 和 API Key';
  static const onlyOpenAiCompatible = '仅 OpenAI 兼容协议支持自动获取模型列表，请手动填写模型名称。';
  static const noModelsReturned = '服务未返回可用模型';
  static String fetchModelsFailed(String error) => '获取模型失败：$error';
  static const apiKeySecureStorage = 'API Key 仅保存到系统安全存储。';
  static const dayMode = '日间模式';
  static const dayModeSubtitle = '当前使用蓝白浅色主题';
  static const darkModeSubtitle = '当前使用深色主题';
  static const mcpServers = 'MCP 服务器';
  static const mcpServersHint = 'MCP 工具会在 Agent 执行时自动合并进工具集，风险默认需要确认。';
  static const noMcpServers = '尚未配置 MCP 服务器。';
  static const addMcpServer = '添加 MCP 服务器';
  static const clearAll = '清空全部';
  static const clearMcpServers = '清空 MCP 服务器？';
  static const clearMcpServersConfirm = '将移除全部已配置的 MCP 服务器。';
  static const clear = '清空';
  static const cancel = '取消';
  static const add = '添加';
  static const connectionMethod = '连接方式';
  static const streamableHttp = 'Streamable HTTP（推荐）';
  static const stdioProcess = 'stdio 子进程（仅桌面）';
  static const serverName = '名称';
  static const serverUrl = '服务器 URL（如 http://localhost:3000/mcp）';
  static const command = '命令（如 npx）';
  static const argsSpaceSeparated = '参数（空格分隔）';
  static const fillServerUrl = '请填写服务器 URL';

  // --- Agent 管理页 ---
  static const availableTools = '可用工具';
  static const dangerToolHint = '危险操作，执行前必须确认';
  static const confirmToolHint = '执行前需要确认';
  static const safeTool = '安全工具';
  static const modelParams = '模型参数';
  static const temperature = '温度';
  static const topP = 'Top P';
  static const maxOutputTokens = '最大输出 Token';
  static const maxExecutionSteps = '最大执行步数';

  // --- 历史页 ---
  static const rename = '重命名';
  static const delete = '删除';
  static const pin = '置顶';
  static const unpin = '取消置顶';
  static const favorite = '收藏';
  static const unfavorite = '取消收藏';
  static const searchPlaceholder = '搜索会话…';

  // --- 主题 ---
  static const lightMode = '浅色模式';
  static const darkMode = '深色模式';
  static const systemMode = '跟随系统';
}
