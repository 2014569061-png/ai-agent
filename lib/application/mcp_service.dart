import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:drift/drift.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/mcp/mcp_server_config.dart';

/// MCP 配置的唯一持久化入口。
///
/// 数据库存储是正式来源；首次访问时会导入旧版本 SharedPreferences 中的
/// 配置，保证升级后用户既有服务器不会丢失。
class McpService {
  McpService({Future<AppDatabase>? database})
      : _database = database ?? DatabaseProvider.instance.database;

  final Future<AppDatabase> _database;
  bool _legacyMigrated = false;

  Future<List<McpServerConfig>> loadAll() async {
    final database = await _readyDatabase();
    return (await database.allMcpServers())
        .map(_toConfig)
        .toList(growable: false);
  }

  Future<List<McpServerConfig>> loadEnabled() async {
    final database = await _readyDatabase();
    return (await database.enabledMcpServers())
        .map(_toConfig)
        .toList(growable: false);
  }

  Future<void> save(McpServerConfig config) async {
    final database = await _readyDatabase();
    await database.insertMcpServer(_toCompanion(config));
  }

  Future<void> toggleServer(String id, bool enabled) async {
    final database = await _readyDatabase();
    await (database.update(database.mcpServers)
          ..where((row) => row.id.equals(id)))
        .write(McpServersCompanion(enabled: Value(enabled)));
  }

  Future<void> delete(String id) async {
    final database = await _readyDatabase();
    await database.deleteMcpServer(id);
  }

  Future<void> clear() async {
    final database = await _readyDatabase();
    await database.clearMcpServers();
  }

  Future<AppDatabase> _readyDatabase() async {
    final database = await _database;
    if (_legacyMigrated) return database;
    _legacyMigrated = true;
    if ((await database.allMcpServers()).isNotEmpty) return database;

    final legacy = await McpServerStore().loadAll();
    for (final config in legacy) {
      await database.insertMcpServer(_toCompanion(config));
    }
    return database;
  }

  static McpServersCompanion _toCompanion(McpServerConfig config) =>
      McpServersCompanion.insert(
        id: config.id,
        name: config.name,
        kind: config.kind.name,
        url: Value(config.url),
        command: Value(config.command),
        args: Value(jsonEncode(config.args)),
        enabled: Value(config.enabled),
      );

  static McpServerConfig _toConfig(McpServer row) {
    List<String> args = const [];
    try {
      final value = jsonDecode(row.args);
      if (value is List) {
        args = value.whereType<String>().toList(growable: false);
      }
    } catch (error) {
      debugPrint('解析 MCP 配置 args 失败 (id=${row.id}): $error');
    }
    return McpServerConfig(
      id: row.id,
      name: row.name,
      kind: McpServerKind.values.firstWhere(
        (kind) => kind.name == row.kind,
        orElse: () => McpServerKind.http,
      ),
      url: row.url,
      command: row.command,
      args: args,
      enabled: row.enabled,
    );
  }
}
