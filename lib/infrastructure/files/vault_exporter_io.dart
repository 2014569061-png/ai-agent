import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../../domain/models.dart';
import '../providers/provider_config.dart';
import '../providers/provider_config_store.dart';
import '../sync/sync_service.dart';

/// G3 隐私保险箱：把全量本地数据打包为单个 AES-256-GCM 加密文件（.nexusvault）。
/// 导入时先备份现有库再覆盖写入，密码丢失无法恢复。
/// v2 起额外包含 Provider 配置（含 API Key）、工具密钥与 MCP 服务器配置；
/// 旧版备份文件缺少这些段时按原样跳过。

Future<String?> exportVaultFile(AppDatabase db, String password,
    {bool includeSecrets = false}) async {
  try {
    final json = await buildVaultJson(db, includeSecrets: includeSecrets);
    final plaintext = jsonEncode(json);
    final cipher = await SyncService().encryptWithPassword(plaintext, password);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(
        dir.path, 'nexus-${DateTime.now().millisecondsSinceEpoch}.nexusvault'));
    await file.writeAsString(cipher, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

/// 从加密文件字节解密并全量恢复。返回解密后的数据条数摘要。
Future<String> importVaultBytes(AppDatabase db, Uint8List bytes, String password,
    {ProviderConfigStore? providerStore}) async {
  final cipher = utf8.decode(bytes);
  final plaintext = await SyncService().decryptWithPassword(cipher, password);
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
    messages.addAll((await db.messagesFor(c.id)).map((m) => m.toJson()));
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
              })
          .toList(),
    if (includeSecrets)
      'toolKeys': {
        'tavily': await store.readToolKey('tavily'),
      },
    'mcpServers': (await db.allMcpServers()).map((s) => s.toJson()).toList(),
  };
}

Future<void> restoreVault(AppDatabase db, Map<String, dynamic> json,
    {ProviderConfigStore? providerStore}) async {
  await db.transaction(() async {
    await db.clearAllUserData();
    for (final m in (json['conversations'] as List? ?? const [])
        .cast<Map<String, dynamic>>()) {
      await db.saveConversation(Conversation.fromJson(m));
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
    // MCP 配置的正式来源是数据库；仅当备份含该段（v2+）时覆盖。
    if (json['mcpServers'] is List) {
      await db.clearMcpServers();
      for (final m in (json['mcpServers'] as List)
          .cast<Map<String, dynamic>>()) {
        await db.saveMcpServer(McpServer.fromJson(m));
      }
    }
  });
  await _restoreSkillFiles(db, json);
  await _restoreProviderSecrets(db, json,
      providerStore ?? ProviderConfigStore());
}

/// 恢复 Provider 配置（含 API Key）与工具密钥到安全存储；旧版备份无该段时跳过。
Future<void> _restoreProviderSecrets(AppDatabase db,
    Map<String, dynamic> json, ProviderConfigStore store) async {
  try {
    final profilesJson = json['providerProfiles'];
    if (profilesJson is List) {
      final configs = profilesJson
          .whereType<Map<String, dynamic>>()
          .map((item) => ProviderConfig(
                id: item['id'] as String? ?? 'default',
                name: item['name'] as String? ?? 'Provider',
                baseUrl: item['baseUrl'] as String? ?? '',
                model: item['model'] as String? ?? '',
                apiKey: item['apiKey'] as String? ?? '',
                type: ProviderType.values.firstWhere(
                    (t) => t.name == item['type'],
                    orElse: () => ProviderType.openaiCompatible),
                reasoningEffort: ReasoningEffort.values
                    .firstWhere((e) => e.name == item['reasoningEffort'],
                        orElse: () => ReasoningEffort.medium),
                contextTokens: (item['contextTokens'] as num?)?.toInt() ??
                    ProviderConfig.defaultContextTokens,
              ))
          .where((config) => config.model.trim().isNotEmpty)
          .toList();
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
  } catch (_) {
    // 密钥恢复失败不阻断整体导入。
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
          } catch (_) {
            // 单个文件读取失败不影响整体导出。
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
