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
import '../widgets/empty_state_view.dart';
import '../widgets/immersive_sheet.dart';
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

  Future<void> _createAgent() async {
    final name = TextEditingController(text: '通用助手');
    final prompt = TextEditingController(text: '你是一个有帮助的 AI Agent。');
    final result = await showImmersiveDialog<(String, String)>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('创建 Agent'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '名称')),
                  TextField(
                      controller: prompt,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '系统提示词'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, (name.text, prompt.text)),
                      child: const Text('创建'))
                ]));
    name.dispose();
    prompt.dispose();
    if (result == null || result.$1.trim().isEmpty) return;
    final now = DateTime.now();
    final db = await DatabaseProvider.instance.database;
    await db.insertAgent(AgentsCompanion.insert(
        id: 'agent-${now.microsecondsSinceEpoch}',
        name: result.$1.trim(),
        systemPrompt: Value(result.$2.trim()),
        modelProfileId: 'default',
        enabledToolsJson: const Value('["calculator","get_time","json_query"]'),
        updatedAt: now));
    if (mounted) setState(_reload);
  }

  Future<void> _editAgent(Agent agent) async {
    final name = TextEditingController(text: agent.name);
    final prompt = TextEditingController(text: agent.systemPrompt);
    final steps = TextEditingController(text: '${agent.maxSteps}');
    final temperature = TextEditingController(text: '${agent.temperature}');
    final maxTokens = TextEditingController(text: '${agent.maxTokens}');
    final topP = TextEditingController(text: '${agent.topP}');
    final parsed =
        (jsonDecode(agent.enabledToolsJson) as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet();
    final enabled = parsed.isEmpty
        ? <String>{'calculator', 'get_time', 'json_query'}
        : {...parsed};
    final result = await showImmersiveDialog<
        (String, String, int, double, int, double, Set<String>)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑 Agent'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '名称')),
                TextField(
                    controller: prompt,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '系统提示词')),
                TextField(
                    controller: steps,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: AppStrings.maxExecutionSteps)),
                const SizedBox(height: 12),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(AppStrings.modelParams,
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: temperature,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: AppStrings.temperature))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: topP,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: AppStrings.topP))),
                ]),
                const SizedBox(height: 8),
                TextField(
                    controller: maxTokens,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: AppStrings.maxOutputTokens)),
                const SizedBox(height: 12),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(AppStrings.availableTools,
                        style: TextStyle(fontWeight: FontWeight.w600))),
                ..._toolOptions.map((tool) => CheckboxListTile(
                      value: enabled.contains(tool.manifest.name),
                      onChanged: (value) => setDialogState(() => value == true
                          ? enabled.add(tool.manifest.name)
                          : enabled.remove(tool.manifest.name)),
                      title: Text(tool.manifest.name),
                      subtitle: Text(tool.manifest.risk == ToolRisk.dangerous
                          ? AppStrings.dangerToolHint
                          : tool.manifest.risk == ToolRisk.requiresConfirmation
                              ? AppStrings.confirmToolHint
                              : AppStrings.safeTool),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    )),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (
                  name.text,
                  prompt.text,
                  int.tryParse(steps.text) ?? 8,
                  double.tryParse(temperature.text) ?? 0.7,
                  int.tryParse(maxTokens.text) ?? 2048,
                  double.tryParse(topP.text) ?? 1.0,
                  {...enabled},
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    prompt.dispose();
    steps.dispose();
    temperature.dispose();
    maxTokens.dispose();
    topP.dispose();
    if (result == null) return;
    final db = await DatabaseProvider.instance.database;
    await db.saveAgent(agent.copyWith(
      name: result.$1.trim(),
      systemPrompt: result.$2.trim(),
      maxSteps: result.$3.clamp(1, 32).toInt(),
      temperature: result.$4.clamp(0.0, 2.0),
      maxTokens: result.$5.clamp(1, 128000).toInt(),
      topP: result.$6.clamp(0.0, 1.0),
      enabledToolsJson: jsonEncode(result.$7.toList()),
      updatedAt: DateTime.now(),
    ));
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent 管理')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _createAgent,
          icon: const Icon(Icons.add),
          label: const Text('新建 Agent')),
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
                          leading: const CircleAvatar(
                              child: Icon(Icons.smart_toy_outlined)),
                          title: Text(agent.name),
                          subtitle: Text(agent.systemPrompt,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editAgent(agent)),
                          onTap: () => _editAgent(agent)));
                });
          }),
    );
  }
}
