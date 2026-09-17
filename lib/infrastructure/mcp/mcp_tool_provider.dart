import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../../domain/models.dart';
import '../../domain/network_access_policy.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../tools/tool_registry.dart';
import 'mcp_server_config.dart';

/// 管理 MCP 服务器连接，并把远端工具统一映射为 [AgentTool]。
///
/// 连接建立后保持复用（Map 缓存），避免每次 Agent 循环重连；
/// 调用 [dispose] 统一关闭。
///
/// 两条出口各有一道闸门：
/// * **HTTP** 走 `NetworkAccessPolicy`（唯一权威），与 `http_request` / 插件
///   声明式工具同一条策略——私网、回环、元数据地址一律拒绝。
/// * **stdio** 走 [McpStdioAvailability]，并且**子进程不继承父环境变量**。
class McpToolProvider {
  McpToolProvider({
    NetworkAccessPolicy? policy,
    bool? stdioEnabled,
  })  : _policy = policy ?? const NetworkAccessPolicy(),
        _stdioEnabledOverride = stdioEnabled;

  final NetworkAccessPolicy _policy;

  /// 测试注入用：覆盖真机开关的读取结果。生产环境传 null，走 SharedPreferences。
  final bool? _stdioEnabledOverride;

  final Map<String, mcp.McpClient> _clients = {};

  /// 读取当前生效的 stdio 真机开关。默认关闭。
  Future<bool> _stdioEnabled() async {
    final override = _stdioEnabledOverride;
    if (override != null) return override;
    return McpStdioAvailability.readEnabled();
  }

  /// 连接并列出该服务器全部工具，映射为 [AgentTool]。
  /// 失败返回空列表（调用方跳过该服务器，不影响其他工具）。
  Future<List<AgentTool>> connectAndListTools(McpServerConfig server) async {
    if (!await _isAllowed(server)) return const [];
    try {
      final client = await _connect(server);
      final result = await client.listTools();
      return result.tools
          .map((tool) => McpTool(client: client, server: server, tool: tool))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// 出口准入检查。返回 false 时 [lastBlockReason] 会带上可读原因。
  Future<bool> _isAllowed(McpServerConfig server) async {
    switch (server.kind) {
      case McpServerKind.http:
        final decision = _policy.inspect(server.url?.trim() ?? '');
        if (!decision.allowed) {
          _lastBlockReason = decision.reason;
          return false;
        }
        return true;
      case McpServerKind.stdio:
        final enabled = await _stdioEnabled();
        final reason = McpStdioAvailability.blockedReason(enabled: enabled);
        if (reason != null) {
          _lastBlockReason = reason;
          return false;
        }
        return true;
    }
  }

  String? _lastBlockReason;

  /// 最近一次被准入策略拒绝的原因（供设置页展示）。
  String? get lastBlockReason => _lastBlockReason;

  /// 仅测试连接连通性与可用的工具数量，不缓存、不映射 AgentTool。
  /// 返回 null 表示连接失败，否则返回 (是否可用, 工具数量, 错误消息)。
  Future<({bool ok, int toolCount, String? error})> testConnection(
      McpServerConfig server) async {
    if (!await _isAllowed(server)) {
      return (ok: false, toolCount: 0, error: _lastBlockReason);
    }
    mcp.McpClient? client;
    try {
      client = mcp.McpClient(
        const mcp.Implementation(name: 'nexus-agent', version: '0.1.0'),
        options: const mcp.McpClientOptions(protocol: mcp.McpProtocol.legacy),
      );
      switch (server.kind) {
        case McpServerKind.http:
          final url = server.url?.trim() ?? '';
          if (url.isEmpty) {
            return (ok: false, toolCount: 0, error: '未配置 HTTP URL');
          }
          final transport = mcp.StreamableHttpClientTransport(Uri.parse(url));
          await client.connect(transport);
        case McpServerKind.stdio:
          final transport = mcp.StdioClientTransport(
            mcp.StdioServerParameters(
              command: server.command ?? 'npx',
              args: server.args,
              // 不把 App 进程的环境变量全量透传给子进程：里面可能有用户配置的
              // Provider API Key、代理凭据。子进程按需在命令里自己声明。
              includeParentEnvironment: false,
            ),
          );
          await client.connect(transport);
      }
      final result = await client.listTools();
      return (
        ok: true,
        toolCount: result.tools.length,
        error: result.tools.isEmpty ? '连接成功，但未发现任何工具' : null,
      );
    } catch (error) {
      return (ok: false, toolCount: 0, error: '$error');
    } finally {
      if (client != null) {
        try {
          await client.close();
        } catch (_) {}
      }
    }
  }

  Future<mcp.McpClient> _connect(McpServerConfig server) async {
    final existing = _clients[server.id];
    if (existing != null) return existing;

    final client = mcp.McpClient(
      const mcp.Implementation(name: 'nexus-agent', version: '0.1.0'),
      options: const mcp.McpClientOptions(protocol: mcp.McpProtocol.legacy),
    );
    switch (server.kind) {
      case McpServerKind.http:
        final url = server.url?.trim() ?? '';
        final transport = mcp.StreamableHttpClientTransport(Uri.parse(url));
        await client.connect(transport);
      case McpServerKind.stdio:
        final transport = mcp.StdioClientTransport(
          mcp.StdioServerParameters(
            command: server.command ?? 'npx',
            args: server.args,
            includeParentEnvironment: false,
          ),
        );
        await client.connect(transport);
    }
    _clients[server.id] = client;
    return client;
  }

  /// 对比最新启用列表，关闭已停用 / 已删除服务器的连接，
  /// 避免设置页开关或删除后旧连接泄漏。
  Future<void> syncServers(List<McpServerConfig> enabled) async {
    final activeIds = enabled.map((server) => server.id).toSet();
    final staleIds =
        _clients.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in staleIds) {
      final client = _clients.remove(id);
      if (client != null) {
        try {
          await client.close();
        } catch (_) {}
      }
    }
  }

  /// 关闭全部连接（ProviderScope 销毁时调用）。
  Future<void> dispose() async {
    for (final client in _clients.values) {
      try {
        await client.close();
      } catch (_) {}
    }
    _clients.clear();
  }
}

/// 把单个 MCP 远端工具包装为 [AgentTool]。
class McpTool implements AgentTool {
  McpTool({required this.client, required this.server, required this.tool});

  final mcp.McpClient client;
  final McpServerConfig server;
  final mcp.Tool tool;

  /// 工具名带稳定的 MCP 前缀与服务器前缀，避免与内置工具冲突，
  /// 同时让持久化/日志出口可以按命名空间统一脱敏。
  String get qualifiedName => 'mcp_${server.name}.${tool.name}';

  @override
  UnifiedTool get manifest => UnifiedTool(
        name: qualifiedName,
        description: tool.description ?? 'MCP 工具：${tool.name}',
        parametersSchema: tool.inputSchema.toJson(),
        // MCP 远端工具可执行任意操作，默认需要用户确认。
        risk: ToolRisk.requiresConfirmation,
        sensitive: true,
      );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final result = await client.callTool(
        mcp.CallToolRequest(name: tool.name, arguments: arguments),
      );
      final text = result.content
          .whereType<mcp.TextContent>()
          .map((content) => content.text)
          .join('\n');
      final structured = result.structuredContent;
      final payload = text.isNotEmpty
          ? text
          : (structured != null && structured.isNotEmpty
              ? jsonEncode(structured)
              : '');
      if (result.isError) {
        return ToolResult.failure(
          code: ToolCodes.toolError,
          message: payload.isEmpty ? 'MCP 工具执行失败（无返回内容）' : payload,
          // 远端已收到调用，失败响应无法证明是否产生了副作用。
          effect: ToolEffect.unknown,
        );
      }
      return ToolResult.text(
        payload.isEmpty ? '工具已执行（无返回内容）' : payload,
        effect: ToolEffect.applied,
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.networkUnavailable,
        message: 'MCP 工具调用失败：$error；远端可能已执行，请先确认状态再决定是否重试',
        effect: ToolEffect.unknown,
      );
    }
  }
}
