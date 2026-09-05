import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MCP 服务器连接方式。
enum McpServerKind {
  /// Streamable HTTP（浏览器 / 移动端均可）。
  http,

  /// stdio 子进程（仅桌面 / 命令行，Web 不支持）。
  stdio,
}

/// 一个 MCP 服务器配置。
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.kind,
    this.url,
    this.command,
    this.args = const [],
    this.enabled = true,
  });

  final String id;
  final String name;
  final McpServerKind kind;

  /// kind == http 时的端点地址。
  final String? url;

  /// kind == stdio 时的可执行命令。
  final String? command;
  final List<String> args;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'url': url,
        'command': command,
        'args': args,
        'enabled': enabled,
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'MCP Server',
        kind: McpServerKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => McpServerKind.http,
        ),
        url: json['url'] as String?,
        command: json['command'] as String?,
        args: (json['args'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        enabled: json['enabled'] as bool? ?? true,
      );

  McpServerConfig copyWith({bool? enabled}) => McpServerConfig(
        id: id,
        name: name,
        kind: kind,
        url: url,
        command: command,
        args: args,
        enabled: enabled ?? this.enabled,
      );
}

/// MCP 服务器配置的本地持久化（SharedPreferences）。
///
/// 与 ProviderConfigStore 一样，web / 原生统一走 SharedPreferences，
/// 避免隐私模式下 secure storage 静默失败的问题。
class McpServerStore {
  static const _key = 'mcp.servers';

  Future<List<McpServerConfig>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(McpServerConfig.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<McpServerConfig>> loadEnabled() async {
    final all = await loadAll();
    return all.where((server) => server.enabled).toList();
  }

  Future<void> saveAll(List<McpServerConfig> servers) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
  }

  Future<void> save(McpServerConfig server) async {
    final all = await loadAll();
    final updated = [...all.where((item) => item.id != server.id), server];
    await saveAll(updated);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    await saveAll(all.where((item) => item.id != id).toList());
  }

  /// 校验地址基本合法性（HTTP 型）。
  static bool isValidUrl(String url) {
    if (kIsWeb) return true;
    final uri = Uri.tryParse(url);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }
}
