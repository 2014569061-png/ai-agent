import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../database/memory_forget_store.dart';
import '../database/personal_context_store.dart';
import '../database/result_action_store.dart';
import '../mcp/mcp_legacy_migration.dart';
import '../../domain/models.dart';
import '../../domain/sensitive_tool_policy.dart';
import '../observability/sentry_service.dart';
import '../providers/provider_config.dart';
import '../providers/provider_config_store.dart';
import 'context_result_vault.dart';
import 'mobile_module_vault.dart';
import 'local_crypto_service.dart';
import 'run_plan_vault.dart';
import 'vault_manifest.dart';
import 'vault_snapshot_reader.dart';
import 'vault_skill_staging.dart';
export 'vault_manifest.dart'
    show VaultRestoreReport, VaultLimits, encodeVaultJson;

/// G3 隐私保险箱：把全量本地数据打包为单个 AES-256-GCM 加密文件（.nexusvault）。
/// 导入先校验并暂存文件，数据库事务失败时回滚文件；密码丢失无法恢复。
/// v2 起额外包含 Provider 配置（含 API Key）、工具密钥与 MCP 服务器配置；
/// 旧版备份文件缺少这些段时按原样跳过。

Future<String?> exportVaultFile(AppDatabase db, String password,
    {bool includeSecrets = false}) async {
  try {
    final json = await buildVaultJson(db, includeSecrets: includeSecrets);
    final plaintext = await encodeVaultJson(json);
    final cipher =
        await LocalCryptoService().encryptWithPassword(plaintext, password);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(
        dir.path, 'nexus-${DateTime.now().millisecondsSinceEpoch}.nexusvault'));
    await file.writeAsString(cipher, flush: true);
    return file.path;
  } catch (error, stackTrace) {
    // 影响用户：导出失败会让用户拿不到备份文件。返回 null 由调用方提示，
    // 但必须留下记录，否则「备份没生成」这件事在数据上不可见。
    // 只记录 error type：password 与路径都不能进日志。
    unawaited(SentryService.reportException(error, stackTrace));
    return null;
  }
}

/// 从加密文件字节解密并全量恢复。返回解密后的数据条数摘要。
Future<String> importVaultBytes(
    AppDatabase db, Uint8List bytes, String password,
    {ProviderConfigStore? providerStore}) async {
  if (bytes.length > VaultLimits.maxCipherBytes) {
    throw const FormatException('备份文件过大');
  }
  final cipher = utf8.decode(bytes);
  final plaintext =
      await LocalCryptoService().decryptWithPassword(cipher, password);
  if (utf8.encode(plaintext).length > VaultLimits.maxJsonBytes) {
    throw const FormatException('备份内容过大');
  }
  final json = jsonDecode(plaintext) as Map<String, dynamic>;
  final report = await restoreVault(db, json, providerStore: providerStore);
  return report.summary;
}

Future<Map<String, dynamic>> buildVaultJson(AppDatabase db,
    {ProviderConfigStore? providerStore, bool includeSecrets = false}) async {
  await ensurePersonalContextTables(db);
  await ensureResultActionTables(db);
  return db.transaction(() async {
    final reader = VaultSnapshotReader(db);
    final store = providerStore ?? ProviderConfigStore();
    final profiles =
        includeSecrets ? await store.loadAll() : const <ProviderConfig>[];
    final data = <String, dynamic>{
      'version': 2,
      'conversations':
          await reader.rows(db.conversations, (row) => row.toJson()),
      'messages': await reader.rows(db.messages, (row) => row.toJson()),
      'memories': await reader.rows(db.memories, (row) => row.toJson()),
      'memoryForgetRules': await reader.memoryForgetRules(),
      'agents': await reader.rows(db.agents, (row) => row.toJson()),
      'prompts': await reader.rows(db.promptTemplates, (row) => row.toJson()),
      'modelProfiles':
          await reader.rows(db.modelProfiles, (row) => row.toJson()),
      'knowledgeScopes': await reader.knowledgeScopes(),
      'knowledgeDocs':
          await reader.rows(db.knowledgeDocs, (row) => row.toJson()),
      'knowledgeChunks':
          await reader.rows(db.knowledgeChunks, (row) => row.toJson()),
      'scheduledTasks':
          await reader.rows(db.scheduledTasks, (row) => row.toJson()),
      'plugins': await reader.rows(db.plugins, (row) => row.toJson()),
      'skillPacks': await reader.rows(db.skillPacks, (row) => row.toJson()),
      'projects': await reader.rows(db.projects, (row) => row.toJson()),
      'drafts': await reader.rows(db.drafts, (row) => row.toJson()),
      'runControls': await reader.rows(db.runControls, (row) => row.toJson()),
      ...await reader.runPlans(),
      ...await reader.contextAndResultActions(),
      ...await reader.mobileModules(),
      'executionLeases':
          await reader.rows(db.executionLeases, (row) => row.toJson()),
      'tasks': await reader.rows(db.tasks, (row) => row.toJson()),
      'taskFeedback': await reader.rows(db.taskFeedback, (row) => row.toJson()),
      'collaborationRuns':
          await reader.rows(db.collaborationRuns, (row) => row.toJson()),
      'collaborationAgentRuns':
          await reader.rows(db.collaborationAgentRuns, (row) => row.toJson()),
      'collaborationArtifacts':
          await reader.rows(db.collaborationArtifacts, (row) => row.toJson()),
      'collaborationMessages':
          await reader.rows(db.collaborationMessages, (row) => row.toJson()),
      'auditLogs': await reader.rows(db.auditLogs, (row) => row.toJson()),
      'runRecords': await reader.rows(db.runRecords, (row) => row.toJson()),
      'runEvents': await reader.rows(db.runEvents, (row) => row.toJson()),
      'logRecords': await reader.rows(db.logRecords, (row) => row.toJson()),
      'mcpServers': await reader.rows(db.mcpServers, (row) => row.toJson()),
      'artifacts': await reader.artifacts(),
      'skillFiles': await _collectSkillFiles(db),
      if (includeSecrets && profiles.isNotEmpty)
        'activeProviderId': (await store.load()).id,
      if (includeSecrets)
        'providerProfiles': profiles
            .map((p) => {
                  'id': p.id,
                  'name': p.name,
                  'baseUrl': p.baseUrl,
                  'model': p.model,
                  'type': p.type.name,
                  'apiKey': p.apiKey,
                  'reasoningEffort': p.reasoningEffort.name,
                  'contextTokens': p.contextTokens,
                  if (p.inputPricePerMillionCents != null)
                    'inputPricePerMillionCents': p.inputPricePerMillionCents,
                  if (p.outputPricePerMillionCents != null)
                    'outputPricePerMillionCents': p.outputPricePerMillionCents,
                  if (p.cachedPricePerMillionCents != null)
                    'cachedPricePerMillionCents': p.cachedPricePerMillionCents,
                })
            .toList(),
      if (includeSecrets)
        'toolKeys': {
          'tavily': await store.readToolKey('tavily'),
        },
    };
    final names = <String, Map<String, String>>{};
    for (final row in (data['messages'] as List).cast<Map<String, dynamic>>()) {
      final calls = row['toolCallsJson'];
      if (row['role'] != 'assistant' || calls == null) continue;
      try {
        for (final call
            in (jsonDecode(calls as String) as List).whereType<Map>()) {
          names.putIfAbsent(row['conversationId'] as String,
              () => {})[call['id'].toString()] = call['name'].toString();
        }
      } catch (_) {
        // Malformed tool metadata must not leak raw arguments into a backup.
        row['toolCallsJson'] = '[]';
      }
    }
    data['messages'] = [
      for (final row in (data['messages'] as List).cast<Map<String, dynamic>>())
        _redactPersistedMessage(row, names[row['conversationId']] ?? const {})
    ];
    data['auditLogs'] = (data['auditLogs'] as List)
        .cast<Map<String, dynamic>>()
        .map(_redactAuditLog)
        .toList();
    data['runEvents'] = (data['runEvents'] as List)
        .cast<Map<String, dynamic>>()
        .map(_redactRunEvent)
        .toList();
    data['logRecords'] = (data['logRecords'] as List)
        .cast<Map<String, dynamic>>()
        .map(_redactLogRecord)
        .toList();
    final sealed = await sealVault(data);
    await encodeVaultJson(
        sealed); // Enforce encoded-size budget before returning a snapshot.
    return sealed;
  });
}

Map<String, dynamic> _redactPersistedMessage(
    Map<String, dynamic> raw, Map<String, String> toolNamesById) {
  final result = Map<String, dynamic>.from(raw);
  final role = result['role']?.toString() ?? '';
  final toolName = toolNamesById[result['toolCallId']?.toString()];
  if (role == 'tool' &&
      toolName != null &&
      SensitiveToolPolicy.isSensitive(toolName)) {
    result['content'] = '[敏感工具结果已脱敏]';
  }
  final callsJson = result['toolCallsJson']?.toString();
  if (role == 'assistant' && callsJson != null && callsJson.isNotEmpty) {
    try {
      final calls = jsonDecode(callsJson);
      if (calls is List) {
        result['toolCallsJson'] =
            jsonEncode(calls.whereType<Map>().map((rawCall) {
          final call = Map<String, dynamic>.from(rawCall);
          final name = call['name']?.toString() ?? '';
          if (SensitiveToolPolicy.isArgumentSensitive(name)) {
            call['arguments'] = SensitiveToolPolicy.redactArguments(
                name,
                call['arguments'] is Map
                    ? Map<String, dynamic>.from(call['arguments'] as Map)
                    : const {});
          }
          return call;
        }).toList(growable: false));
      }
    } catch (error, stackTrace) {
      // 可忽略（有意降级）：旧版本的损坏 toolCallsJson 不阻断整个保险箱导出。
      unawaited(SentryService.reportException(error, stackTrace));
    }
  }
  return result;
}

Map<String, dynamic> _redactAuditLog(Map<String, dynamic> raw) {
  final result = Map<String, dynamic>.from(raw);
  final type = result['type']?.toString() ?? '';
  final risk = result['risk']?.toString() ?? '';
  if (type == 'tool' ||
      risk == 'requiresConfirmation' ||
      risk == 'dangerous' ||
      SensitiveToolPolicy.isSensitive(type)) {
    result['detail'] = '[敏感审计详情已脱敏]';
  }
  return result;
}

Map<String, dynamic> _redactRunEvent(Map<String, dynamic> raw) {
  final result = Map<String, dynamic>.from(raw);
  final name = result['name']?.toString() ?? '';
  if (SensitiveToolPolicy.isSensitive(name) ||
      SensitiveToolPolicy.isArgumentSensitive(name) ||
      SensitiveToolPolicy.isResultSensitive(name)) {
    if (result['inputSummary'] != null) {
      result['inputSummary'] = '[敏感工具参数已脱敏]';
    }
    if (result['outputSummary'] != null) {
      result['outputSummary'] = '[敏感工具结果已脱敏]';
    }
    result['metadataJson'] = '{}';
  }
  return result;
}

Map<String, dynamic> _redactLogRecord(Map<String, dynamic> raw) {
  final result = Map<String, dynamic>.from(raw);
  final category = result['category']?.toString() ?? '';
  final detail = result['detailJson']?.toString() ?? '';
  if (category == 'tool' ||
      detail.contains('"arguments"') ||
      detail.contains('"result"')) {
    result['detailJson'] = '{"redacted":true}';
  }
  return result;
}

// SQLite cannot serialize directory publication. Keep restores ordered within
// this isolate so one rollback never removes another restore's new files.
Future<void> _restoreTail = Future<void>.value();

Future<VaultRestoreReport> restoreVault(
    AppDatabase db, Map<String, dynamic> json,
    {ProviderConfigStore? providerStore}) {
  final previous = _restoreTail;
  final complete = Completer<void>();
  _restoreTail = complete.future;
  return () async {
    await previous;
    try {
      return await _restoreVault(db, json, providerStore: providerStore);
    } finally {
      complete.complete();
    }
  }();
}

Future<VaultRestoreReport> _restoreVault(
    AppDatabase db, Map<String, dynamic> json,
    {ProviderConfigStore? providerStore}) async {
  await validateVault(json);
  final profiles = _providerConfigsFromJson(json['providerProfiles']);
  final activeId = json['activeProviderId'];
  if (activeId != null && !profiles.any((p) => p.id == activeId)) {
    throw const FormatException('备份中的激活配置不存在');
  }
  // Work on a private copy: staged installRoot rewrites must not change the caller's manifest.
  json = jsonDecode(await encodeVaultJson(json)) as Map<String, dynamic>;
  final store = providerStore ?? ProviderConfigStore();
  final oldProfiles =
      json['providerProfiles'] is List ? await store.loadAll() : null;
  final oldActiveId = oldProfiles != null && oldProfiles.isNotEmpty
      ? (await store.load()).id
      : null;
  final oldKeys = <String, String>{};
  if (json['toolKeys'] is Map) {
    for (final key in (json['toolKeys'] as Map).keys.cast<String>()) {
      oldKeys[key] = await store.readToolKey(key);
    }
  }
  await ensurePersonalContextTables(db);
  await ensureResultActionTables(db);
  final hasPersonalContext = backupHasPersonalContextSection(json);
  final hasResultActions = backupHasResultActionSection(json);
  final preservePersonalContext = !hasPersonalContext;
  var contextResultSummary = const ContextResultRestoreSummary(
    restoredEntities: 0,
    skippedForgottenEntities: 0,
    restoredTombstones: 0,
    restoredResultCards: 0,
    restoredResultActions: 0,
  );
  final stage = await VaultSkillStaging.prepare(json);
  var secretsStarted = false;
  var preserveStage = false;
  var committed = false;
  var forgottenMemoriesSkipped = 0;
  try {
    await stage.publish();
    await db.transaction(() async {
      // Restore must not erase newer privacy choices, including with legacy vaults.
      final localForgetRules =
          await VaultSnapshotReader(db).memoryForgetRules();
      final preservedLocalTombstones = hasPersonalContext
          ? [
              for (final r in await db
                  .customSelect(
                    'SELECT normalized_key, project_id, reason, forgotten_at, entity_id '
                    'FROM $personalContextTombstonesTable',
                  )
                  .get())
                Map<String, Object?>.from(r.data),
            ]
          : const <Map<String, Object?>>[];
      // Legacy vaults without F17 preserve local personal context and tombstones;
      // full vaults restore F17 while merging local tombstones.
      await db.clearAllUserData(
          preservePersonalContext: preservePersonalContext,
          preserveMobileData: true);
      if (hasResultActions) {
        await db.customStatement('DELETE FROM result_actions');
        await db.customStatement('DELETE FROM result_cards');
      }
      final forget = MemoryForgetStore(db);
      for (final raw in [
        ...localForgetRules,
        ...(json['memoryForgetRules'] as List? ?? const [])
      ]) {
        await forget.put(Map<String, dynamic>.from(raw as Map));
      }
      await _restoreOptionalRows(
          json['projects'], db.saveProject, Project.fromJson);
      await _restoreOptionalRows(json['drafts'], db.saveDraft, Draft.fromJson);
      if (json['artifacts'] is List) {
        for (final raw in (json['artifacts'] as List).whereType<Map>()) {
          await db.saveArtifactRecord(Map<String, dynamic>.from(raw));
        }
      }
      for (final m in (json['conversations'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        final row = Map<String, dynamic>.from(m);
        row['mode'] ??= 'chat';
        await db.saveConversation(Conversation.fromJson(row));
      }
      for (final m in (json['messages'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveMessage(Message.fromJson(m));
      }
      for (final m in (json['memories'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        final memory = Memory.fromJson(m);
        if (await forget.blocks(memory.content,
            sourceConversationId: memory.sourceType == 'manual'
                ? null
                : memory.sourceConversationId)) {
          forgottenMemoriesSkipped++;
        } else {
          await db.saveMemory(memory);
        }
      }
      for (final m in (json['agents'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveAgent(Agent.fromJson(m));
      }
      for (final m in (json['prompts'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.savePromptTemplate(PromptTemplate.fromJson(m));
      }
      for (final m in (json['modelProfiles'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveModelProfile(ModelProfile.fromJson(m));
      }
      for (final m in (json['knowledgeDocs'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveKnowledgeDoc(KnowledgeDoc.fromJson(m));
      }
      for (final row in (json['knowledgeScopes'] as List? ?? const [])) {
        await db.bindKnowledgeDocument(
            row['docId'] as String, row['projectId'] as String);
      }
      for (final m in (json['knowledgeChunks'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveKnowledgeChunk(KnowledgeChunk.fromJson(m));
      }
      for (final m in (json['scheduledTasks'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveScheduledTask(ScheduledTask.fromJson(m));
      }
      for (final m in (json['plugins'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.savePlugin(Plugin.fromJson(m));
      }
      for (final s in (json['skillPacks'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await db.saveSkillPack(SkillPack.fromJson(s));
      }
      await _restoreOptionalRows(json['tasks'], db.saveTask, (row) {
        final mapped = Map<String, dynamic>.from(row);
        mapped['stateRevision'] ??= 0;
        return Task.fromJson(mapped);
      });
      await _restoreOptionalRows(
          json['runControls'], db.saveRunControl, RunControl.fromJson);
      await _restoreOptionalRows(json['executionLeases'], db.saveExecutionLease,
          ExecutionLease.fromJson);
      await _restoreOptionalRows(json['taskFeedback'], db.saveTaskFeedbackRow,
          TaskFeedbackData.fromJson);
      await _restoreOptionalRows(json['collaborationRuns'],
          db.saveCollaborationRun, CollaborationRun.fromJson);
      await _restoreOptionalRows(json['collaborationAgentRuns'],
          db.saveCollaborationAgentRun, CollaborationAgentRun.fromJson);
      await _restoreOptionalRows(json['collaborationArtifacts'],
          db.saveCollaborationArtifact, CollaborationArtifact.fromJson);
      await _restoreOptionalRows(json['collaborationMessages'],
          db.saveCollaborationMessage, CollaborationMessage.fromJson);
      await _restoreOptionalRows(
          json['auditLogs'], db.saveAuditLog, AuditLog.fromJson);
      await _restoreOptionalRows(
          json['runRecords'], db.saveRunRecordRow, RunRecord.fromJson);
      await _restoreOptionalRows(
          json['runEvents'], db.saveRunEventRow, RunEvent.fromJson);
      await _restoreOptionalRows(
          json['logRecords'], db.saveLogRecordRow, LogRecord.fromJson);
      // MCP 配置的正式来源是数据库；仅当备份含该段（v2+）时覆盖。
      if (json['mcpServers'] is List) {
        await McpLegacyMigration.markComplete(db);
        await db.clearMcpServers();
        for (final m
            in (json['mcpServers'] as List).cast<Map<String, dynamic>>()) {
          await db.saveMcpServer(McpServer.fromJson(m));
        }
      }
      await restoreRunPlanVault(db, json);
      await restoreMobileModuleVault(db, json);
      contextResultSummary = await restoreContextResultVault(
        db,
        json,
        preservedLocalTombstones: preservedLocalTombstones,
      );
      secretsStarted = true;
      await _restoreProviderSecrets(db, json, store);
    });
    committed = true;
    final warnings = <String>[
      if (!mobileModuleVaultTables.keys.every(json.containsKey))
        '旧备份不含完整的提醒、工作流或研究成果；对应本机数据已保留',
      if ((json['reminders'] as List? ?? const [])
          .any((r) => const {'scheduled', 'snoozed'}.contains(r['status'])))
        '恢复的提醒已暂停，请确认时间后重新启用；不会自动重放通知',
      if (preservePersonalContext) '本备份不含个人上下文；本机原有条目与遗忘保护已保留，并非从备份恢复',
      if (forgottenMemoriesSkipped > 0)
        '已按遗忘规则跳过 $forgottenMemoriesSkipped 条旧记忆；历史消息及外部副本未清除',
      if (contextResultSummary.skippedForgottenEntities > 0)
        '已按个人上下文遗忘墓碑跳过 ${contextResultSummary.skippedForgottenEntities} 条实体'
    ];
    try {
      await stage.dispose();
    } catch (error, stack) {
      // The database already committed: cleanup failure is not restore failure.
      warnings.add('数据已恢复，但临时文件清理失败');
      unawaited(SentryService.reportException(error, stack));
    }
    return VaultRestoreReport({
      for (final entry in json.entries)
        if (entry.value is List) entry.key: (entry.value as List).length,
      'memories': (json['memories'] as List? ?? const []).length -
          forgottenMemoriesSkipped,
      if (hasPersonalContext) ...{
        'personalContextEntities': contextResultSummary.restoredEntities,
        'personalContextTombstones': contextResultSummary.restoredTombstones,
      },
      if (hasResultActions) ...{
        'resultCards': contextResultSummary.restoredResultCards,
        'resultActions': contextResultSummary.restoredResultActions,
      },
    }, stage.fileCount, warnings: warnings);
  } catch (error, stack) {
    Object? fileRollbackError;
    try {
      await stage.rollback();
    } catch (rollbackError, rollbackStack) {
      // Preserve backups if compensation fails; still attempt secret rollback.
      preserveStage = true;
      fileRollbackError = rollbackError;
      unawaited(SentryService.reportException(rollbackError, rollbackStack));
    }
    if (secretsStarted) {
      try {
        if (oldProfiles != null) {
          await store.restoreProfiles(oldProfiles, activeId: oldActiveId);
        }
        for (final key in oldKeys.entries) {
          await store.saveToolKey(key.key, key.value);
        }
      } catch (rollbackError, rollbackStack) {
        // Secure storage is outside SQLite. Surface compensation failure, never claim success.
        unawaited(SentryService.reportException(rollbackError, rollbackStack));
        throw StateError('恢复失败且密钥回滚失败，请保留原备份并重新恢复');
      }
    }
    if (fileRollbackError != null) {
      throw StateError('恢复失败且文件回滚失败；恢复材料保留于 ${stage.temp?.path}');
    }
    Error.throwWithStackTrace(error, stack);
  } finally {
    if (!committed && !preserveStage) await stage.dispose();
  }
}

List<ProviderConfig> _providerConfigsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final configs = raw
      .cast<Map<String, dynamic>>()
      .map((item) => ProviderConfig(
            id: item['id'] as String? ?? 'default',
            name: item['name'] as String? ?? 'Provider',
            baseUrl: item['baseUrl'] as String? ?? '',
            model: item['model'] as String? ?? '',
            apiKey: item['apiKey'] as String? ?? '',
            type: ProviderType.values.firstWhere((t) => t.name == item['type'],
                orElse: () => ProviderType.openaiCompatible),
            reasoningEffort: ReasoningEffort.values.firstWhere(
                (e) => e.name == item['reasoningEffort'],
                orElse: () => ReasoningEffort.auto),
            contextTokens: (item['contextTokens'] as num?)?.toInt() ??
                ProviderConfig.defaultContextTokens,
            inputPricePerMillionCents:
                (item['inputPricePerMillionCents'] as num?)?.toInt(),
            outputPricePerMillionCents:
                (item['outputPricePerMillionCents'] as num?)?.toInt(),
            cachedPricePerMillionCents:
                (item['cachedPricePerMillionCents'] as num?)?.toInt(),
          ))
      .toList();
  if (configs.any((p) => p.id.isEmpty) ||
      configs.map((p) => p.id).toSet().length != configs.length) {
    throw const FormatException('备份中的配置 ID 为空或重复');
  }
  return configs;
}

/// 恢复 Provider 配置（含 API Key）与工具密钥到安全存储；旧版备份无该段时跳过。
Future<void> _restoreOptionalRows<T>(
  Object? raw,
  Future<void> Function(T row) save,
  T Function(Map<String, dynamic> json) fromJson,
) async {
  if (raw is! List) return;
  for (final item in raw.cast<Map>()) {
    // A partial restore must fail the enclosing transaction, not report input counts as success.
    await save(fromJson(Map<String, dynamic>.from(item)));
  }
}

Future<void> _restoreProviderSecrets(AppDatabase db, Map<String, dynamic> json,
    ProviderConfigStore store) async {
  final profilesJson = json['providerProfiles'];
  if (profilesJson is List) {
    final configs = _providerConfigsFromJson(profilesJson);
    await store.restoreProfiles(configs,
        activeId:
            json['activeProviderId'] as String? ?? configs.firstOrNull?.id);
  }
  final toolKeys = json['toolKeys'];
  if (toolKeys is Map) {
    for (final entry in toolKeys.entries) {
      final value = entry.value;
      if (value is String) {
        await store.saveToolKey(entry.key, value);
      }
    }
  }
}

/// 收集 skill 文件内容（base64），用于随 vault 备份导出。
Future<Map<String, Map<String, String>>> _collectSkillFiles(
    AppDatabase db) async {
  final packs = await db.allSkillPacks();
  final out = <String, Map<String, String>>{};
  var totalBytes = 0;
  var count = 0;
  for (final pack in packs) {
    validateVaultName(pack.name);
    final files = <String, String>{};
    final root = Directory(pack.installRoot);
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('不能备份符号链接技能目录');
    }
    if (!await root.exists()) {
      throw const FormatException('技能目录缺失，备份未生成');
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) throw const FormatException('不能备份符号链接技能文件');
      if (entity is! File) continue;
      final rel =
          validateVaultRelativePath(p.relative(entity.path, from: root.path));
      final before = await entity.stat();
      totalBytes += before.size;
      if (++count > VaultLimits.maxFiles ||
          before.size > VaultLimits.maxFileBytes ||
          totalBytes > VaultLimits.maxSkillBytes) {
        throw const FormatException('技能超过备份容量上限');
      }
      final content = await entity.readAsBytes();
      final after = await entity.stat();
      if (content.length != before.size || after.modified != before.modified) {
        throw const FormatException('备份期间技能文件发生变化，请重试');
      }
      files[rel] = base64Encode(content);
    }
    out[pack.id] = files;
  }
  return out;
}
