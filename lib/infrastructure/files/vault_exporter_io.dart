import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../../domain/models.dart';
import '../../domain/sensitive_tool_policy.dart';
import '../observability/sentry_service.dart';
import '../providers/provider_config.dart';
import '../providers/provider_config_store.dart';
import 'local_crypto_service.dart';

/// G3 隐私保险箱：把全量本地数据打包为单个 AES-256-GCM 加密文件（.nexusvault）。
/// 导入时先备份现有库再覆盖写入，密码丢失无法恢复。
/// v2 起额外包含 Provider 配置（含 API Key）、工具密钥与 MCP 服务器配置；
/// 旧版备份文件缺少这些段时按原样跳过。

Future<String?> exportVaultFile(AppDatabase db, String password,
    {bool includeSecrets = false}) async {
  try {
    final json = await buildVaultJson(db, includeSecrets: includeSecrets);
    final plaintext = jsonEncode(json);
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
  final cipher = utf8.decode(bytes);
  final plaintext =
      await LocalCryptoService().decryptWithPassword(cipher, password);
  final json = jsonDecode(plaintext) as Map<String, dynamic>;
  if (json['version'] is! int) throw const FormatException('无效的备份文件');
  await restoreVault(db, json, providerStore: providerStore);
  final conv = (json['conversations'] as List?)?.length ?? 0;
  final msg = (json['messages'] as List?)?.length ?? 0;
  final providers = (json['providerProfiles'] as List?)?.length ?? 0;
  final mcp = (json['mcpServers'] as List?)?.length ?? 0;
  final extras = [
    if (providers > 0) '$providers 个 Provider 配置',
    if (mcp > 0) '$mcp 台 MCP 服务器',
  ];
  return [
    '已恢复 $conv 个会话、$msg 条消息',
    if (extras.isNotEmpty) '（含 ${extras.join('、')}）',
  ].join();
}

Future<Map<String, dynamic>> buildVaultJson(AppDatabase db,
    {ProviderConfigStore? providerStore, bool includeSecrets = false}) async {
  final store = providerStore ?? ProviderConfigStore();
  final conversations = await db.recentConversations();
  final messages = <Map<String, dynamic>>[];
  for (final c in conversations) {
    final rows = await db.messagesFor(c.id);
    final toolNamesById = <String, String>{};
    for (final row in rows) {
      if (row.role != 'assistant' || row.toolCallsJson == null) continue;
      try {
        final calls = jsonDecode(row.toolCallsJson!);
        if (calls is List) {
          for (final call in calls.whereType<Map>()) {
            final id = call['id']?.toString();
            final name = call['name']?.toString();
            if (id != null && name != null) toolNamesById[id] = name;
          }
        }
      } catch (_) {
        // 可忽略：toolCallsJson 损坏时只跳过「工具名映射」这一步，消息本身
        // 仍会导出（下方的脱敏会退化为按敏感工具策略整体兜底）。
      }
    }
    messages.addAll(rows
        .map((row) => _redactPersistedMessage(row.toJson(), toolNamesById)));
  }
  final profiles = await store.loadAll();
  return {
    'version': 2,
    'conversations': conversations.map((c) => c.toJson()).toList(),
    'messages': messages,
    'memories': (await db.allMemories()).map((m) => m.toJson()).toList(),
    'agents': (await db.allAgents()).map((a) => a.toJson()).toList(),
    'prompts': (await db.allPromptTemplates()).map((p) => p.toJson()).toList(),
    'modelProfiles':
        (await db.allModelProfiles()).map((p) => p.toJson()).toList(),
    'knowledgeDocs':
        (await db.allKnowledgeDocs()).map((d) => d.toJson()).toList(),
    'knowledgeChunks':
        (await db.allKnowledgeChunks()).map((c) => c.toJson()).toList(),
    'scheduledTasks':
        (await db.allScheduledTasks()).map((t) => t.toJson()).toList(),
    'plugins': (await db.allPlugins()).map((p) => p.toJson()).toList(),
    'skillPacks': (await db.allSkillPacks()).map((s) => s.toJson()).toList(),
    'skillFiles': await _collectSkillFiles(db),
    'projects': (await db.allProjects(includeArchived: true))
        .map((t) => t.toJson())
        .toList(),
    'drafts': (await db.select(db.drafts).get()).map((t) => t.toJson()).toList(),
    'artifacts': await db.allArtifactRecords(),
    'runControls':
        (await db.select(db.runControls).get()).map((t) => t.toJson()).toList(),
    'executionLeases': (await db.select(db.executionLeases).get())
        .map((t) => t.toJson())
        .toList(),
    'tasks': (await db.allTasks(limit: 2000)).map((t) => t.toJson()).toList(),
    'taskFeedback':
        (await db.allTaskFeedback()).map((t) => t.toJson()).toList(),
    'collaborationRuns':
        (await db.allCollaborationRuns(limit: 2000)).map((t) => t.toJson()).toList(),
    'collaborationAgentRuns':
        (await db.allCollaborationAgentRuns()).map((t) => t.toJson()).toList(),
    'collaborationArtifacts':
        (await db.allCollaborationArtifacts()).map((t) => t.toJson()).toList(),
    'collaborationMessages':
        (await db.allCollaborationMessages()).map((t) => t.toJson()).toList(),
    'auditLogs': (await db.allAuditLogs())
        .map((t) => _redactAuditLog(t.toJson()))
        .toList(),
    'runRecords': (await db.allRunRecords()).map((t) => t.toJson()).toList(),
    'runEvents': (await db.allRunEvents())
        .map((t) => _redactRunEvent(t.toJson()))
        .toList(),
    'logRecords': (await db.allLogRecords())
        .map((t) => _redactLogRecord(t.toJson()))
        .toList(),
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
    'mcpServers': (await db.allMcpServers()).map((s) => s.toJson()).toList(),
  };
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

Future<void> restoreVault(AppDatabase db, Map<String, dynamic> json,
    {ProviderConfigStore? providerStore}) async {
  // Validate optional secret payload before clearing the database. A malformed
  // profile must not turn a later restore failure into data loss.
  _providerConfigsFromJson(json['providerProfiles']);
  await db.transaction(() async {
    await db.clearAllUserData();
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
      await db.saveMemory(Memory.fromJson(m));
    }
    for (final m
        in (json['agents'] as List? ?? const []).cast<Map<String, dynamic>>()) {
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
    await _restoreOptionalRows(
        json['taskFeedback'], db.saveTaskFeedbackRow, TaskFeedbackData.fromJson);
    await _restoreOptionalRows(json['collaborationRuns'],
        db.saveCollaborationRun, CollaborationRun.fromJson);
    await _restoreOptionalRows(json['collaborationAgentRuns'],
        db.saveCollaborationAgentRun, CollaborationAgentRun.fromJson);
    await _restoreOptionalRows(json['collaborationArtifacts'],
        db.saveCollaborationArtifact, CollaborationArtifact.fromJson);
    await _restoreOptionalRows(json['collaborationMessages'],
        db.saveCollaborationMessage, CollaborationMessage.fromJson);
    await _restoreOptionalRows(json['auditLogs'], db.saveAuditLog, AuditLog.fromJson);
    await _restoreOptionalRows(
        json['runRecords'], db.saveRunRecordRow, RunRecord.fromJson);
    await _restoreOptionalRows(
        json['runEvents'], db.saveRunEventRow, RunEvent.fromJson);
    await _restoreOptionalRows(
        json['logRecords'], db.saveLogRecordRow, LogRecord.fromJson);
    // MCP 配置的正式来源是数据库；仅当备份含该段（v2+）时覆盖。
    if (json['mcpServers'] is List) {
      await db.clearMcpServers();
      for (final m
          in (json['mcpServers'] as List).cast<Map<String, dynamic>>()) {
        await db.saveMcpServer(McpServer.fromJson(m));
      }
    }
  });
  await _restoreSkillFiles(db, json);
  await _restoreProviderSecrets(
      db, json, providerStore ?? ProviderConfigStore());
}

List<ProviderConfig> _providerConfigsFromJson(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
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
      .where((config) => config.model.trim().isNotEmpty)
      .toList();
}

/// 恢复 Provider 配置（含 API Key）与工具密钥到安全存储；旧版备份无该段时跳过。
Future<void> _restoreOptionalRows<T>(
  Object? raw,
  Future<void> Function(T row) save,
  T Function(Map<String, dynamic> json) fromJson,
) async {
  if (raw is! List) return;
  for (final item in raw.whereType<Map>()) {
    try {
      await save(fromJson(Map<String, dynamic>.from(item)));
    } catch (error, stackTrace) {
      // 可忽略（有意降级）：单行损坏不阻断整份备份恢复——整份回滚会让用户
      // 在「一条坏数据」与「全部丢失」之间被迫二选一。上报以统计损坏率，
      // 便于判断备份格式是否在退化。
      unawaited(SentryService.reportException(error, stackTrace));
    }
  }
}

Future<void> _restoreProviderSecrets(AppDatabase db, Map<String, dynamic> json,
    ProviderConfigStore store) async {
  final profilesJson = json['providerProfiles'];
  if (profilesJson is List) {
    final configs = _providerConfigsFromJson(profilesJson);
    if (configs.isNotEmpty) {
      // 导出时 profiles 首个不一定是激活项，但备份快照顺序即 loadAll 顺序
      // （首项为激活配置），恢复后保持一致。
      await store.restoreProfiles(configs, activeId: configs.first.id);
    }
  }
  final toolKeys = json['toolKeys'];
  if (toolKeys is Map) {
    for (final entry in toolKeys.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
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
  for (final pack in packs) {
    final files = <String, String>{};
    final root = Directory(pack.installRoot);
    if (root.existsSync()) {
      await for (final entity in root.list(recursive: true)) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: root.path);
          try {
            files[rel] = base64Encode(await entity.readAsBytes());
          } catch (error, stackTrace) {
            // 可忽略（有意降级）：单个文件读取失败不影响整体导出（如权限、
            // 文件被占用）。缺失文件在恢复后表现为技能文件不全，属可接受降级。
            unawaited(SentryService.reportException(error, stackTrace));
          }
        }
      }
    }
    out[pack.id] = files;
  }
  return out;
}

/// 恢复 skill 文件到当前设备的技能目录，并修正 installRoot（换机后旧路径失效）。
Future<void> _restoreSkillFiles(
    AppDatabase db, Map<String, dynamic> json) async {
  final packs = await db.allSkillPacks();
  if (packs.isEmpty) return;
  final String docDir;
  try {
    docDir = (await getApplicationDocumentsDirectory()).path;
  } catch (_) {
    // path_provider 不可用（如单测环境）时跳过文件恢复，不影响数据库导入。
    return;
  }
  final filesMap = (json['skillFiles'] as Map?) ?? const {};
  for (final pack in packs) {
    final files = (filesMap[pack.id] as Map?)?.cast<String, dynamic>() ?? {};
    try {
      final installRoot = p.join(docDir, 'skills', pack.name);
      final root = Directory(installRoot);
      await root.create(recursive: true);
      for (final e in files.entries) {
        final rel = e.key;
        if (rel.contains('..') || p.isAbsolute(rel)) continue;
        final f = File(p.join(root.path, rel));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(base64Decode(e.value as String? ?? ''));
      }
      if (pack.installRoot != installRoot) {
        await db.saveSkillPack(pack.copyWith(installRoot: installRoot));
      }
    } catch (_) {
      // 恢复单包失败不阻断整体。
    }
  }
}
