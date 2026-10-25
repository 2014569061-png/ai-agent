import 'dart:convert';
import 'context_result_vault.dart';
import 'run_plan_vault.dart';
import 'mobile_module_vault.dart';
import '../database/memory_forget_store.dart';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

class VaultLimits {
  static const maxJsonBytes = 64 * 1024 * 1024;
  static const maxCipherBytes = 96 * 1024 * 1024;
  static const maxRows = 100000;
  static const maxFiles = 2000;
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxSkillBytes = 32 * 1024 * 1024;
}

class VaultRestoreReport {
  const VaultRestoreReport(this.counts, this.files, {this.warnings = const []});
  final List<String> warnings;
  final Map<String, int> counts;
  final int files;
  String get summary => '已恢复 ${counts['conversations'] ?? 0} 个会话、'
      '${counts['messages'] ?? 0} 条消息、$files 个技能文件'
      '${warnings.isEmpty ? '' : '；${warnings.join('；')}'}';
}

Future<String> encodeVaultJson(Map<String, dynamic> data) => Isolate.run(() {
      final encoded = jsonEncode(data);
      if (utf8.encode(encoded).length > VaultLimits.maxJsonBytes) {
        throw const FormatException('备份超过 64MB 容量上限');
      }
      return encoded;
    });

Future<Map<String, dynamic>> sealVault(Map<String, dynamic> data) =>
    Isolate.run(() {
      final counts = <String, int>{};
      final hashes = <String, String>{};
      for (final entry in data.entries) {
        if (entry.value is List) {
          counts[entry.key] = (entry.value as List).length;
        }
        hashes[entry.key] =
            sha256.convert(utf8.encode(jsonEncode(entry.value))).toString();
      }
      data['manifest'] = {
        'schema': 1,
        'complete': true,
        'counts': counts,
        'sha256': hashes
      };
      return data;
    });

/// Validate structure/size/checksums before deleting or writing anything.
Future<void> validateVault(Map<String, dynamic> data) => Isolate.run(() {
      if (data['version'] != 1 && data['version'] != 2) {
        throw const FormatException('不支持的备份版本');
      }
      if (utf8.encode(jsonEncode(data)).length > VaultLimits.maxJsonBytes) {
        throw const FormatException('备份超过容量上限');
      }
      const listSections = {
        'conversations',
        'messages',
        'memories',
        'memoryForgetRules',
        'agents',
        'prompts',
        'modelProfiles',
        'knowledgeDocs',
        'knowledgeScopes',
        'knowledgeChunks',
        'scheduledTasks',
        'plugins',
        'skillPacks',
        'projects',
        'drafts',
        'runControls',
        'runPlanHeads',
        'planRevisions',
        'runDispatchClaims',
        'executionLeases',
        'tasks',
        'taskFeedback',
        'collaborationRuns',
        'collaborationAgentRuns',
        'collaborationArtifacts',
        'collaborationMessages',
        'auditLogs',
        'runRecords',
        'runEvents',
        'logRecords',
        'mcpServers',
        'artifacts',
        'providerProfiles',
        'personalContextEntities',
        'personalContextRelations',
        'personalContextAliases',
        'personalContextTombstones',
        'personalContextRevisions',
        'resultCards',
        'resultActions',
      };
      for (final section in listSections) {
        if (data.containsKey(section) && data[section] is! List) {
          throw FormatException('备份数据段不是列表：$section');
        }
      }
      for (final section in ['skillFiles', 'toolKeys']) {
        if (data.containsKey(section) && data[section] is! Map) {
          throw FormatException('备份数据段不是映射：$section');
        }
      }
      if (data['toolKeys'] is Map &&
          (data['toolKeys'] as Map).values.any((value) => value is! String)) {
        throw const FormatException('工具密钥格式错误');
      }
      var rows = 0;
      for (final entry in data.entries) {
        if (entry.value is List) {
          final list = entry.value as List;
          rows += list.length;
          if (list.any((item) => item is! Map<String, dynamic>)) {
            throw FormatException('备份数据格式错误：${entry.key}');
          }
        }
      }
      if (rows > VaultLimits.maxRows) throw const FormatException('备份记录过多');
      for (final row in (data['memoryForgetRules'] as List? ?? const [])) {
        MemoryForgetStore.validateRow(Map<String, dynamic>.from(row as Map));
      }
      final knowledgeIds = {
        for (final row in (data['knowledgeDocs'] as List? ?? const []))
          row['id']
      };
      for (final row in (data['knowledgeScopes'] as List? ?? const [])) {
        if (row['docId'] is! String ||
            !knowledgeIds.contains(row['docId']) ||
            (row['docId'] as String).length > 256 ||
            row['projectId'] is! String ||
            (row['projectId'] as String).isEmpty ||
            (row['projectId'] as String).length > 256) {
          throw const FormatException('知识项目范围格式错误');
        }
      }
      validateRunPlanVault(data);
      validateContextResultVault(data);
      validateMobileModuleVault(data);
      final manifest = data['manifest'];
      if (manifest != null) {
        if (manifest is! Map ||
            manifest['schema'] != 1 ||
            manifest['complete'] != true ||
            manifest['sha256'] is! Map ||
            manifest['counts'] is! Map) {
          throw const FormatException('备份清单不完整');
        }
        final hashes = manifest['sha256'] as Map;
        if (hashes.length != data.length - 1) {
          throw const FormatException('备份清单缺少数据段');
        }
        for (final entry in data.entries.where((e) => e.key != 'manifest')) {
          final digest =
              sha256.convert(utf8.encode(jsonEncode(entry.value))).toString();
          if (hashes[entry.key] != digest ||
              (entry.value is List &&
                  (manifest['counts'] as Map)[entry.key] !=
                      (entry.value as List).length)) {
            throw FormatException('备份校验失败：${entry.key}');
          }
        }
      }
    });
