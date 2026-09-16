import '../domain/agent_draft.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/database_provider.dart';
import '../infrastructure/mcp/mcp_tool_provider.dart';
import '../infrastructure/plugins/plugin_store.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/tool_registry.dart';
import 'mcp_service.dart';

/// 收集当前设备上可供 Agent 授权的工具：内置 + 声明式插件 + 已启用的 MCP 服务。
///
/// 编辑器与「对话式创建 Agent」共用这一份来源。两边若各取一套，「生成时可选」与
/// 「编辑器里能勾选」就会漂移，表现为草稿里的工具在编辑器里成了勾不上的幽灵项。
///
/// [database] 应当由调用方把注入点（`databaseProvider`）传进来。**不要**在这里
/// 回落到全局单例：那样在 widget 测试里会去触发真实的 path_provider 平台通道，
/// 而 `testWidgets` 的假异步环境不会推进真实 I/O，函数会永远挂住，调用方界面卡在
/// 「生成中」。这是本文件第一版踩过的坑，留此说明避免改回去。
Future<List<AgentTool>> loadAvailableAgentTools(
    {Future<AppDatabase>? database}) async {
  final tools = <AgentTool>[
    CalculatorTool(),
    GetTimeTool(),
    JsonQueryTool(),
    HttpRequestTool(),
    WebSearchTool(apiKey: ''),
  ];

  try {
    final db = await (database ?? DatabaseProvider.instance.database);
    tools.addAll(await PluginStore().loadDeclarativeTools(db));
  } catch (_) {
    // 插件读取失败不影响内置工具可用。
  }

  final provider = McpToolProvider();
  try {
    final servers = await McpService(database: database).loadEnabled();
    for (final server in servers) {
      try {
        tools.addAll(await provider.connectAndListTools(server));
      } catch (_) {
        // 单台 MCP 服务不可用不应中断整份清单。
      }
    }
  } catch (_) {
    // 同上：MCP 配置不可读时只提供内置工具。
  }
  await provider.dispose();

  final seen = <String>{};
  return tools
      .where((tool) => seen.add(tool.manifest.name))
      .toList(growable: false);
}

/// 把工具清单投影成草稿生成所需的摘要（名称 + 说明 + 风险等级）。
List<AgentToolSpec> toToolSpecs(Iterable<AgentTool> tools) => [
      for (final tool in tools)
        AgentToolSpec(
          name: tool.manifest.name,
          description: tool.manifest.description,
          risk: tool.manifest.risk,
        ),
    ];
