import 'package:drift/drift.dart';
import 'database_executor.dart';

part 'app_database.g.dart';

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('新会话'))();
  TextColumn get agentId => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 会话消息按会话查询 / 删除是高频路径，为 conversationId 建索引避免全表扫描。
@TableIndex(name: 'idx_messages_conversation', columns: {#conversationId})
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
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
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

/// v0.9 鍗忎綔鍒嗘瀽杩愯鐘舵€併€佽鍒掍笌鎬荤粨銆?
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

/// 云同步元数据（D1）：记录各业务行的版本号与脏标记，用于增量密文同步。
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
class ScheduledTasks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get prompt => text()();
  TextColumn get cron => text()();
  TextColumn get agentId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get lastResult => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 审计日志（G2）：记录工具调用审批的决策链路。
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
class RunRecords extends Table {
  TextColumn get runId => text()();
  TextColumn get conversationId => text()();
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
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
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
        },
      );

  Future<List<Conversation>> recentConversations() => (select(conversations)
        ..orderBy([
          (row) => OrderingTerm.desc(row.isPinned),
          (row) => OrderingTerm.desc(row.updatedAt),
        ]))
      .get();

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
      final runs = await (select(runRecords)
            ..where((row) => row.conversationId.equals(id)))
          .get();
      final runIds = runs.map((run) => run.runId).toList(growable: false);
      if (runIds.isNotEmpty) {
        await (delete(logRecords)..where((row) => row.runId.isIn(runIds))).go();
        await (delete(runEvents)..where((row) => row.runId.isIn(runIds))).go();
        await (delete(runRecords)..where((row) => row.runId.isIn(runIds))).go();
      }
      await (delete(messages)..where((row) => row.conversationId.equals(id)))
          .go();
      await (delete(conversations)..where((row) => row.id.equals(id))).go();
    });
  }

  Future<List<Message>> messagesFor(String conversationId) => (select(messages)
        ..where((row) => row.conversationId.equals(conversationId))
        ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
      .get();

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

  // --- 后台任务（C2）---

  Future<List<Task>> runningTasks() => (select(tasks)
        ..where((row) => row.status.equals('running'))
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

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((row) => row.id.equals(id))).go();

  // --- 云同步元数据（D1）---

  Future<List<SyncMetaData>> dirtySyncRows() =>
      (select(syncMeta)..where((row) => row.dirty.equals(true))).get();

  Future<void> saveSyncMeta(SyncMetaData meta) =>
      into(syncMeta).insertOnConflictUpdate(meta);

  Future<SyncMetaData?> findSyncMeta(String objectId) =>
      (select(syncMeta)..where((row) => row.objectId.equals(objectId)))
          .getSingleOrNull();

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
  /// 保留 tasks / syncMeta（运行态元数据）。
  Future<void> clearAllUserData() async {
    await transaction(() async {
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
    });
  }
}

Future<AppDatabase> openAppDatabase() async {
  final database = AppDatabase(await createDatabaseExecutor());
  await database.ensureDefaultPromptTemplates();
  return database;
}
