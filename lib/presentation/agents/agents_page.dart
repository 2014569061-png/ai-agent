import '../l10n/app_strings.dart';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../application/mojibake_repair.dart';
import '../../infrastructure/tools/core_tools.dart';
import '../../infrastructure/tools/tool_registry.dart';
import '../../infrastructure/mcp/mcp_tool_provider.dart';
import '../../infrastructure/plugins/plugin_store.dart';
import '../../application/mcp_service.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});
  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  late Future<List<Agent>> _agents;
  final _toolOptions = <AgentTool>[
    CalculatorTool(),
    GetTimeTool(),
    JsonQueryTool(),
    HttpRequestTool(),
    WebSearchTool(apiKey: '')
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _agents = DatabaseProvider.instance.database.then((db) async {
      final agents = await db.allAgents();
      return agents
          .map((agent) =>
              agent.copyWith(name: MojibakeRepair.repair(agent.name)))
          .toList();
    });
  }

  Future<List<AgentTool>> _loadAvailableTools() async {
    final tools = <AgentTool>[..._toolOptions];
    try {
      tools.addAll(await PluginStore()
          .loadDeclarativeTools(await DatabaseProvider.instance.database));
    } catch (_) {}

    final provider = McpToolProvider();
    try {
      final servers = await McpService().loadEnabled();
      for (final server in servers) {
        try {
          tools.addAll(await provider.connectAndListTools(server));
        } catch (_) {}
      }
    } catch (_) {}
    await provider.dispose();

    final seen = <String>{};
    return tools.where((tool) => seen.add(tool.manifest.name)).toList();
  }

  Future<void> _openAgentEditor([Agent? agent]) async {
    final toolOptions = await _loadAvailableTools();
    if (!mounted) return;

    final nameController = TextEditingController(text: agent?.name ?? '通用助手');
    final promptController = TextEditingController(
        text: agent?.systemPrompt ?? '你是一个有帮助的 AI Agent。');
    var steps = (agent?.maxSteps ?? 8).clamp(1, 32);
    var temperature = (agent?.temperature ?? 0.7).clamp(0.0, 2.0);
    var maxTokens = (agent?.maxTokens ?? 2048).clamp(256, 8192);
    var topP = (agent?.topP ?? 1.0).clamp(0.0, 1.0);

    final parsed = agent != null
        ? (jsonDecode(agent.enabledToolsJson) as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet()
        : const <String>{};
    final enabled = parsed.isEmpty
        ? <String>{'calculator', 'get_time', 'json_query'}
        : {...parsed};

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusModal)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          agent == null
                              ? AppStrings.createAgent
                              : AppStrings.editAgent,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? AppPalette.darkHairline
                        : AppPalette.lightHairline,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. 基本信息
                          const Text(
                            '基本信息',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.brandAction,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: '${AppStrings.agentName} *',
                              hintText: '如：代码分析师、客服助手',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: promptController,
                            maxLines: 4,
                            minLines: 2,
                            decoration: const InputDecoration(
                              labelText: '${AppStrings.systemPrompt} *',
                              hintText: '描述该智能体的角色设定、行为规则与专业能力…',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 2. 模型参数
                          const Text(
                            AppStrings.modelParams,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.brandAction,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 最大执行步数
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(AppStrings.maxExecutionSteps,
                                  style: TextStyle(fontSize: 13)),
                              Text('$steps 步',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Slider(
                            value: steps.toDouble(),
                            min: 1,
                            max: 32,
                            divisions: 31,
                            activeColor: AppPalette.brandAction,
                            onChanged: (val) =>
                                setSheetState(() => steps = val.round()),
                          ),
                          // 温度 Temperature
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(AppStrings.temperature,
                                  style: TextStyle(fontSize: 13)),
                              Text(temperature.toStringAsFixed(2),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Slider(
                            value: temperature,
                            min: 0.0,
                            max: 2.0,
                            divisions: 40,
                            activeColor: AppPalette.brandAction,
                            onChanged: (val) =>
                                setSheetState(() => temperature = val),
                          ),
                          // 最大输出 Token
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(AppStrings.maxOutputTokens,
                                  style: TextStyle(fontSize: 13)),
                              Text('$maxTokens Tokens',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Slider(
                            value: maxTokens.toDouble(),
                            min: 256,
                            max: 8192,
                            divisions: 31,
                            activeColor: AppPalette.brandAction,
                            onChanged: (val) =>
                                setSheetState(() => maxTokens = val.round()),
                          ),
                          // Top P
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(AppStrings.topP,
                                  style: TextStyle(fontSize: 13)),
                              Text(topP.toStringAsFixed(2),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Slider(
                            value: topP,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            activeColor: AppPalette.brandAction,
                            onChanged: (val) => setSheetState(() => topP = val),
                          ),
                          const SizedBox(height: 20),

                          // 3. 工具权限
                          const Text(
                            AppStrings.availableTools,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.brandAction,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...toolOptions.map((tool) {
                            final isChecked =
                                enabled.contains(tool.manifest.name);
                            final isDanger =
                                tool.manifest.risk == ToolRisk.dangerous;
                            final isConfirm = tool.manifest.risk ==
                                ToolRisk.requiresConfirmation;

                            return CheckboxListTile(
                              value: isChecked,
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppPalette.brandAction,
                              title: Row(
                                children: [
                                  Text(
                                    tool.manifest.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isDanger
                                          ? AppPalette.danger
                                              .withValues(alpha: 0.12)
                                          : isConfirm
                                              ? AppPalette.warning
                                                  .withValues(alpha: 0.12)
                                              : (isDark
                                                  ? AppPalette.brandSoftDark
                                                  : AppPalette.brandSoftLight),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isDanger
                                          ? '危险操作'
                                          : isConfirm
                                              ? '需确认'
                                              : '安全',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: isDanger
                                            ? AppPalette.danger
                                            : isConfirm
                                                ? AppPalette.warning
                                                : AppPalette.brandAction,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                tool.manifest.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppPalette.darkTextMuted
                                      : AppPalette.lightTextMuted,
                                ),
                              ),
                              onChanged: (val) {
                                setSheetState(() {
                                  if (val == true) {
                                    enabled.add(tool.manifest.name);
                                  } else {
                                    enabled.remove(tool.manifest.name);
                                  }
                                });
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  // 固定底部操作栏
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurface,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? AppPalette.darkHairline
                              : AppPalette.lightHairline,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  AppTokens.kMinTouchTarget),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text(AppStrings.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  AppTokens.kMinTouchTarget),
                              backgroundColor: AppPalette.brandAction,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              if (nameController.text.trim().isEmpty ||
                                  promptController.text.trim().isEmpty) {
                                return;
                              }
                              Navigator.pop(context, true);
                            },
                            child: const Text(AppStrings.save),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;

    final db = await DatabaseProvider.instance.database;
    final now = DateTime.now();

    if (agent == null) {
      await db.insertAgent(AgentsCompanion.insert(
        id: 'agent-${now.microsecondsSinceEpoch}',
        name: nameController.text.trim(),
        systemPrompt: Value(promptController.text.trim()),
        modelProfileId: 'default',
        maxSteps: Value(steps),
        temperature: Value(temperature),
        maxTokens: Value(maxTokens),
        topP: Value(topP),
        enabledToolsJson: Value(jsonEncode(enabled.toList())),
        updatedAt: now,
      ));
    } else {
      await db.saveAgent(agent.copyWith(
        name: nameController.text.trim(),
        systemPrompt: promptController.text.trim(),
        maxSteps: steps,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        enabledToolsJson: jsonEncode(enabled.toList()),
        updatedAt: now,
      ));
    }

    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: const NexusPageHeader(
        title: AppStrings.agentManagement,
        subtitle: '管理智能体配置与专属工具',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAgentEditor(),
        tooltip: AppStrings.newAgent,
        backgroundColor: AppPalette.brandAction,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.newAgent),
      ),
      body: FutureBuilder<List<Agent>>(
          future: _agents,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final agents = snapshot.data!;
            if (agents.isEmpty) {
              return const EmptyStateView(
                icon: Icons.smart_toy_outlined,
                title: '还没有 Agent',
                message: '点击右下角创建一个 Agent',
              );
            }
            return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: agents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final agent = agents[index];
                  return SectionCard(
                      child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppPalette.brandSoftDark
                                  : AppPalette.brandSoftLight,
                              borderRadius: BorderRadius.circular(
                                  AppTokens.radiusControl),
                            ),
                            child: const Icon(Icons.smart_toy_outlined,
                                size: 20, color: AppPalette.brand),
                          ),
                          title: Text(
                            agent.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            agent.systemPrompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppPalette.darkTextMuted
                                  : AppPalette.lightTextMuted,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: AppStrings.editAgent,
                            constraints: const BoxConstraints(
                              minWidth: AppTokens.kMinTouchTarget,
                              minHeight: AppTokens.kMinTouchTarget,
                            ),
                            onPressed: () => _openAgentEditor(agent),
                          ),
                          onTap: () => _openAgentEditor(agent)));
                });
          }),
    );
  }
}
