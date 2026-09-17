import 'dart:convert';

import 'package:drift/drift.dart';
import 'database_executor.dart';

part 'app_database.g.dart';

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
@TableIndex(name: 'idx_tasks_project_updated', columns: {#projectId, #updatedAt})
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

@TableIndex(
    name: 'idx_projects_updated', columns: {#archived, #updatedAt})
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get canonicalRootPath => text()();
  TextColumn get sourceKind => text().withDefault(const Constant('directory'))();
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
    name: 'idx_run_controls_run_sequence',
    columns: {#runId, #sequenceNo})
@TableIndex(
    name: 'idx_run_controls_client',
    columns: {#clientControlId},
    unique: true)
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

@DriftDatabase(tables: [
  Conversations,
  Messages,
  Agents,
  PromptTemplates,
  ModelProfiles,
  Memories,
  Tasks,
  Projects,
  Drafts,
  RunControls,
  ExecutionLeases,
  TaskFeedback,
  SyncMeta,
  KnowledgeDocs,
  KnowledgeChunks,
  ScheduledTasks,
  AuditLogs,
  Plugins,
  SkillPacks,
  McpServers,
  AccountMeta,
  RunRecords,
  RunEvents,
  LogRecords,
  CollaborationRuns,
  CollaborationAgentRuns,
  CollaborationArtifacts,
  CollaborationMessages,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 23;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_active_path '
            'ON projects (canonical_root_path) WHERE archived = 0',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_projects_updated '
            'ON projects (archived, updated_at)',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_run_controls_client '
            'ON run_controls (client_control_id)',
          );
          await customStatement(
            'CREATE TABLE IF NOT EXISTS artifacts ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'project_id TEXT NOT NULL, '
            'task_id TEXT NOT NULL, '
            'run_id TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'relative_path TEXT NOT NULL, '
            'hash TEXT NOT NULL, '
            'bytes INTEGER NOT NULL DEFAULT 0, '
            'inspection_json TEXT NOT NULL DEFAULT \'{}\', '
            'created_at TEXT NOT NULL)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_artifacts_project_created '
            'ON artifacts (project_id, created_at)',
          );
          await _ensurePendingApprovals();
        },
        onUpgrade: (m, from, to) async {
          Future<bool> hasTable(String tableName) async {
            final rows = await customSelect(
              'SELECT name FROM sqlite_master '
              'WHERE type = \'table\' AND name = ?',
              variables: [Variable<String>(tableName)],
            ).get();
            return rows.isNotEmpty;
          }

          Future<bool> hasColumn(String tableName, String columnName) async {
            final rows = await customSelect(
              'PRAGMA table_info($tableName)',
            ).get();
            return rows.any((row) => row.data['name'] == columnName);
          }

          if (from < 2) {
            await m.addColumn(conversations, conversations.isPinned);
            await m.addColumn(conversations, conversations.isFavorite);
            await m.addColumn(agents, agents.topP);
            await m.createTable(promptTemplates);
          }
          if (from < 3) {
            await m.addColumn(messages, messages.toolCallsJson);
          }
          if (from < 4) {
            // Keep migrations compatible with the generated Drift schema while
            // build_runner is unavailable in constrained environments.
            await customStatement(
              "ALTER TABLE conversations ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
            );
          }
          if (from < 5) {
            await m.createIndex(idxMessagesConversation);
          }
          if (from < 6) {
            await m.createTable(memories);
            await m.addColumn(messages, messages.reasoningContent);
          }
          if (from < 7) {
            await m.createTable(tasks);
            await m.createTable(syncMeta);
          }
          if (from < 8) {
            await m.createTable(knowledgeDocs);
            await m.createTable(knowledgeChunks);
            await m.createTable(scheduledTasks);
            await m.createTable(auditLogs);
            await m.createTable(plugins);
          }
          if (from < 9) {
            await m.createTable(mcpServers);
          }
          if (from < 10) {
            // 账号/额度本地缓存（无需 build_runner 的兜底方式）
            await customStatement(
              "CREATE TABLE IF NOT EXISTS account_meta (id TEXT NOT NULL PRIMARY KEY, "
              "user_id TEXT, is_pro INTEGER NOT NULL DEFAULT 0, "
              "balance_cents TEXT NOT NULL DEFAULT '0', "
              "config_json TEXT NOT NULL DEFAULT '{}', "
              "updated_at TEXT NOT NULL)",
            );
          }
          if (from < 11) {
            // Skill 市场：GitHub Skill 包本地安装记录（不含可执行代码）。
            await m.createTable(skillPacks);
          }
          if (from < 12) {
            // The generated RunRecords table already contains columns added
            // by later migrations. Guard table creation for interrupted or
            // partially completed upgrades.
            if (!await hasTable('run_records')) {
              await m.createTable(runRecords);
            }
            if (!await hasTable('run_events')) {
              await m.createTable(runEvents);
            }
            if (!await hasTable('log_records')) {
              await m.createTable(logRecords);
            }
          }
          if (from < 13) {
            if (!await hasColumn('run_records', 'total_duration_ms')) {
              await m.addColumn(runRecords, runRecords.totalDurationMs);
            }
            if (!await hasColumn('run_records', 'retry_count')) {
              await m.addColumn(runRecords, runRecords.retryCount);
            }
          }
          if (from < 14) {
            if (!await hasColumn('run_records', 'first_token_duration_ms')) {
              await m.addColumn(runRecords, runRecords.firstTokenDurationMs);
            }
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_run_events_run_sequence '
              'ON run_events (run_id, sequence_no)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_log_records_run_created '
              'ON log_records (run_id, created_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_log_records_level_created '
              'ON log_records (level, created_at)',
            );
          }
          if (from < 15) {
            if (!await hasTable('collaboration_runs')) {
              await m.createTable(collaborationRuns);
            }
            if (!await hasTable('collaboration_agent_runs')) {
              await m.createTable(collaborationAgentRuns);
            }
            if (!await hasTable('collaboration_artifacts')) {
              await m.createTable(collaborationArtifacts);
            }
            if (!await hasTable('collaboration_messages')) {
              await m.createTable(collaborationMessages);
            }
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_collaboration_runs_task_updated '
              'ON collaboration_runs (task_id, updated_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_collaboration_agent_runs_run_round '
              'ON collaboration_agent_runs (collaboration_run_id, round)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_collaboration_artifacts_run_created '
              'ON collaboration_artifacts (collaboration_run_id, created_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_collaboration_messages_run_round '
              'ON collaboration_messages (collaboration_run_id, round)',
            );
          }
          if (from < 16) {
            if (!await hasColumn('run_records', 'output_rate_milli')) {
              await m.addColumn(runRecords, runRecords.outputRateMilli);
            }
            if (!await hasColumn('run_records', 'max_stall_duration_ms')) {
              await m.addColumn(runRecords, runRecords.maxStallDurationMs);
            }
            if (!await hasColumn('run_records', 'stall_count')) {
              await m.addColumn(runRecords, runRecords.stallCount);
            }
            if (!await hasColumn('run_records', 'cancel_duration_ms')) {
              await m.addColumn(runRecords, runRecords.cancelDurationMs);
            }
          }
          if (from < 17) {
            // B-4：补齐热查询索引 —— 任务恢复按 (status, updatedAt)、Agent 过滤按
            // enabled、消息列表按 (conversationId, createdAt) 免排序、审计/运行记录
            // 按时间清理。同名消息索引从单列重建为复合，需先删旧索引。
            await customStatement(
                'DROP INDEX IF EXISTS idx_messages_conversation');
            await m.createIndex(idxMessagesConversation);
            await m.createIndex(idxTasksStatusUpdated);
            await m.createIndex(idxMemoriesEnabled);
            await m.createIndex(idxScheduledTasksEnabled);
            await m.createIndex(idxAuditLogsCreated);
            await m.createIndex(idxRunRecordsStarted);
          }
          if (from < 18) {
            if (!await hasColumn('scheduled_tasks', 'last_run_at')) {
              await m.addColumn(scheduledTasks, scheduledTasks.lastRunAt);
            }
          }
          if (from < 19) {
            await customStatement(
              'CREATE TABLE IF NOT EXISTS task_feedback ('
              'task_id TEXT NOT NULL PRIMARY KEY, '
              'run_id TEXT, '
              'helpful INTEGER NOT NULL, '
              'created_at TEXT NOT NULL, '
              'updated_at TEXT NOT NULL)',
            );
          }
          if (from < 20) {
            if (!await hasTable('projects')) {
              await m.createTable(projects);
            }
            if (!await hasTable('drafts')) {
              await m.createTable(drafts);
            }
            if (await hasTable('conversations')) {
              if (!await hasColumn('conversations', 'project_id')) {
                await m.addColumn(conversations, conversations.projectId);
              }
              if (!await hasColumn('conversations', 'mode')) {
                await m.addColumn(conversations, conversations.mode);
              }
              if (!await hasColumn('conversations', 'provider_profile_id')) {
                await m.addColumn(
                    conversations, conversations.providerProfileId);
              }
            }
            if (await hasTable('tasks')) {
              if (!await hasColumn('tasks', 'project_id')) {
                await m.addColumn(tasks, tasks.projectId);
              }
              if (!await hasColumn('tasks', 'state_revision')) {
                await m.addColumn(tasks, tasks.stateRevision);
              }
            }
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_active_path '
              'ON projects (canonical_root_path) WHERE archived = 0',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_projects_updated '
              'ON projects (archived, updated_at)',
            );
            if (await hasTable('conversations')) {
              await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_conversations_project_updated '
                'ON conversations (project_id, updated_at)',
              );
            }
            if (await hasTable('tasks')) {
              await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_tasks_project_updated '
                'ON tasks (project_id, updated_at)',
              );
            }
          }
          if (from < 21) {
            if (!await hasTable('run_controls')) {
              await m.createTable(runControls);
            }
            if (!await hasTable('execution_leases')) {
              await m.createTable(executionLeases);
            }
            if (await hasTable('run_records')) {
              if (!await hasColumn('run_records', 'task_id')) {
                await m.addColumn(runRecords, runRecords.taskId);
              }
              if (!await hasColumn('run_records', 'project_id')) {
                await m.addColumn(runRecords, runRecords.projectId);
              }
            }
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_run_controls_client '
              'ON run_controls (client_control_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_run_controls_run_sequence '
              'ON run_controls (run_id, sequence_no)',
            );
          }
          if (from < 22) {
            await customStatement(
              'CREATE TABLE IF NOT EXISTS artifacts ('
              'id TEXT NOT NULL PRIMARY KEY, '
              'project_id TEXT NOT NULL, '
              'task_id TEXT NOT NULL, '
              'run_id TEXT NOT NULL, '
              'kind TEXT NOT NULL, '
              'relative_path TEXT NOT NULL, '
              'hash TEXT NOT NULL, '
              'bytes INTEGER NOT NULL DEFAULT 0, '
              'inspection_json TEXT NOT NULL DEFAULT \'{}\', '
              'created_at TEXT NOT NULL)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_artifacts_project_created '
              'ON artifacts (project_id, created_at)',
            );
          }
          if (from < 23) {
            await _ensurePendingApprovals();
          }
        },
      );

  /// 建 pending_approvals 表与索引（锁屏审批的决策通道）。
  ///
  /// onCreate 与 onUpgrade 共用同一段 SQL，避免两条路径漂移——历史教训是
  /// 「onCreate 建了表、onUpgrade 忘了建」，结果是全新安装正常、升级用户永远缺表。
  ///
  /// 用裸 SQL 而不是 Drift 表类：`artifacts` 已是同样的先例，可以避免为一张只有
  /// 几个字段的临时表重新跑 build_runner 生成 app_database.g.dart。
  Future<void> _ensurePendingApprovals() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS pending_approvals ('
      'request_id TEXT NOT NULL PRIMARY KEY, '
      'tool_name TEXT NOT NULL, '
      'summary TEXT NOT NULL DEFAULT \'\', '
      'risk TEXT NOT NULL DEFAULT \'\', '
      'decision TEXT, '
      'decided_at TEXT, '
      'created_at TEXT NOT NULL, '
      'expires_at TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pending_approvals_created '
      'ON pending_approvals (created_at)',
    );
  }

  // --- 锁屏审批的决策通道 ---
  //
  // 用途：应用不在前台（锁屏 / 切到别的应用）时，弹窗用户根本看不见，需审批的
  // 工具会一直等下去。这条通道把审批请求落库，由带动作的通知让用户直接裁决，
  // 后台 isolate 把结果写回同一行，前台轮询取走。
  //
  // ⚠️ 这些行是**一次性握手**数据（分钟级过期），刻意不进保险箱备份：把几分钟前
  // 的审批决定恢复到新设备上是错误的。

  Future<void> insertPendingApproval({
    required String requestId,
    required String toolName,
    required String summary,
    required String risk,
    required Duration ttl,
  }) async {
    final now = DateTime.now();
    await customInsert(
      'INSERT OR REPLACE INTO pending_approvals '
      '(request_id, tool_name, summary, risk, decision, decided_at, created_at, expires_at) '
      'VALUES (?, ?, ?, ?, NULL, NULL, ?, ?)',
      variables: [
        Variable<String>(requestId),
        Variable<String>(toolName),
        Variable<String>(summary),
        Variable<String>(risk),
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.add(ttl).toIso8601String()),
      ],
    );
  }

  /// 返回 'approve' / 'deny'；未决或不存在时返回 null。
  Future<String?> findPendingApprovalDecision(String requestId) async {
    final rows = await customSelect(
      'SELECT decision FROM pending_approvals WHERE request_id = ?',
      variables: [Variable<String>(requestId)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data['decision'] as String?;
  }

  /// 写入决定，**只有第一条生效**（`decision IS NULL` 作为哨兵）。
  /// 这样锁屏动作与前台弹窗几乎同时提交时不会互相覆盖，返回 false 表示已有决定。
  Future<bool> decidePendingApproval(String requestId, String decision) async {
    final affected = await customUpdate(
      'UPDATE pending_approvals SET decision = ?, decided_at = ? '
      'WHERE request_id = ? AND decision IS NULL',
      variables: [
        Variable<String>(decision),
        Variable<String>(DateTime.now().toIso8601String()),
        Variable<String>(requestId),
      ],
      updateKind: UpdateKind.update,
    );
    return affected > 0;
  }

  Future<void> deletePendingApproval(String requestId) async {
    await customUpdate(
      'DELETE FROM pending_approvals WHERE request_id = ?',
      variables: [Variable<String>(requestId)],
      updateKind: UpdateKind.delete,
    );
  }

  /// 清理已过期的一次性记录（包括用户一直没处理、早已无人等待的那些）。
  Future<int> prunePendingApprovals() => customUpdate(
        'DELETE FROM pending_approvals WHERE expires_at < ?',
        variables: [Variable<String>(DateTime.now().toIso8601String())],
        updateKind: UpdateKind.delete,
      );

  /// [limit]/[offset] 供列表页分页（B-2）：热路径（抽屉、启动恢复）必须显式限流，
  /// 不传则全量 —— 保险箱导出等确实需要完整数据的场景保持原语义。
  Future<List<Conversation>> recentConversations({int? limit, int offset = 0}) {
    final query = select(conversations)
      ..orderBy([
        (row) => OrderingTerm.desc(row.isPinned),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    if (limit != null) query.limit(limit, offset: offset);
    return query.get();
  }

  /// [since] 之后"活跃过"（更新或新建）的会话，按置顶 + 更新时间倒序。
  /// 供仪表盘统计今日会话与最近会话，避免无 limit 拉全表。
  Future<List<Conversation>> conversationsSince(DateTime since) =>
      (select(conversations)
            ..where((row) =>
                row.updatedAt.isBiggerOrEqualValue(since) |
                row.createdAt.isBiggerOrEqualValue(since))
            ..orderBy([
              (row) => OrderingTerm.desc(row.isPinned),
              (row) => OrderingTerm.desc(row.updatedAt),
            ]))
          .get();

  Stream<List<Message>> watchMessages(String conversationId) =>
      (select(messages)
            ..where((row) => row.conversationId.equals(conversationId))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .watch();

  Future<void> saveConversation(Conversation conversation) =>
      into(conversations).insertOnConflictUpdate(conversation);

  Future<void> insertConversation(ConversationsCompanion conversation) =>
      into(conversations).insertOnConflictUpdate(conversation);

  Future<void> saveMessage(Message message) =>
      into(messages).insertOnConflictUpdate(message);

  Future<void> insertMessage(MessagesCompanion message) =>
      into(messages).insertOnConflictUpdate(message);

  Future<Conversation?> findConversation(String id) =>
      (select(conversations)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<void> deleteConversation(String id) async {
    await transaction(() async {
      final linkedTasks = await (select(tasks)
            ..where((row) => row.conversationId.equals(id)))
          .get();
      final taskIds =
          linkedTasks.map((task) => task.id).toList(growable: false);
      await _deleteCollaborationForTasks(taskIds);
      if (taskIds.isNotEmpty) {
        await (delete(taskFeedback)..where((row) => row.taskId.isIn(taskIds)))
            .go();
        await (delete(tasks)..where((row) => row.id.isIn(taskIds))).go();
      }
      final runs = await (select(runRecords)
            ..where((row) => row.conversationId.equals(id)))
          .get();
      final runIds = runs.map((run) => run.runId).toList(growable: false);
      if (runIds.isNotEmpty) {
        await (delete(logRecords)..where((row) => row.runId.isIn(runIds))).go();
        await (delete(runEvents)..where((row) => row.runId.isIn(runIds))).go();
        await (delete(runRecords)..where((row) => row.runId.isIn(runIds))).go();
      }
      // 会话删除必须同步清理审批/敏感工具轨迹，避免导出和审计页残留可关联信息。
      await (delete(auditLogs)..where((row) => row.conversationId.equals(id)))
          .go();
      await (delete(messages)..where((row) => row.conversationId.equals(id)))
          .go();
      await (delete(conversations)..where((row) => row.id.equals(id))).go();
    });
  }

  /// [before]/[limit] 为键集分页参数（B-2）：传入 before 则只取该时刻之前的消息，
  /// 返回仍按 createdAt 升序。不传时保持全量语义（现有调用方无需改动）。
  Future<List<Message>> messagesFor(String conversationId,
      {DateTime? before, int? limit}) {
    final query = select(messages)
      ..where((row) => before == null
          ? row.conversationId.equals(conversationId)
          : (row.conversationId.equals(conversationId) &
              row.createdAt.isSmallerThanValue(before)))
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    if (limit != null) query.limit(limit);
    return query.get().then((rows) => rows.reversed.toList(growable: false));
  }

  /// UI 分页专用的键集翻页（B-2）：游标是 (createdAt, rowid) 复合。
  ///
  /// Drift 默认按「秒」存 DateTime —— 同一秒内会写入多条消息（快速工具轮很常见），
  /// 只按 createdAt 严格小于翻页会把同秒边界上的整组消息漏掉（实测复现），
  /// 因此必须带 rowid 决胜。返回升序的 (行, rowid)。
  Future<List<(Message, int)>> messagesPage(
    String conversationId, {
    DateTime? before,
    int? beforeRowId,
    int? limit,
  }) async {
    final variables = <Variable>[Variable<String>(conversationId)];
    var where = 'conversation_id = ?';
    if (before != null) {
      if (beforeRowId == null) {
        where += ' AND created_at < ?';
        variables.add(Variable<DateTime>(before));
      } else {
        where += ' AND (created_at < ? OR (created_at = ? AND rowid < ?))';
        variables
          ..add(Variable<DateTime>(before))
          ..add(Variable<DateTime>(before))
          ..add(Variable<int>(beforeRowId));
      }
    }
    final limitSql = limit == null ? '' : ' LIMIT $limit';
    final rows = await customSelect(
      'SELECT *, rowid AS page_rowid FROM messages WHERE $where '
      'ORDER BY created_at DESC, rowid DESC$limitSql',
      variables: variables,
      readsFrom: {messages},
    ).get();
    final page = <(Message, int)>[
      for (final row in rows)
        (await messages.mapFromRow(row), row.data['page_rowid'] as int),
    ];
    return page.reversed.toList(growable: false);
  }

  /// 删除最后一次用户消息之后的所有助手/工具消息（用于"重新生成"时清理上一轮结果）。
  Future<void> deleteTrailingAssistantAndTool(String conversationId) async {
    final lastUser = await (select(messages)
          ..where((row) =>
              row.conversationId.equals(conversationId) &
              row.role.equals('user'))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    final cutoff = lastUser?.createdAt;
    if (cutoff == null) return;
    await (delete(messages)
          ..where((row) =>
              row.conversationId.equals(conversationId) &
              row.createdAt.isBiggerThanValue(cutoff) &
              (row.role.equals('assistant') | row.role.equals('tool'))))
        .go();
  }

  /// 编辑指定消息的内容并删除其后同会话的所有消息（用于"编辑重发"）。
  /// 按 [messagesFor] 的排序定位锚点行，逐 id 删除，避免 createdAt 相同时误删。
  Future<void> editMessageAndTruncate(
      String conversationId, String messageId, String newContent) async {
    final all = await messagesFor(conversationId);
    final index = all.indexWhere((row) => row.id == messageId);
    if (index < 0) return;
    final trailingIds =
        all.sublist(index + 1).map((row) => row.id).toList(growable: false);
    await transaction(() async {
      await (update(messages)..where((row) => row.id.equals(messageId)))
          .write(MessagesCompanion(content: Value(newContent)));
      if (trailingIds.isNotEmpty) {
        await (delete(messages)..where((row) => row.id.isIn(trailingIds))).go();
      }
    });
  }

  Future<List<Agent>> allAgents() => select(agents).get();

  Future<Agent?> findAgent(String id) =>
      (select(agents)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> saveAgent(Agent agent) =>
      into(agents).insertOnConflictUpdate(agent);

  Future<void> insertAgent(AgentsCompanion agent) =>
      into(agents).insertOnConflictUpdate(agent);

  Future<void> deleteAgent(String id) =>
      (delete(agents)..where((row) => row.id.equals(id))).go();

  Future<List<ModelProfile>> allModelProfiles() => select(modelProfiles).get();

  Future<void> saveModelProfile(ModelProfile profile) =>
      into(modelProfiles).insertOnConflictUpdate(profile);

  // --- Prompt templates ---

  Future<List<PromptTemplate>> allPromptTemplates() => (select(promptTemplates)
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
      .get();

  Future<PromptTemplate?> findPromptTemplate(String id) =>
      (select(promptTemplates)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<void> savePromptTemplate(PromptTemplate template) =>
      into(promptTemplates).insertOnConflictUpdate(template);

  Future<void> insertPromptTemplate(PromptTemplatesCompanion template) =>
      into(promptTemplates).insertOnConflictUpdate(template);

  Future<void> deletePromptTemplate(String id) =>
      (delete(promptTemplates)..where((row) => row.id.equals(id))).go();

  /// Install built-in templates once while preserving user edits and deletes.
  Future<void> ensureDefaultPromptTemplates() async {
    final now = DateTime.now();
    const defaults =
        <({String id, String name, String category, String content})>[
      (
        id: 'builtin-explain',
        name: '解释概念',
        category: '学习',
        content: '请用清晰、易懂的中文解释以下概念：\n\n{内容}\n\n先给出一句话定义，再用要点说明核心原理，并补充一个实际例子。'
      ),
      (
        id: 'builtin-summarize',
        name: '总结要点',
        category: '效率',
        content: '请总结以下内容，提炼 3-5 条关键要点，并列出需要继续跟进的事项：\n\n{内容}'
      ),
      (
        id: 'builtin-code-review',
        name: '代码审查',
        category: '编程',
        content:
            '请审查下面的代码，优先指出真实的 bug、安全风险和可维护性问题。按“严重程度、位置、原因、修改建议”输出：\n\n{代码}'
      ),
      (
        id: 'builtin-writing',
        name: '润色改写',
        category: '写作',
        content: '请在不改变原意的前提下润色下面的文字，使表达更自然、专业、简洁。直接给出修改后的版本，并简要说明主要改动：\n\n{原文}'
      ),
      (
        id: 'builtin-plan',
        name: '制定执行计划',
        category: '工作',
        content: '请把以下目标拆解成可执行的步骤，标注每一步的产出、依赖和验收标准，并指出可能的风险：\n\n{目标}'
      ),
    ];
    for (final item in defaults) {
      if (await findPromptTemplate(item.id) != null) continue;
      await insertPromptTemplate(PromptTemplatesCompanion.insert(
        id: item.id,
        name: item.name,
        content: item.content,
        category: Value(item.category),
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  // --- Memories ---

  Future<List<Memory>> allMemories() =>
      (select(memories)..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<List<Memory>> enabledMemories() => (select(memories)
        ..where((row) => row.enabled.equals(true))
        ..orderBy([
          (row) => OrderingTerm.desc(row.importance),
          (row) => OrderingTerm.desc(row.updatedAt),
        ]))
      .get();

  Future<Memory?> findMemory(String id) =>
      (select(memories)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> saveMemory(Memory memory) =>
      into(memories).insertOnConflictUpdate(memory);

  Future<void> insertMemory(MemoriesCompanion memory) =>
      into(memories).insertOnConflictUpdate(memory);

  Future<void> deleteMemory(String id) =>
      (delete(memories)..where((row) => row.id.equals(id))).go();

  // --- 项目与草稿（开发落地方案 T01）---

  Future<List<Project>> allProjects({bool includeArchived = false}) {
    final query = select(projects)
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    if (!includeArchived) {
      query.where((row) => row.archived.equals(false));
    }
    return query.get();
  }

  Future<Project?> findProject(String id) =>
      (select(projects)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<Project?> findProjectByCanonicalPath(String path) =>
      (select(projects)
            ..where((row) =>
                row.canonicalRootPath.equals(path) &
                row.archived.equals(false)))
          .getSingleOrNull();

  Future<void> saveProject(Project project) =>
      into(projects).insertOnConflictUpdate(project);

  Future<void> insertProject(ProjectsCompanion project) =>
      into(projects).insertOnConflictUpdate(project);

  Future<List<Conversation>> conversationsForProject(String projectId) =>
      (select(conversations)
            ..where((row) => row.projectId.equals(projectId))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<List<Task>> tasksForProject(String projectId, {int limit = 50}) =>
      (select(tasks)
            ..where((row) => row.projectId.equals(projectId))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
            ..limit(limit))
          .get();

  Future<void> saveRunControl(RunControl row) =>
      into(runControls).insertOnConflictUpdate(row);

  Future<RunControl?> findRunControlByClientId(String clientControlId) =>
      (select(runControls)
            ..where((row) => row.clientControlId.equals(clientControlId)))
          .getSingleOrNull();

  Future<List<RunControl>> pendingRunControls({
    required String taskId,
    String? runId,
  }) {
    final query = select(runControls)
      ..where((row) =>
          row.taskId.equals(taskId) & row.status.equals('pending'))
      ..orderBy([(row) => OrderingTerm.asc(row.sequenceNo)]);
    if (runId != null && runId.isNotEmpty) {
      query.where((row) => row.runId.equals(runId) | row.runId.isNull());
    }
    return query.get();
  }

  Future<int> nextRunControlSequence(String taskId) async {
    final rows = await (select(runControls)
          ..where((row) => row.taskId.equals(taskId))
          ..orderBy([(row) => OrderingTerm.desc(row.sequenceNo)])
          ..limit(1))
        .get();
    if (rows.isEmpty) return 1;
    return rows.first.sequenceNo + 1;
  }

  Future<void> saveExecutionLease(ExecutionLease row) =>
      into(executionLeases).insertOnConflictUpdate(row);

  Future<ExecutionLease?> findExecutionLease(String resourceKey) =>
      (select(executionLeases)
            ..where((row) => row.resourceKey.equals(resourceKey)))
          .getSingleOrNull();

  Future<void> deleteExecutionLease(String resourceKey) =>
      (delete(executionLeases)
            ..where((row) => row.resourceKey.equals(resourceKey)))
          .go();

  Future<Draft?> findDraft(String draftKey) =>
      (select(drafts)..where((row) => row.draftKey.equals(draftKey)))
          .getSingleOrNull();

  Future<void> saveDraft(Draft draft) =>
      into(drafts).insertOnConflictUpdate(draft);

  Future<void> deleteDraft(String draftKey) =>
      (delete(drafts)..where((row) => row.draftKey.equals(draftKey))).go();

  Future<void> saveArtifactRecord(Map<String, dynamic> row) async {
    await customStatement(
      'INSERT OR REPLACE INTO artifacts '
      '(id, project_id, task_id, run_id, kind, relative_path, hash, bytes, inspection_json, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        row['id'],
        row['projectId'],
        row['taskId'],
        row['runId'],
        row['kind'],
        row['relativePath'],
        row['hash'],
        row['bytes'] ?? 0,
        row['inspectionJson'] is String
            ? row['inspectionJson']
            : jsonEncode(row['inspectionJson'] ?? const {}),
        row['createdAt'],
      ],
    );
  }

  Future<List<Map<String, dynamic>>> artifactsForProject(String projectId) async {
    final rows = await customSelect(
      'SELECT * FROM artifacts WHERE project_id = ? ORDER BY created_at DESC',
      variables: [Variable<String>(projectId)],
    ).get();
    return [
      for (final row in rows)
        {
          'id': row.data['id'],
          'projectId': row.data['project_id'],
          'taskId': row.data['task_id'],
          'runId': row.data['run_id'],
          'kind': row.data['kind'],
          'relativePath': row.data['relative_path'],
          'hash': row.data['hash'],
          'bytes': row.data['bytes'],
          'inspectionJson': row.data['inspection_json'],
          'createdAt': row.data['created_at'],
        }
    ];
  }

  Future<List<Map<String, dynamic>>> allArtifactRecords() async {
    final rows = await customSelect(
      'SELECT * FROM artifacts ORDER BY created_at DESC',
    ).get();
    return [
      for (final row in rows)
        {
          'id': row.data['id'],
          'projectId': row.data['project_id'],
          'taskId': row.data['task_id'],
          'runId': row.data['run_id'],
          'kind': row.data['kind'],
          'relativePath': row.data['relative_path'],
          'hash': row.data['hash'],
          'bytes': row.data['bytes'],
          'inspectionJson': row.data['inspection_json'],
          'createdAt': row.data['created_at'],
        }
    ];
  }

  // --- 后台任务（C2）---

  Future<List<Task>> runningTasks() => (select(tasks)
        ..where((row) => row.status.equals('running'))
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
      .get();

  /// 可恢复任务：进程被杀遗留的 running + 预算暂停的 paused 都要给恢复入口，
  /// 否则 paused 任务（resumeTask 本身支持）永远无法被用户发现。
  Future<List<Task>> resumableTasks() => (select(tasks)
        ..where((row) => row.status.isIn(const ['running', 'paused']))
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
      .get();

  Future<List<Task>> allTasks({int limit = 100}) => (select(tasks)
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
        ..limit(limit))
      .get();

  /// [since] 后更新过的任务，按 updatedAt 倒序。
  /// 供仪表盘成功率/待办统计，避免 allTasks 固定 100 条导致窗口失真。
  Future<List<Task>> tasksSince(DateTime since, {int limit = 2000}) =>
      (select(tasks)
            ..where((row) => row.updatedAt.isBiggerOrEqualValue(since))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
            ..limit(limit))
          .get();

  Future<Task?> findTask(String id) =>
      (select(tasks)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> saveTask(Task task) => into(tasks).insertOnConflictUpdate(task);

  Future<void> insertTask(TasksCompanion task) =>
      into(tasks).insertOnConflictUpdate(task);

  Future<TaskFeedbackData?> feedbackForTask(String taskId) =>
      (select(taskFeedback)..where((row) => row.taskId.equals(taskId)))
          .getSingleOrNull();

  Future<void> saveTaskFeedbackRow(TaskFeedbackData row) =>
      into(taskFeedback).insertOnConflictUpdate(row);

  Future<void> saveRunRecordRow(RunRecord row) =>
      into(runRecords).insertOnConflictUpdate(row);

  Future<void> saveRunEventRow(RunEvent row) =>
      into(runEvents).insertOnConflictUpdate(row);

  Future<void> saveLogRecordRow(LogRecord row) =>
      into(logRecords).insertOnConflictUpdate(row);

  Future<void> saveAuditLog(AuditLog row) =>
      into(auditLogs).insertOnConflictUpdate(row);

  Future<void> saveTaskFeedback({
    required String taskId,
    String? runId,
    required bool helpful,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final existing = await feedbackForTask(taskId);
    await into(taskFeedback).insertOnConflictUpdate(TaskFeedbackCompanion(
      taskId: Value(taskId),
      runId: Value(runId),
      helpful: Value(helpful),
      createdAt: Value(existing?.createdAt ?? timestamp),
      updatedAt: Value(timestamp),
    ));
  }

  Future<int> taskFeedbackCount({DateTime? since}) async {
    final query = selectOnly(taskFeedback)
      ..addColumns([taskFeedback.taskId.count()]);
    if (since != null) {
      query.where(taskFeedback.updatedAt.isBiggerOrEqualValue(since));
    }
    return query
        .getSingle()
        .then((row) => row.read(taskFeedback.taskId.count()) ?? 0);
  }

  Future<int> helpfulTaskFeedbackCount({DateTime? since}) async {
    final query = selectOnly(taskFeedback)
      ..addColumns([taskFeedback.taskId.count()])
      ..where(taskFeedback.helpful.equals(true));
    if (since != null) {
      query.where(taskFeedback.updatedAt.isBiggerOrEqualValue(since));
    }
    return query
        .getSingle()
        .then((row) => row.read(taskFeedback.taskId.count()) ?? 0);
  }

  Future<int> developmentTaskFeedbackCount({DateTime? since}) =>
      _developmentTaskFeedbackCount(since: since);

  Future<int> helpfulDevelopmentTaskFeedbackCount({DateTime? since}) =>
      _developmentTaskFeedbackCount(since: since, helpfulOnly: true);

  Future<int> _developmentTaskFeedbackCount({
    DateTime? since,
    bool helpfulOnly = false,
  }) async {
    final variables = <Variable>[];
    var where = "(t.type LIKE 'development:%' OR t.type IN "
        "('project_analysis', 'bug_fix', 'code_review', 'release_check'))";
    if (helpfulOnly) where += ' AND f.helpful = 1';
    if (since != null) {
      where += ' AND f.updated_at >= ?';
      variables.add(Variable<DateTime>(since));
    }
    final row = await customSelect(
      'SELECT COUNT(*) AS count FROM task_feedback f '
      'INNER JOIN tasks t ON t.id = f.task_id WHERE $where',
      variables: variables,
      readsFrom: {taskFeedback, tasks},
    ).getSingle();
    return row.read<int>('count');
  }

  Future<void> deleteTaskFeedback(String taskId) =>
      (delete(taskFeedback)..where((row) => row.taskId.equals(taskId))).go();

  Future<void> clearTaskFeedback() => delete(taskFeedback).go();

  Future<List<TaskFeedbackData>> allTaskFeedback({int limit = 2000}) =>
      (select(taskFeedback)
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
            ..limit(limit))
          .get();

  Future<List<CollaborationAgentRun>> allCollaborationAgentRuns(
          {int limit = 2000}) =>
      (select(collaborationAgentRuns)..limit(limit)).get();

  Future<List<CollaborationArtifact>> allCollaborationArtifacts(
          {int limit = 2000}) =>
      (select(collaborationArtifacts)..limit(limit)).get();

  Future<List<CollaborationMessage>> allCollaborationMessages(
          {int limit = 2000}) =>
      (select(collaborationMessages)..limit(limit)).get();

  Future<List<AuditLog>> allAuditLogs({int limit = 2000}) =>
      (select(auditLogs)
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
            ..limit(limit))
          .get();

  Future<List<RunRecord>> allRunRecords({int limit = 2000}) =>
      (select(runRecords)
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
            ..limit(limit))
          .get();

  Future<List<RunEvent>> allRunEvents({int limit = 8000}) =>
      (select(runEvents)
            ..orderBy([
              (row) => OrderingTerm.asc(row.runId),
              (row) => OrderingTerm.asc(row.sequenceNo),
            ])
            ..limit(limit))
          .get();

  Future<List<LogRecord>> allLogRecords({int limit = 4000}) =>
      (select(logRecords)
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
            ..limit(limit))
          .get();

  // --- v0.9 协作分析 ---

  Future<CollaborationRun?> findCollaborationRun(String id) =>
      (select(collaborationRuns)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<CollaborationRun?> latestCollaborationRunForTask(String taskId) =>
      (select(collaborationRuns)
            ..where((row) => row.taskId.equals(taskId))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<List<CollaborationRun>> allCollaborationRuns({int limit = 100}) =>
      (select(collaborationRuns)
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
            ..limit(limit))
          .get();

  Stream<CollaborationRun?> watchCollaborationRun(String id) =>
      (select(collaborationRuns)..where((row) => row.id.equals(id)))
          .watchSingleOrNull();

  Future<void> saveCollaborationRun(CollaborationRun run) =>
      into(collaborationRuns).insertOnConflictUpdate(run);

  Future<List<CollaborationAgentRun>> agentRunsForCollaboration(String runId) =>
      (select(collaborationAgentRuns)
            ..where((row) => row.collaborationRunId.equals(runId))
            ..orderBy([
              (row) => OrderingTerm.asc(row.round),
              (row) => OrderingTerm.asc(row.startedAt),
            ]))
          .get();

  Stream<List<CollaborationAgentRun>> watchAgentRunsForCollaboration(
          String runId) =>
      (select(collaborationAgentRuns)
            ..where((row) => row.collaborationRunId.equals(runId))
            ..orderBy([
              (row) => OrderingTerm.asc(row.round),
              (row) => OrderingTerm.asc(row.startedAt),
            ]))
          .watch();

  Future<void> saveCollaborationAgentRun(CollaborationAgentRun run) =>
      into(collaborationAgentRuns).insertOnConflictUpdate(run);

  Future<List<CollaborationArtifact>> artifactsForCollaboration(String runId) =>
      (select(collaborationArtifacts)
            ..where((row) => row.collaborationRunId.equals(runId))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  Stream<List<CollaborationArtifact>> watchArtifactsForCollaboration(
          String runId) =>
      (select(collaborationArtifacts)
            ..where((row) => row.collaborationRunId.equals(runId))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .watch();

  Future<void> saveCollaborationArtifact(CollaborationArtifact artifact) =>
      into(collaborationArtifacts).insertOnConflictUpdate(artifact);

  Future<List<CollaborationMessage>> messagesForCollaboration(String runId) =>
      (select(collaborationMessages)
            ..where((row) => row.collaborationRunId.equals(runId))
            ..orderBy([
              (row) => OrderingTerm.asc(row.round),
              (row) => OrderingTerm.asc(row.createdAt),
            ]))
          .get();

  Future<void> saveCollaborationMessage(CollaborationMessage message) =>
      into(collaborationMessages).insertOnConflictUpdate(message);

  Future<void> updateTaskStatus(String id, String status) async {
    await (update(tasks)..where((row) => row.id.equals(id)))
        .write(TasksCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deleteTask(String id) => transaction(() async {
        await _deleteCollaborationForTasks([id]);
        await deleteTaskFeedback(id);
        await (delete(tasks)..where((row) => row.id.equals(id))).go();
      });

  /// 协作表没有依赖数据库外键，必须在删除任务时显式清理，避免审计导出
  /// 或协作时间线继续暴露已经删除任务的只读上下文与结果。
  Future<void> _deleteCollaborationForTasks(Iterable<String> taskIds) async {
    final ids = taskIds.toList(growable: false);
    if (ids.isEmpty) return;
    final runs = await (select(collaborationRuns)
          ..where((row) => row.taskId.isIn(ids)))
        .get();
    final runIds = runs.map((run) => run.id).toList(growable: false);
    if (runIds.isEmpty) return;
    await (delete(collaborationMessages)
          ..where((row) => row.collaborationRunId.isIn(runIds)))
        .go();
    await (delete(collaborationArtifacts)
          ..where((row) => row.collaborationRunId.isIn(runIds)))
        .go();
    await (delete(collaborationAgentRuns)
          ..where((row) => row.collaborationRunId.isIn(runIds)))
        .go();
    await (delete(collaborationRuns)..where((row) => row.id.isIn(runIds))).go();
  }

  // --- 云同步元数据（D1）---
  // 注：云同步功能已移除。原 dirtySyncRows / saveSyncMeta / findSyncMeta
  // 访问器因无任何调用方已一并删除；SyncMeta 表保留未启用（见表注释）。

  // --- 知识库（C4）---

  Future<List<KnowledgeDoc>> allKnowledgeDocs() => (select(knowledgeDocs)
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
      .get();

  Future<KnowledgeDoc?> findKnowledgeDoc(String id) =>
      (select(knowledgeDocs)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<void> saveKnowledgeDoc(KnowledgeDoc doc) =>
      into(knowledgeDocs).insertOnConflictUpdate(doc);

  Future<void> insertKnowledgeDoc(KnowledgeDocsCompanion doc) =>
      into(knowledgeDocs).insertOnConflictUpdate(doc);

  Future<void> deleteKnowledgeDoc(String id) async {
    await transaction(() async {
      await (delete(knowledgeChunks)..where((row) => row.docId.equals(id)))
          .go();
      await (delete(knowledgeDocs)..where((row) => row.id.equals(id))).go();
    });
  }

  Future<List<KnowledgeChunk>> chunksFor(String docId) =>
      (select(knowledgeChunks)
            ..where((row) => row.docId.equals(docId))
            ..orderBy([(row) => OrderingTerm.asc(row.index)]))
          .get();

  Future<void> saveKnowledgeChunk(KnowledgeChunk chunk) =>
      into(knowledgeChunks).insertOnConflictUpdate(chunk);

  Future<List<KnowledgeChunk>> allKnowledgeChunks() =>
      select(knowledgeChunks).get();

  // --- 定时任务（C5）---

  Future<List<ScheduledTask>> allScheduledTasks() => (select(scheduledTasks)
        ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
      .get();

  Future<ScheduledTask?> findScheduledTask(String id) =>
      (select(scheduledTasks)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<void> saveScheduledTask(ScheduledTask task) =>
      into(scheduledTasks).insertOnConflictUpdate(task);

  Future<void> insertScheduledTask(ScheduledTasksCompanion task) =>
      into(scheduledTasks).insertOnConflictUpdate(task);

  Future<void> deleteScheduledTask(String id) =>
      (delete(scheduledTasks)..where((row) => row.id.equals(id))).go();

  // --- 审计日志（G2）---

  Future<void> insertAuditLog(AuditLogsCompanion log) =>
      into(auditLogs).insert(log);

  Future<List<AuditLog>> recentAuditLogs({int limit = 200}) =>
      (select(auditLogs)
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
            ..limit(limit))
          .get();

  Future<void> pruneAuditLogs(DateTime before) => (delete(auditLogs)
        ..where((row) => row.createdAt.isSmallerThanValue(before)))
      .go();

  Future<void> insertRunRecord(RunRecordsCompanion record) =>
      into(runRecords).insertOnConflictUpdate(record);

  Future<void> updateRunRecord(String runId, RunRecordsCompanion record) =>
      (update(runRecords)..where((row) => row.runId.equals(runId)))
          .write(record);

  Future<void> insertRunEvent(RunEventsCompanion event) =>
      into(runEvents).insertOnConflictUpdate(event);

  Future<void> updateRunEvent(String eventId, RunEventsCompanion event) =>
      (update(runEvents)..where((row) => row.eventId.equals(eventId)))
          .write(event);

  Future<List<RunRecord>> recentRuns({int limit = 100}) => (select(runRecords)
        ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
        ..limit(limit))
      .get();

  /// [since] 起的运行记录，按 startedAt 倒序。
  /// 供仪表盘 7 天 Token 聚合：不再受 recentRuns 固定条数限制截断窗口。
  /// 注：runRecords 受保留策略约束（默认仅保留 30 天内 / 100 条已完成记录），
  /// 7 天窗口在该策略下通常完整，但极端高频使用仍可能被清理，属数据模型层限制。
  Future<List<RunRecord>> runsSince(DateTime since, {int limit = 2000}) =>
      (select(runRecords)
            ..where((row) => row.startedAt.isBiggerOrEqualValue(since))
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
            ..limit(limit))
          .get();

  Future<RunRecord?> findRunRecord(String runId) =>
      (select(runRecords)..where((row) => row.runId.equals(runId)))
          .getSingleOrNull();

  Stream<RunRecord?> watchRunRecord(String runId) =>
      (select(runRecords)..where((row) => row.runId.equals(runId)))
          .watch()
          .map((rows) => rows.isEmpty ? null : rows.first);

  /// Keeps completed runs from growing without bound. Active runs are always
  /// retained so a long-running task cannot disappear mid-execution.
  Future<void> pruneRunRecords({
    DateTime? now,
    int maxRuns = 100,
    Duration maxAge = const Duration(days: 30),
  }) async {
    if (maxRuns < 1) return;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    await transaction(() async {
      final staleRunningCutoff = (now ?? DateTime.now()).subtract(
        const Duration(days: 1),
      );
      await (update(runRecords)
            ..where((row) =>
                row.status.equals('running') &
                row.startedAt.isSmallerThanValue(staleRunningCutoff)))
          .write(RunRecordsCompanion(
        status: const Value('failed'),
        endedAt: Value(now ?? DateTime.now()),
      ));
      final rows = await (select(runRecords)
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
          .get();
      final keepIds = <String>{};
      var retainedCompleted = 0;
      for (final row in rows) {
        if (row.status == 'running') {
          keepIds.add(row.runId);
          continue;
        }
        if (!row.startedAt.isBefore(cutoff) && retainedCompleted < maxRuns) {
          keepIds.add(row.runId);
          retainedCompleted++;
        }
      }
      final removeIds = rows
          .where((row) => !keepIds.contains(row.runId))
          .map((row) => row.runId)
          .toList(growable: false);
      if (removeIds.isEmpty) return;
      await (delete(logRecords)..where((row) => row.runId.isIn(removeIds)))
          .go();
      await (delete(runEvents)..where((row) => row.runId.isIn(removeIds))).go();
      await (delete(runRecords)..where((row) => row.runId.isIn(removeIds)))
          .go();
    });
  }

  Future<List<RunEvent>> eventsForRun(String runId,
          {int limit = 50, int offset = 0}) =>
      (select(runEvents)
            ..where((row) => row.runId.equals(runId))
            ..orderBy([(row) => OrderingTerm.asc(row.sequenceNo)])
            ..limit(limit, offset: offset))
          .get();

  Stream<List<RunEvent>> watchEventsForRun(String runId,
          {int limit = 50, int offset = 0}) =>
      (select(runEvents)
            ..where((row) => row.runId.equals(runId))
            ..orderBy([(row) => OrderingTerm.asc(row.sequenceNo)])
            ..limit(limit, offset: offset))
          .watch();

  Future<void> insertLogRecord(LogRecordsCompanion record) =>
      into(logRecords).insertOnConflictUpdate(record);

  Future<List<LogRecord>> recentLogRecords({
    int limit = 200,
    int offset = 0,
    String? runId,
    String? level,
    String? category,
    String? keyword,
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(logRecords)
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(limit, offset: offset);
    if (runId != null) query.where((row) => row.runId.equals(runId));
    if (level != null) query.where((row) => row.level.equals(level));
    if (category != null) query.where((row) => row.category.equals(category));
    if (keyword != null && keyword.trim().isNotEmpty) {
      final term = '%${keyword.trim()}%';
      query.where((row) => row.message.like(term) | row.category.like(term));
    }
    if (from != null) {
      query.where((row) => row.createdAt.isBiggerOrEqualValue(from));
    }
    if (to != null) query.where((row) => row.createdAt.isSmallerThanValue(to));
    return query.get();
  }

  Stream<List<LogRecord>> watchLogRecords({
    int limit = 200,
    String? runId,
    String? level,
    String? category,
    String? keyword,
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(logRecords)
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(limit);
    if (runId != null) query.where((row) => row.runId.equals(runId));
    if (level != null) query.where((row) => row.level.equals(level));
    if (category != null) query.where((row) => row.category.equals(category));
    if (keyword != null && keyword.trim().isNotEmpty) {
      final term = '%${keyword.trim()}%';
      query.where((row) => row.message.like(term) | row.category.like(term));
    }
    if (from != null) {
      query.where((row) => row.createdAt.isBiggerOrEqualValue(from));
    }
    if (to != null) query.where((row) => row.createdAt.isSmallerThanValue(to));
    return query.watch();
  }

  Future<void> clearLogRecords() => delete(logRecords).go();

  Future<void> pruneLogRecords(DateTime before) => (delete(logRecords)
        ..where((row) => row.createdAt.isSmallerThanValue(before)))
      .go();

  Future<void> pruneRunLogs(String runId, {int max = 2000}) async {
    await customStatement(
      'DELETE FROM log_records WHERE run_id = ? AND log_id NOT IN '
      '(SELECT log_id FROM log_records WHERE run_id = ? '
      'ORDER BY created_at DESC LIMIT ?)',
      [runId, runId, max],
    );
  }

  // --- 插件（C6）---

  Future<List<Plugin>> allPlugins() =>
      (select(plugins)..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();

  Future<Plugin?> findPlugin(String id) =>
      (select(plugins)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> savePlugin(Plugin plugin) =>
      into(plugins).insertOnConflictUpdate(plugin);

  Future<void> insertPlugin(PluginsCompanion plugin) =>
      into(plugins).insertOnConflictUpdate(plugin);

  Future<void> deletePlugin(String id) =>
      (delete(plugins)..where((row) => row.id.equals(id))).go();

  // --- Skill 市场（GitHub Skill 包）---

  Future<List<SkillPack>> allSkillPacks() =>
      (select(skillPacks)..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<SkillPack?> findSkillPack(String id) =>
      (select(skillPacks)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<SkillPack?> findSkillPackByName(String name) =>
      (select(skillPacks)..where((row) => row.name.equals(name)))
          .getSingleOrNull();

  Future<List<SkillPack>> enabledSkillPacks() => (select(skillPacks)
        ..where((row) => row.enabled.equals(true))
        ..orderBy([(row) => OrderingTerm.asc(row.name)]))
      .get();

  Future<void> saveSkillPack(SkillPack pack) =>
      into(skillPacks).insertOnConflictUpdate(pack);

  Future<void> insertSkillPack(SkillPacksCompanion pack) =>
      into(skillPacks).insertOnConflictUpdate(pack);

  Future<void> deleteSkillPack(String id) =>
      (delete(skillPacks)..where((row) => row.id.equals(id))).go();

  // --- MCP 服务器 ---

  Future<List<McpServer>> allMcpServers() =>
      (select(mcpServers)..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<List<McpServer>> enabledMcpServers() => (select(mcpServers)
        ..where((row) => row.enabled.equals(true))
        ..orderBy([(row) => OrderingTerm.asc(row.name)]))
      .get();

  Future<void> saveMcpServer(McpServer server) =>
      into(mcpServers).insertOnConflictUpdate(server);

  Future<void> insertMcpServer(McpServersCompanion server) =>
      into(mcpServers).insertOnConflictUpdate(server);

  Future<void> deleteMcpServer(String id) =>
      (delete(mcpServers)..where((row) => row.id.equals(id))).go();

  Future<void> clearMcpServers() => delete(mcpServers).go();

  /// 清空全部业务数据（G3 隐私保险箱导入前备份后覆盖用）。
  /// 范围必须与 [buildVaultJson] 的导出清单保持一致：导出包含而此处未清的表
  /// 会在恢复时留下旧行，此处清掉而导出没有的表会在恢复时彻底丢失。
  /// 保留 syncMeta（运行态元数据），tasks 属于业务数据，同样会被清空。
  Future<void> clearAllUserData() async {
    await transaction(() async {
      await delete(collaborationMessages).go();
      await delete(collaborationArtifacts).go();
      await delete(collaborationAgentRuns).go();
      await delete(collaborationRuns).go();
      await delete(tasks).go();
      await delete(taskFeedback).go();
      await delete(drafts).go();
      await delete(runControls).go();
      await delete(executionLeases).go();
      await delete(projects).go();
      await delete(messages).go();
      await delete(conversations).go();
      await delete(memories).go();
      await delete(agents).go();
      await delete(promptTemplates).go();
      await delete(modelProfiles).go();
      await delete(knowledgeChunks).go();
      await delete(knowledgeDocs).go();
      await delete(scheduledTasks).go();
      await delete(auditLogs).go();
      await delete(plugins).go();
      await delete(skillPacks).go();
      await delete(runEvents).go();
      await delete(runRecords).go();
      await delete(logRecords).go();
      await customStatement('DELETE FROM artifacts');
      // 一次性审批握手数据：不进备份，但清库时必须一并抹掉，否则残留记录会
      // 让清库后的下一个同名请求拿到一个早已过期的决定。
      await customStatement('DELETE FROM pending_approvals');
    });
  }
}

Future<AppDatabase> openAppDatabase() async {
  final database = AppDatabase(await createDatabaseExecutor());
  await database.ensureDefaultPromptTemplates();
  return database;
}
