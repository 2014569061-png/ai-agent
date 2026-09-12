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
  // --- 长按朗读（G1）---
  static const speakAloud = '朗读';
  static const stopSpeaking = '停止朗读';
  static const noSpeakableContent = '没有可朗读的内容';
  static const ttsUnsupported = '当前设备不支持语音朗读';
  // --- 消息长按菜单 ---
  static const messageActions = '消息操作';
  static const selectText = '选择文本';
  static const finishSelecting = '完成选择';
  static const copyFullText = '复制全文';
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
  static const closeApprovalSheet = '关闭审批弹窗';
  static const closeDialog = '关闭弹窗';
  static const everyDay = '每天';
  static String weekday(int day) => '周$day';
  static const weekdays = <int, String>{
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    7: '周日',
  };
  static const dangerOperation = '危险操作';
  static const requiresConfirmation = '需要确认';
  static const awaitExecution = '等待执行';
  static const awaitConfirmation = '等待确认';
  static const executed = '已完成';
  static const executionFailed = '执行失败';
  static const toolExecutionFailed = '工具执行失败';
  static const executing = '执行中';
  static String attachmentExceedsLimit(String name) => '附件 $name 超过 8MB，已跳过';
  static String fileContent(String name) => '文件 $name 内容';
  static const contentTruncated = '内容已截断';
  static const imageAttachment = '[图片附件]';
  static const fileAttachment = '[文件附件]';
  static const codeCopied = '代码已复制';
  static const genericAssistant = '通用助手';
  static const youAreHelpfulAgent = '你是一个有帮助的 AI Agent。';
  static const error = '错误：';

  // --- 设置页 ---
  static const settingsHeroSubtitle = '管理模型、工具、权限与应用行为';
  static const searchSettingsPlaceholder = '搜索设置项…';
  static const llmProviderSection = 'LLM 提供商';
  static const modelProviderEntry = '模型提供商';
  static const noProviderConfiguredHint = '尚未配置，点击添加';
  static const enableDeepReasoning = '默认启用深度推理';
  static const enableDeepReasoningHint = '对支持推理的模型自动启用思考模式';
  static const deepReasoningUnsupported = '当前模型不支持深度推理';
  static const contextExtensionSection = '上下文与扩展';
  static const memorySectionTitle = '记忆';
  static const skillsSectionTitle = 'Skills 技能';
  static const mcpServersSectionTitle = 'MCP 服务器';
  static const knowledgeSectionTitle = '知识库';
  static const knowledgeSearchHint = '录入与检索文档，Agent 自动注入相关内容';
  static const scheduledTasksEntry = '定时任务';
  static const scheduledTasksSearchHint = '定时执行指定提示词的 Agent 任务';
  static const auditLogEntry = '审计日志';
  static const auditLogSubtitle = '审批追踪';
  static const auditLogSearchHint = '工具调用与审批追踪记录';
  static const toolsSectionTitle = '工具';
  static const toolListEntry = '工具列表';
  static const enableWebBrowsingTool = '启用网页浏览工具';
  static const enableWebBrowsingToolHint = '允许 Agent 搜索和读取网页内容';
  static const enableTerminalFileTool = '启用终端/文件工具';
  static const linuxEnvironmentEntry = 'Linux 工具环境';
  static const linuxEnvironmentSubtitle = 'Termux · proot · 主机终端';
  static const workspaceFilesEntry = '工作区与文件';
  static const workspaceFilesSubtitle = '导入、导出与目录访问';
  static const generalSection = '通用';
  static const appearanceAndTheme = '外观与主题';
  static const language = '语言';
  static const languageFollowSystem = '跟随系统';
  static const dataBackup = '数据备份';
  static const permissionsSection = '权限';
  static const floatingWindowPermission = '悬浮窗权限';
  static const batteryExemption = '电池优化豁免';
  static const permGranted = '已授权';
  static const permDenied = '未授权';
  static const permDisabled = '未启用';
  static const permChecking = '检查中';
  static const permUnsupported = '系统不支持';
  static const aboutSection = '关于';
  static const currentVersionLabel = '当前版本';
  static const appVersionName = 'v0.8.8';
  static const sourceCode = '源代码';
  static const openSourceLicenses = '开源许可';
  static const privacyAndCompliance = '隐私与合规';
  static const feedbackAndIssues = '意见反馈';
  static const changelog = '更新日志';
  static const onboardingGuide = '新手引导';

  static const providerSettings = '服务商设置';
  static const modelServiceConfig = '模型服务配置';
  static const quickApplyTemplate = '快速套用服务商模板';
  static const protocolType = '协议类型';
  static const savedProviders = '已保存配置';
  static const providerName = '服务商名称';
  static const baseUrl = '接口地址';
  static const modelName = '模型';
  static const apiKey = 'API 密钥';
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
  static const mcpNotConnected = '未连接';
  static String mcpConnectedCount(int count) => '$count 个已连接';
  static String knowledgeDocsSummary(int count) =>
      count > 0 ? '$count 个文档' : '未建立';
  static String scheduledTasksSummary(int count) =>
      count > 0 ? '$count 个任务' : '未创建';
  static const mcpServersSearchHint = '管理 Model Context Protocol 扩展端点';
  static const mcpServersHint = 'MCP 工具会在 Agent 执行时自动合并进工具集，风险默认需要确认。';
  static const noMcpServers = '尚未配置 MCP 服务器。';
  static const addMcpServer = '添加 MCP 服务器';
  static const editMcpServer = '编辑 MCP 服务器';
  static const deleteMcpServer = '删除 MCP 服务器';
  static const mcpServerAdded = '已添加 MCP 服务器';
  static const mcpServerSaved = '已保存修改';
  static const mcpServerDeleted = '已删除服务器';
  static const addFirstMcpServerHint = '点击右下角按钮添加你的第一个 MCP 服务。';
  static String mcpConnectionFoundTools(int count) => '连接成功：发现 $count 个工具';
  static String mcpConnectionFailed(String? error) => '连接失败：${error ?? '未知错误'}';
  static String confirmDeleteMcpServer(String name) =>
      '确定删除服务器“$name”吗？此操作不可撤销。';
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
  static const createAgent = '创建 Agent';
  static const editAgent = '编辑 Agent';
  static const agentName = '名称';
  static const systemPrompt = '系统提示词';
  static const save = '保存';
  static const newAgent = '新建 Agent';

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

  // --- 记忆 ---
  static const memory = '记忆';
  static const memoryEntry = '记忆管理';
  static const memoryHint = '长期记忆会跨会话注入，让 Agent 记住关于你的事实；数据仅存本机。';
  static const noMemories = '还没有记忆。可在对话中让 Agent「记住」某件事，或点击下方按钮手动添加。';
  static const addMemory = '添加记忆';
  static const editMemory = '编辑记忆';
  static const memoryContent = '记忆内容';
  static const memoryCategory = '分类';
  static const memoryImportance = '权重';
  static const memoryImportanceHint = '权重越高，注入时排序越靠前';
  static const memoryEnabled = '启用记忆注入';
  static const memoryEnabledHint = '关闭后不再把记忆注入到对话';

  // --- 拍照 / 分享 / 锁屏 / 更新 / 引导 ---
  static const takePhoto = '拍照';
  static const fromGallery = '相册';
  static const appLock = '应用锁（生物识别）';
  static const appLockHint = '启动或从后台返回时用指纹/面容解锁';
  static const crashReport = '崩溃上报（匿名）';
  static const crashReportHint = '仅上报匿名崩溃堆栈，不含聊天内容与密钥';
  static const checkUpdate = '检查更新';
  static const updateAvailable = '发现新版本';
  static const updateAvailableMsg = '发现新版本';
  static const updateNow = '更新';
  static const updateLater = '稍后';
  static const downloading = '下载中…';
  static const isLatestVersion = '已是最新版本';
  static const onboardingStep1 = '配置模型服务';
  static const onboardingStep2 = '选择你的模型';
  static const onboardingStep3 = '让 Agent 用工具';
  static const skip = '跳过';
  static const startUsing = '开始使用';

  // --- 任务中心与执行分析 ---
  static const taskCenter = '任务中心';
  static const developmentTasks = '开发任务';
  static const taskDetails = '任务详情';
  static const runAnalysis = '运行分析';
  static const currentRun = '当前运行';
  static const historyRuns = '历史记录';
  static const planModeActiveHint = '计划模式已开启 · 首轮需要确认';
  static const stageRequestingModel = '正在请求模型…';
  static const stageExecutingTools = '工具执行中…';
  static const stageAwaitingApproval = '等待用户审批中…';
  static const confirmAndExecutePlan = '确认并执行计划';
  static const stopExecution = '停止执行';
  static const retryFailedStep = '重试失败步骤';
  static const regeneratePlan = '重新生成计划';
  static const openAssociatedChat = '打开关联会话';
  static const startCollaboration = '发起协作分析';
  static const copyReport = '复制运行报告';

  // --- 仪表盘 ---
  static const dashboard = '仪表盘';
  static const dashboardSubtitle = 'Agent 工作负载与运行总览';
  static const todayConversations = '今日会话';
  static const todayTokens = '今日 Token';
  static const cacheHitRate = '缓存命中率';
  static const cacheHitRateHint = '今日命中缓存的 Token 占比';
  static const runningTasks = '进行中任务';
  static const taskSuccessRate = '任务成功率';
  static const taskFeedbackRate = '用户好评率';
  static String taskFeedbackSamples(int count) => '$count 个样本';
  static const taskFeedbackTitle = '任务反馈';
  static const taskFeedbackPrompt = '这个结果对你有帮助吗？';
  static const taskHelpful = '有帮助';
  static const taskNotHelpful = '没帮助';
  static const tokenTrend7Days = 'Token 用量（近 7 天）';
  static const runStatus = '运行状态';
  static const pendingActions = '待我处理';
  static const recentConversations = '最近会话';
  static const viewAll = '查看全部';
  static const noRunningRecords = '还没有运行记录，去对话页发起第一个任务';
  static const noPendingActions = '暂无待处理项';
  static const noRecentConversations = '暂无最近会话';
  static const approve = '批准';
  static const confirm = '确认';
  static const resume = '继续执行';
  static const viewUsageReport = '查看用量报告';
  static const viewTaskDetails = '查看任务详情';
  static const cacheHit = '缓存命中';
  static const cached = '缓存';
  static const promptTokens = '输入';
  static const outputTokens = '输出';
  static const cachedTokens = '缓存';
  static const callsLabel = '调用';
  static const costLabel = '预计';
  static const trendTotal = '7日合计';
  static const todayLabel = '今日';
  static const pastLabel = '历史';
  static const trendHint = '柱顶为当天输入与输出 Token 总量';
  static const refreshDashboard = '刷新仪表盘';
  static String dashboardLoadFailed(String error) => '加载仪表盘失败：$error';
  static const retry = '重试';
  static const pendingApproval = '等待审批';
  static const pendingPlanConfirm = '计划待确认';
  static const pendingResume = '可恢复任务';
  static const resumingTask = '正在恢复执行任务…';
  static const viewDetails = '查看';
  static const goTo = '前往';
  static String durationLabel(String duration) => '耗时 $duration';
  static const noTokenData = '暂无 Token 消耗数据';
}
