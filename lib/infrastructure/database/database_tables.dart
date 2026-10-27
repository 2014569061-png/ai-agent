part of 'app_database.dart';

@TableIndex(
    name: 'idx_conversations_project_updated',
    columns: {#projectId, #updatedAt})
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('新会话'))();
  TextColumn get agentId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get mode => text().withDefault(const Constant('chat'))();
  TextColumn get providerProfileId => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// 用户最后一次打开这条会话的时间；用于派生「未读」。
  /// 为空表示从未打开过（历史数据一律视为未读）。
  DateTimeColumn get lastReadAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 会话消息按会话查询 / 删除是高频路径，为 conversationId 建索引避免全表扫描。
@TableIndex(
    name: 'idx_messages_conversation', columns: {#conversationId, #createdAt})
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get toolCallId => text().nullable()();
  TextColumn get toolCallsJson => text().nullable()();
  TextColumn get reasoningContent => text().nullable()();
  TextColumn get displayMetadataJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 长期记忆（跨会话）。本地优先，符合隐私叙事；注入时按权重/更新时间排序并截断。
@TableIndex(name: 'idx_memories_enabled', columns: {#enabled})
class Memories extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  TextColumn get sourceConversationId => text().nullable()();
  TextColumn get sourceType => text().withDefault(const Constant('manual'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get importance => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Agents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get systemPrompt =>
      text().withDefault(const Constant('你是一个有帮助的 AI Agent。'))();
  TextColumn get modelProfileId => text()();
  TextColumn get enabledToolsJson => text().withDefault(const Constant('[]'))();
  RealColumn get temperature => real().withDefault(const Constant(0.7))();
  IntColumn get maxTokens => integer().withDefault(const Constant(2048))();
  IntColumn get maxSteps => integer().withDefault(const Constant(8))();
  RealColumn get topP => real().withDefault(const Constant(1.0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PromptTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get content => text()();
  TextColumn get category => text().withDefault(const Constant('通用'))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ModelProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get modelName => text()();
  TextColumn get apiKeyRef => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 后台任务持久化（C2）：记录 Agent / 定时任务的运行状态与请求快照，用于断点恢复。
@TableIndex(name: 'idx_tasks_status_updated', columns: {#status, #updatedAt})
@TableIndex(
    name: 'idx_tasks_project_updated', columns: {#projectId, #updatedAt})
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get projectId => text().nullable()();
  IntColumn get stateRevision => integer().withDefault(const Constant(0))();
  TextColumn get type => text().withDefault(const Constant('agent'))();
  TextColumn get status => text().withDefault(const Constant('running'))();
  TextColumn get requestJson => text()();
  TextColumn get progressJson => text().withDefault(const Constant('{}'))();
  IntColumn get resumeCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'idx_projects_updated', columns: {#archived, #updatedAt})
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get canonicalRootPath => text()();
  TextColumn get sourceKind =>
      text().withDefault(const Constant('directory'))();
  TextColumn get projectKind => text().withDefault(const Constant('unknown'))();
  TextColumn get runtimePreference => text().nullable()();
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();
  IntColumn get settingsVersion => integer().withDefault(const Constant(1))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Drafts extends Table {
  TextColumn get draftKey => text()();
  TextColumn get conversationId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get attachmentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get referencesJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {draftKey};
}

@TableIndex(
    name: 'idx_run_controls_run_sequence', columns: {#runId, #sequenceNo})
@TableIndex(
    name: 'idx_run_controls_client', columns: {#clientControlId}, unique: true)
class RunControls extends Table {
  TextColumn get id => text()();
  TextColumn get clientControlId => text()();
  TextColumn get taskId => text()();
  TextColumn get runId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get sequenceNo => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get consumedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ExecutionLeases extends Table {
  TextColumn get resourceKey => text()();
  TextColumn get taskId => text()();
  TextColumn get runId => text()();
  TextColumn get ownerToken => text()();
  IntColumn get generation => integer().withDefault(const Constant(0))();
  DateTimeColumn get heartbeatAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {resourceKey};
}

/// 用户对已结束开发任务结果的最小反馈记录。每个任务最多一条，可反复修改。
class TaskFeedback extends Table {
  TextColumn get taskId => text()();
  TextColumn get runId => text().nullable()();
  BoolColumn get helpful => boolean()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {taskId};
}

/// v0.9 协作分析运行状态、计划与总结。
@TableIndex(
    name: 'idx_collaboration_runs_task_updated', columns: {#taskId, #updatedAt})
class CollaborationRuns extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  TextColumn get status => text()();
  IntColumn get budgetTokens => integer().withDefault(const Constant(4000))();
  IntColumn get consumedTokens => integer().withDefault(const Constant(0))();
  IntColumn get maxAgents => integer().withDefault(const Constant(3))();
  IntColumn get maxRounds => integer().withDefault(const Constant(1))();
  IntColumn get currentRound => integer().withDefault(const Constant(0))();
  TextColumn get planJson => text().withDefault(const Constant('{}'))();
  TextColumn get resultJson => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v0.9 子 Agent 的角色运行记录，按 run + round 幂等。
@TableIndex(
    name: 'idx_collaboration_agent_runs_run_round',
    columns: {#collaborationRunId, #round})
class CollaborationAgentRuns extends Table {
  TextColumn get id => text()();
  TextColumn get collaborationRunId => text()();
  TextColumn get role => text()();
  TextColumn get agentProfileId => text().nullable()();
  TextColumn get status => text()();
  IntColumn get round => integer().withDefault(const Constant(1))();
  TextColumn get contextManifest => text().withDefault(const Constant('[]'))();
  TextColumn get allowedTools => text().withDefault(const Constant('[]'))();
  TextColumn get inputDigest => text().withDefault(const Constant(''))();
  TextColumn get outputSummary => text().nullable()();
  TextColumn get failureReason => text().nullable()();
  IntColumn get inputTokens => integer().withDefault(const Constant(0))();
  IntColumn get outputTokens => integer().withDefault(const Constant(0))();
  IntColumn get cachedTokens => integer().withDefault(const Constant(0))();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v0.9 子 Agent 提交的结构化产物。
@TableIndex(
    name: 'idx_collaboration_artifacts_run_created',
    columns: {#collaborationRunId, #createdAt})
class CollaborationArtifacts extends Table {
  TextColumn get id => text()();
  TextColumn get collaborationRunId => text()();
  TextColumn get producerAgentRunId => text()();
  TextColumn get type => text()();
  TextColumn get payloadJson => text()();
  TextColumn get evidenceRefs => text().withDefault(const Constant('[]'))();
  RealColumn get confidence => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v0.9 协作讨论的脱敏消息摘要。
@TableIndex(
    name: 'idx_collaboration_messages_run_round',
    columns: {#collaborationRunId, #round})
class CollaborationMessages extends Table {
  TextColumn get id => text()();
  TextColumn get collaborationRunId => text()();
  TextColumn get senderAgentRunId => text().nullable()();
  TextColumn get recipientRole => text().nullable()();
  IntColumn get round => integer().withDefault(const Constant(1))();
  TextColumn get contentDigest => text().withDefault(const Constant(''))();
  TextColumn get content => text()();
  TextColumn get artifactRefs => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 云同步元数据（D1）：记录各业务行的版本号与脏标记。
/// 注：多设备云同步功能已于 2026-09-10 移除，此表保留未启用（避免
/// schemaVersion 迁移风险），未来若重新启用同步可继续复用。
class SyncMeta extends Table {
  TextColumn get objectId => text()();
  TextColumn get table => text()();
  TextColumn get rowJson => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {objectId};
}

/// 知识库文档（C4）。
class KnowledgeDocs extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get sourceType => text()();
  IntColumn get chunkCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 知识库分块（C4）：chunk 存 embedding 序列化 JSON，本地计算余弦相似度。
class KnowledgeChunks extends Table {
  TextColumn get id => text()();
  TextColumn get docId => text()();
  TextColumn get content => text()();
  TextColumn get embeddingJson => text().nullable()();
  IntColumn get index => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 定时任务（C5）。
@TableIndex(name: 'idx_scheduled_tasks_enabled', columns: {#enabled})
class ScheduledTasks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get prompt => text()();
  TextColumn get cron => text()();
  TextColumn get agentId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get lastResult => text().nullable()();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 审计日志（G2）：记录工具调用审批的决策链路。
@TableIndex(name: 'idx_audit_logs_created', columns: {#createdAt})
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get detail => text()();
  TextColumn get decision => text().nullable()();
  TextColumn get risk => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Agent 单次运行摘要，用于任务级可观测性。
@TableIndex(name: 'idx_run_records_started', columns: {#startedAt})
class RunRecords extends Table {
  TextColumn get runId => text()();
  TextColumn get conversationId => text()();
  TextColumn get taskId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get model => text().withDefault(const Constant('unknown'))();
  TextColumn get status => text().withDefault(const Constant('running'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get inputTokens => integer().withDefault(const Constant(0))();
  IntColumn get outputTokens => integer().withDefault(const Constant(0))();
  IntColumn get cachedTokens => integer().withDefault(const Constant(0))();
  IntColumn get estimatedCostCents => integer().nullable()();
  IntColumn get eventCount => integer().withDefault(const Constant(0))();
  IntColumn get totalDurationMs => integer().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get firstTokenDurationMs => integer().nullable()();

  /// Output rate in tokens/sec multiplied by 1000 for stable SQLite storage.
  IntColumn get outputRateMilli => integer().nullable()();
  IntColumn get maxStallDurationMs => integer().nullable()();
  IntColumn get stallCount => integer().nullable()();
  IntColumn get cancelDurationMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {runId};
}

/// Agent 运行步骤，按 sequenceNo 回放。
@TableIndex(
    name: 'idx_run_events_run_sequence',
    columns: {#runId, #sequenceNo},
    unique: true)
class RunEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get runId => text()();
  IntColumn get sequenceNo => integer()();
  TextColumn get type => text()();
  TextColumn get status => text()();
  TextColumn get name => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get inputSummary => text().nullable()();
  TextColumn get outputSummary => text().nullable()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {eventId};
}

/// 面向用户的诊断日志，默认只保存脱敏摘要。
@TableIndex(name: 'idx_log_records_run_created', columns: {#runId, #createdAt})
@TableIndex(
    name: 'idx_log_records_level_created', columns: {#level, #createdAt})
class LogRecords extends Table {
  TextColumn get logId => text()();
  TextColumn get runId => text().nullable()();
  TextColumn get eventId => text().nullable()();
  TextColumn get level => text()();
  TextColumn get category => text()();
  TextColumn get message => text()();
  TextColumn get detailJson => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get stackTrace => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get retryable => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {logId};
}

/// 插件市场（C6）：声明式工具包 / Agent 预设包。
class Plugins extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  TextColumn get manifestJson => text()();
  TextColumn get version => text().withDefault(const Constant('1.0.0'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Skill 市场（GitHub Skill 包）：只保存指令 + 静态资源的安装记录。
class SkillPacks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get author => text().nullable()();
  TextColumn get version => text().withDefault(const Constant('0.0.1'))();
  TextColumn get source => text()();
  TextColumn get repo => text()();
  TextColumn get ref => text()();
  TextColumn get subPath => text().nullable()();
  TextColumn get installRoot => text()();
  TextColumn get fileListJson => text().withDefault(const Constant('[]'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get installedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get sha256 => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// MCP 服务器配置。参数以 JSON 数组存储，便于同时支持 HTTP 与本地 stdio。
class McpServers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  TextColumn get url => text().nullable()();
  TextColumn get command => text().nullable()();
  TextColumn get args => text().withDefault(const Constant('[]'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 账号/额度本地缓存（§5.2）。Feature Flag 与权益状态离线兜底。
class AccountMeta extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  BoolColumn get isPro => boolean().withDefault(const Constant(false))();
  TextColumn get balanceCents => text().withDefault(const Constant('0'))();
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
