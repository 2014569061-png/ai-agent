import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MCP 服务器连接方式。
enum McpServerKind {
  /// Streamable HTTP（浏览器 / 移动端均可）。
  http,

  /// stdio 子进程（桌面 / 命令行）。
  ///
  /// ⚠️ 移动端（Android）默认**不暴露**该选项：它会 spawn 任意本地可执行文件，
  /// 属于「高权限本地执行」面。要启用需在 MCP 页面连点标题 5 次打开真机开关，
  /// 且每个 stdio 服务器保存前都必须过一次高危确认。
  stdio,
}

/// stdio 型 MCP 的可用性判定（唯一权威，UI 与运行时共用）。
class McpStdioAvailability {
  const McpStdioAvailability._();

  /// 移动端真机开关的持久化键。默认关闭。
  static const preferenceKey = 'mcp.stdio_experimental';

  /// 当前平台是否原生支持 stdio。
  ///
  /// Web 没有子进程能力；Android 出于权限面考虑默认关闭，
  /// 需要用户显式打开真机开关。
  static bool get supportedByPlatform => !kIsWeb;

  /// 在 [enabled] 前提下，当前是否允许使用 stdio 型服务器。
  static bool isUsable({required bool enabled}) =>
      supportedByPlatform && enabled;

  /// 不可用时给用户看的解释（可用时返回 null）。
  static String? blockedReason({required bool enabled}) {
    if (kIsWeb) return 'Web 平台不支持 stdio 型服务器';
    if (!enabled) return '移动端默认关闭本地进程模式，需在 MCP 页面开启真机开关';
    return null;
  }

  /// 读取持久化的真机开关（默认 false）。
  static Future<bool> readEnabled() async {
    if (!supportedByPlatform) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(preferenceKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 写入真机开关。
  static Future<void> writeEnabled(bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(preferenceKey, value);
    } catch (_) {}
  }
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

  McpServerConfig copyWith({
    String? name,
    McpServerKind? kind,
    String? url,
    String? command,
    List<String>? args,
    bool? enabled,
  }) =>
      McpServerConfig(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        url: url ?? this.url,
        command: command ?? this.command,
        args: args ?? this.args,
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
