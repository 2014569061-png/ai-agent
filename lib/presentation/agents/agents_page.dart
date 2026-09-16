import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent_draft_service.dart';
import '../../application/agent_tool_catalog.dart';
import '../../application/providers.dart';
import '../../domain/agent_draft.dart';
import '../../infrastructure/database/app_database.dart';
import '../../application/mojibake_repair.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../motion/nexus_page_route_factory.dart';
import 'agent_editor_page.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/section_card.dart';

class AgentsPage extends ConsumerStatefulWidget {
  const AgentsPage({super.key, this.autoDescribe = false});

  /// 由系统级入口（应用快捷方式 / `nexus://new-agent` 深链）进入时置为 true，
  /// 进入页面即弹出「描述目标」输入框——快捷方式的意义就是少一次点击，
  /// 落到列表页还要用户再找入口就等于没做。
  final bool autoDescribe;

  @override
  ConsumerState<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends ConsumerState<AgentsPage> {
  late Future<List<Agent>> _agents;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.autoDescribe) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _createFromDescription();
      });
    }
  }

  /// 走 [databaseProvider] 而不是全局单例：这是项目在 `providers.dart` 里写明的
  /// 注入点，测试可以 override 成内存库，页面才进得了冒烟守护。
  void _reload() {
    _agents = ref.read(databaseProvider.future).then((db) async {
      final agents = await db.allAgents();
      return agents
          .map((agent) =>
              agent.copyWith(name: MojibakeRepair.repair(agent.name)))
          .toList();
    });
  }

  Future<void> _openAgentEditor({Agent? agent, AgentDraft? draft}) async {
    final changed = await Navigator.of(context).push<bool>(
      NexusPageRoute.detail(
        builder: (_) => AgentEditorPage(agent: agent, draft: draft),
      ),
    );
    if (changed == true && mounted) {
      setState(_reload);
    }
  }

  /// 「说目标 → 生成 Agent 草稿」入口。
  ///
  /// 生成结果只作为编辑器的预填内容：本方法不写库、不授权，用户必须先在编辑器里
  /// 确认并保存。生成的权限范围默认只含安全级工具，其余在编辑器里由用户决定。
  Future<void> _createFromDescription() async {
    final draft = await showNexusDialog<AgentDraft>(
      context: context,
      builder: (_) => const _DescribeGoalDialog(),
    );
    if (draft == null || !mounted) return;
    await _openAgentEditor(draft: draft);
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
              return const NexusCardSkeleton(count: 3);
            }
            final agents = snapshot.data!;
            if (agents.isEmpty) {
              return EmptyStateView(
                icon: Icons.smart_toy_outlined,
                title: '还没有 Agent',
                message: '说一句你要它做什么，AI 会生成角色、指令与工具范围，你确认后即可用',
                actionLabel: '描述目标，让 AI 生成',
                onAction: _createFromDescription,
              );
            }
            return ListView.separated(
                padding: const EdgeInsets.all(16),
                // 首项是「描述生成」入口，其余是已有 Agent。
                itemCount: agents.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _DescribeEntryCard(onTap: _createFromDescription);
                  }
                  final agent = agents[index - 1];
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
                            onPressed: () => _openAgentEditor(agent: agent),
                          ),
                          onTap: () => _openAgentEditor(agent: agent)));
                });
          }),
    );
  }
}

/// 「描述生成」入口卡片。
///
/// 放在已有 Agent 列表之前，因为它才是这个页面的默认动作——手填表单应当是备选，
/// 而不是让用户自己想清楚角色、系统指令与工具白名单。
class _DescribeEntryCard extends StatelessWidget {
  const _DescribeEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return SectionCard(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? AppPalette.brandSoftDark : AppPalette.brandSoftLight,
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: const Icon(Icons.auto_awesome_outlined,
              size: 20, color: AppPalette.brand),
        ),
        title: const Text(
          '用一句话描述，让 AI 生成',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
        subtitle: Text(
          '生成角色、系统指令与工具范围，你确认后再保存',
          style: TextStyle(fontSize: 13, color: textMuted),
        ),
      ),
    );
  }
}

/// 收集一句目标，产出待确认的 Agent 草稿。
///
/// 弹窗只负责「拿到目标 + 调生成」，任何写库和授权都在编辑器里由用户触发；
/// 失败时保持弹窗打开，避免用户刚写的内容被清掉。
class _DescribeGoalDialog extends ConsumerStatefulWidget {
  const _DescribeGoalDialog();

  @override
  ConsumerState<_DescribeGoalDialog> createState() =>
      _DescribeGoalDialogState();
}

class _DescribeGoalDialogState extends ConsumerState<_DescribeGoalDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final goal = _controller.text.trim();
    if (goal.isEmpty) {
      setState(() => _error = '先写一句你要它做什么');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    AgentDraft draft;
    try {
      final config = await ProviderConfigStore().load();
      final specs = toToolSpecs(await loadAvailableAgentTools(
          database: ref.read(databaseProvider.future)));
      draft = await const AgentDraftService()
          .generate(config: config, goal: goal, tools: specs);
    } catch (error) {
      // 生成服务内部已会退化成本地草稿；这里只兜住配置读取一类的极端异常，
      // 并保持弹窗打开让用户直接重试。
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '生成失败：$error';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '用一句话描述这个智能体',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500, color: textColor),
          ),
          const SizedBox(height: 6),
          Text(
            '例如：帮我审代码，重点看空指针和边界条件',
            style: TextStyle(fontSize: 12, color: textMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autofocus: true,
            maxLines: 3,
            minLines: 3,
            style: TextStyle(fontSize: 14, height: 1.4, color: textColor),
            decoration: InputDecoration(
              hintText: '你希望它替你做的那件事…',
              hintStyle: TextStyle(fontSize: 13, color: textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: AppPalette.danger)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize:
                        const Size.fromHeight(AppTokens.kControlHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                    ),
                  ),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text(AppStrings.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize:
                        const Size.fromHeight(AppTokens.kControlHeight),
                    backgroundColor: AppPalette.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                    ),
                  ),
                  onPressed: _busy ? null : _generate,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('生成草稿',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '生成结果只作为编辑器的预填内容，不会自动保存，也不会授予任何权限。',
            style: TextStyle(fontSize: 11.5, color: textMuted),
          ),
        ],
      ),
    );
  }
}
