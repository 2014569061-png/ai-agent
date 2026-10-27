import '../theme/mobile_theme.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_resource_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent_draft_service.dart';
import '../../application/agent_tool_catalog.dart';
import '../../application/providers.dart';
import '../../domain/agent_draft.dart';
import '../../infrastructure/database/app_database.dart';
import '../../application/mojibake_repair.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../motion/nexus_page_route_factory.dart';
import '../motion/nexus_motion.dart';
import '../motion/nexus_staggered_entrance.dart';
import 'agent_editor_page.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/section_card.dart';
import '../../application/local_error_copy.dart';

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
      final agents = await db.allAgents(limit: 200);
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
      // 这里给的是裸内容（没有 AlertDialog 的卡片外壳），
      // 需要 showNexusDialog 补上玻璃卡片背景。
      selfContained: false,
      builder: (_) => const _DescribeGoalDialog(),
    );
    if (draft == null || !mounted) return;
    await _openAgentEditor(draft: draft);
  }

  Future<void> _chooseCreation() async {
    final choice = await showNexusSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('描述目标，生成草稿'),
            subtitle: const Text('生成后核对角色与工具权限，再保存'),
            onTap: () => Navigator.pop(context, 'describe'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('手动配置'),
            onTap: () => Navigator.pop(context, 'manual'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'describe') {
      await _createFromDescription();
    } else {
      await _openAgentEditor();
    }
  }

  Widget _desktopAgents() => FutureBuilder<List<Agent>>(
      future: _agents,
      builder: (context, snapshot) => DesktopResourceView<Agent>(
            title: 'Agent 管理',
            icon: Icons.smart_toy_outlined,
            description: '将角色、指令与工具范围组织成可复用的 Agent。生成草稿后仍需确认保存。',
            items: snapshot.data ?? const [],
            loading: snapshot.connectionState != ConnectionState.done,
            error: snapshot.error,
            onReload: () => setState(_reload),
            searchHint: '搜索 Agent 名称或系统指令',
            searchText: (agent) => '${agent.name} ${agent.systemPrompt}',
            sorts: [
              DesktopResourceSort(
                  '名称 A–Z',
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase())),
              DesktopResourceSort(
                  '执行步数：少到多', (a, b) => a.maxSteps.compareTo(b.maxSteps))
            ],
            actions: [
              FilledButton.icon(
                  onPressed: _createFromDescription,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('描述目标，生成草稿')),
              OutlinedButton.icon(
                  onPressed: () => _openAgentEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('手动创建 Agent')),
            ],
            emptyTitle: '建立你的第一个 Agent',
            emptyMessage: '从描述目标开始，或手动定义角色、参数与工具范围。',
            itemBuilder: (context, agent) => DesktopResourceCard(
              key: ValueKey('desktop-agent-${agent.id}'),
              title: agent.name,
              icon: Icons.smart_toy_outlined,
              description: agent.systemPrompt,
              metadata: [
                '最多 ${agent.maxSteps} 步',
                '温度 ${agent.temperature}',
                '工具权限在编辑器中管理'
              ],
              onTap: () => _openAgentEditor(agent: agent),
              actions: [
                OutlinedButton.icon(
                    onPressed: () => _openAgentEditor(agent: agent),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('编辑角色与权限'))
              ],
            ),
          ));

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopAgents();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: const NexusPageHeader(
        title: AppStrings.agentManagement,
        subtitle: '管理智能体配置与专属工具',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseCreation,
        tooltip: '创建 Agent',
        icon: const Icon(Icons.add_rounded),
        label: const Text('创建 Agent'),
      ),
      body: NexusPageLayout(
          child: FutureBuilder<List<Agent>>(
              future: _agents,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyStateView(
                      icon: Icons.error_outline,
                      title: 'Agent 读取失败',
                      actionLabel: '重试',
                      onAction: () => setState(_reload));
                }
                if (!snapshot.hasData) {
                  return const NexusCardSkeleton(count: 3);
                }
                final agents = snapshot.data!;
                if (agents.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.smart_toy_outlined,
                    title: '还没有 Agent',
                    message: '说一句你要它做什么，AI 会生成角色、指令与工具范围，你确认后即可用',
                  );
                }
                return NexusStaggeredEntrance(
                    child: ListView.separated(
                        physics: NexusMotion.listPhysics,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        // 创建方式统一收纳在添加面板。
                        itemCount: agents.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppTokens.sp3),
                        itemBuilder: NexusStaggeredItem.wrap((context, index) {
                          final agent = agents[index];
                          return SectionCard(
                              glass: false,
                              child: ListTile(
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppPalette.brandSoftDark
                                          : AppPalette.brandSoftLight,
                                      borderRadius: BorderRadius.circular(
                                          MobileTheme.controlRadius(context)),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.12)
                                            : MobileTheme.brand(context)
                                                .withValues(alpha: 0.15),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Icon(Icons.smart_toy_outlined,
                                        size: 20,
                                        color: MobileTheme.brand(context)),
                                  ),
                                  title: Text(
                                    agent.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: AppTokens.fontSizeBody,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        agent.systemPrompt,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: AppTokens.fontSizeCaption,
                                          color: isDark
                                              ? AppPalette.darkTextMuted
                                              : AppPalette.lightTextMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '最大 ${agent.maxSteps} 步 · 温度 ${agent.temperature}',
                                        style: TextStyle(
                                          fontSize: AppTokens.fontSizeBadge,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                          color: isDark
                                              ? AppPalette.darkTextFaint
                                              : AppPalette.lightTextMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: AppStrings.editAgent,
                                    constraints: const BoxConstraints(
                                      minWidth: AppTokens.kMinTouchTarget,
                                      minHeight: AppTokens.kMinTouchTarget,
                                    ),
                                    onPressed: () =>
                                        _openAgentEditor(agent: agent),
                                  ),
                                  onTap: () => _openAgentEditor(agent: agent)));
                        })));
              })),
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
        _error = LocalErrorCopy.of(error, action: '生成').headline();
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
                fontSize: AppTokens.fontSizeBody,
                fontWeight: FontWeight.w500,
                color: textColor),
          ),
          const SizedBox(height: 6),
          Text(
            '例如：帮我审代码，重点看空指针和边界条件',
            style: TextStyle(
                fontSize: AppTokens.fontSizeFootnote, color: textMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autofocus: true,
            maxLines: 3,
            minLines: 3,
            style: TextStyle(
                fontSize: AppTokens.fontSizeSubhead,
                height: 1.4,
                color: textColor),
            decoration: InputDecoration(
              hintText: '你希望它替你做的那件事…',
              hintStyle: TextStyle(
                  fontSize: AppTokens.fontSizeCaption, color: textMuted),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(MobileTheme.controlRadius(context)),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    color: AppPalette.danger)),
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
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
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
                    backgroundColor: MobileTheme.brand(context),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
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
                              fontSize: AppTokens.fontSizeSubhead,
                              fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '生成结果只作为编辑器的预填内容，不会自动保存，也不会授予任何权限。',
            style: TextStyle(
                fontSize: AppTokens.fontSizeSubcaption, color: textMuted),
          ),
        ],
      ),
    );
  }
}
