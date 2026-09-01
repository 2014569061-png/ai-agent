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
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Agents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get systemPrompt => text().withDefault(const Constant('你是一个有帮助的 AI Agent。'))();
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

@DriftDatabase(tables: [Conversations, Messages, Agents, PromptTemplates, ModelProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

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
        },
      );

  Future<List<Conversation>> recentConversations() =>
      (select(conversations)
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

  Future<void> saveConversation(Conversation conversation) => into(conversations).insertOnConflictUpdate(conversation);

  Future<void> insertConversation(ConversationsCompanion conversation) =>
      into(conversations).insertOnConflictUpdate(conversation);

  Future<void> saveMessage(Message message) => into(messages).insertOnConflictUpdate(message);

  Future<void> insertMessage(MessagesCompanion message) =>
      into(messages).insertOnConflictUpdate(message);

  Future<Conversation?> findConversation(String id) =>
      (select(conversations)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> deleteConversation(String id) async {
    await transaction(() async {
      await (delete(messages)..where((row) => row.conversationId.equals(id))).go();
      await (delete(conversations)..where((row) => row.id.equals(id))).go();
    });
  }

  Future<List<Message>> messagesFor(String conversationId) =>
      (select(messages)
            ..where((row) => row.conversationId.equals(conversationId))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  /// 删除最后一次用户消息之后的所有助手/工具消息（用于"重新生成"时清理上一轮结果）。
  Future<void> deleteTrailingAssistantAndTool(String conversationId) async {
    final lastUser = await (select(messages)
          ..where((row) => row.conversationId.equals(conversationId) & row.role.equals('user'))
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

  Future<List<Agent>> allAgents() => select(agents).get();

  Future<Agent?> findAgent(String id) =>
      (select(agents)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> saveAgent(Agent agent) => into(agents).insertOnConflictUpdate(agent);

  Future<void> insertAgent(AgentsCompanion agent) => into(agents).insertOnConflictUpdate(agent);

  Future<List<ModelProfile>> allModelProfiles() => select(modelProfiles).get();

  Future<void> saveModelProfile(ModelProfile profile) => into(modelProfiles).insertOnConflictUpdate(profile);

  // --- Prompt templates ---

  Future<List<PromptTemplate>> allPromptTemplates() =>
      (select(promptTemplates)..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).get();

  Future<PromptTemplate?> findPromptTemplate(String id) =>
      (select(promptTemplates)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> savePromptTemplate(PromptTemplate template) =>
      into(promptTemplates).insertOnConflictUpdate(template);

  Future<void> insertPromptTemplate(PromptTemplatesCompanion template) =>
      into(promptTemplates).insertOnConflictUpdate(template);

  Future<void> deletePromptTemplate(String id) =>
      (delete(promptTemplates)..where((row) => row.id.equals(id))).go();
}

Future<AppDatabase> openAppDatabase() async {
  return AppDatabase(await createDatabaseExecutor());
}
