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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
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
        },
      );

  Future<List<Conversation>> recentConversations() => (select(conversations)
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
        await (delete(messages)
                ..where((row) => row.id.isIn(trailingIds)))
            .go();
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

  Future<Task?> findTask(String id) =>
      (select(tasks)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> saveTask(Task task) => into(tasks).insertOnConflictUpdate(task);

  Future<void> insertTask(TasksCompanion task) =>
      into(tasks).insertOnConflictUpdate(task);

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
    });
  }
}

Future<AppDatabase> openAppDatabase() async {
  return AppDatabase(await createDatabaseExecutor());
}
