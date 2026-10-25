import '../widgets/nexus_disclosure.dart';
import '../theme/mobile_theme.dart';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../theme/desktop_theme.dart';
import '../widgets/desktop_editor_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/agent_loop/output_token_policy.dart';
import '../../application/agent_tool_catalog.dart';
import '../../application/mojibake_repair.dart';
import '../../application/providers.dart';
import '../../domain/agent_draft.dart';
import '../../domain/models.dart';
import '../../domain/unique_id.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/tools/tool_registry.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_undo_toast.dart';
import '../widgets/section_card.dart';

/// 沉浸式全屏智能体编辑器 (Agent Editor Page)
/// 彻底替代 85% 模态底栏方案，解决键盘遮挡、误触丢失与工具列表过长等交互缺陷。
class AgentEditorPage extends ConsumerStatefulWidget {
  const AgentEditorPage({super.key, this.agent, this.draft});

  final Agent? agent;

  /// 「对话式创建 Agent」产出的待确认草稿。仅用于新建时的预填，
  /// 它不落库、不授予任何权限；写库仍由本页的保存动作完成。
  final AgentDraft? draft;

  @override
  ConsumerState<AgentEditorPage> createState() => _AgentEditorPageState();
}

class _AgentEditorPageState extends ConsumerState<AgentEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;

  late int _steps;
  late double _temperature;
  late int _maxTokens;

  /// 开启时保存 [OutputTokenPolicy.legacyDefault]，运行时按模型自动决定上限。
  late bool _autoMaxTokens;

  /// 当前生效服务商的模型与上下文窗口，用于显示自动上限的实际数值。
  String? _activeModel;
  int _activeContextTokens = 0;
  late double _topP;

  late Set<String> _enabledTools;
  bool _loadingTools = true;
  List<AgentTool> _availableTools = const [];
  String _toolQuery = "";

  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    final draft = widget.draft;
    _nameController = TextEditingController(
      text: a != null ? MojibakeRepair.repair(a.name) : (draft?.name ?? ''),
    )..addListener(_markDirty);

    _promptController = TextEditingController(
      text: a?.systemPrompt ?? draft?.systemPrompt ?? '你是一个智能、严谨且富有创造力的 AI 助手。',
    )..addListener(_markDirty);

    _steps = (a?.maxSteps ?? draft?.maxSteps ?? AgentDraft.defaultMaxSteps)
        .clamp(1, 100);
    _temperature =
        (a?.temperature ?? draft?.temperature ?? 0.7).clamp(0.0, 2.0);
    final storedMaxTokens =
        a?.maxTokens ?? draft?.maxTokens ?? OutputTokenPolicy.legacyDefault;
    _autoMaxTokens = storedMaxTokens == OutputTokenPolicy.legacyDefault;
    _maxTokens = _autoMaxTokens
        ? OutputTokenPolicy.standardDefault
        : storedMaxTokens.clamp(256, _maxTokenSteps.last).toInt();
    _topP = (a?.topP ?? draft?.topP ?? 1.0).clamp(0.0, 1.0);

    if (a == null) {
      // 有草稿就按草稿的授权范围预填（可能是空的，这也是一个合法的生成结果）；
      // 没有草稿的新建才给起步默认值。
      _enabledTools = draft != null
          ? {...draft.grantedTools}
          : {'calculator', 'get_time', 'json_query'};
    } else {
      // An explicitly empty list is a valid permission choice.  Only new
      // agents receive the starter defaults; opening an existing agent must
      // never silently grant tools or turn a malformed record into a crash.
      try {
        final decoded = jsonDecode(a.enabledToolsJson);
        _enabledTools =
            decoded is List ? decoded.whereType<String>().toSet() : <String>{};
      } catch (_) {
        _enabledTools = <String>{};
      }
    }

    // 带草稿进入时视为「未保存的修改」：直接返回会丢掉生成结果，
    // 应当和后端返回键一样先确认。
    _isDirty = draft != null;

    _loadTools();
    _loadActiveModel();
  }

  Future<void> _loadActiveModel() async {
    try {
      final config = await ref.read(providerConfigStoreProvider).load();
      if (!mounted || !config.isConfigured) return;
      setState(() {
        _activeModel = config.model;
        _activeContextTokens = config.effectiveContextTokens;
      });
    } catch (_) {
      // 读不到服务商配置时只显示通用规则，不影响编辑。
    }
  }

  int get _savedMaxTokens =>
      _autoMaxTokens ? OutputTokenPolicy.legacyDefault : _maxTokens;

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  Future<void> _loadTools() async {
    final tools = await loadAvailableAgentTools(
        database: ref.read(databaseProvider.future));

    if (mounted) {
      setState(() {
        _availableTools = tools;
        _loadingTools = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final discard = await showConfirmAction(
      context,
      title: '放弃未保存的修改？',
      message: '当前编辑的智能体信息尚未保存，确定退出吗？',
      confirmLabel: '放弃修改',
      isDanger: true,
    );
    return discard;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();

    if (name.isEmpty) {
      FloatingToast.show(context, '请输入智能体名称', tone: ToastTone.danger);
      return;
    }
    if (prompt.isEmpty) {
      FloatingToast.show(context, '请输入系统提示词', tone: ToastTone.danger);
      return;
    }

    setState(() => _isSaving = true);
    unawaited(HapticFeedback.mediumImpact());

    try {
      final db = await ref.read(databaseProvider.future);
      final now = DateTime.now();

      if (widget.agent == null) {
        await db.insertAgent(AgentsCompanion.insert(
          id: UniqueId.generate('agent', now: now),
          name: name,
          systemPrompt: Value(prompt),
          modelProfileId: 'default',
          maxSteps: Value(_steps),
          temperature: Value(_temperature),
          maxTokens: Value(_savedMaxTokens),
          topP: Value(_topP),
          enabledToolsJson: Value(jsonEncode(_enabledTools.toList())),
          updatedAt: now,
        ));
      } else {
        await db.saveAgent(widget.agent!.copyWith(
          name: name,
          systemPrompt: prompt,
          maxSteps: _steps,
          temperature: _temperature,
          maxTokens: _savedMaxTokens,
          topP: _topP,
          enabledToolsJson: jsonEncode(_enabledTools.toList()),
          updatedAt: now,
        ));
      }

      if (!mounted) return;
      FloatingToast.show(
        context,
        widget.agent == null ? '已创建智能体 “$name”' : '已保存智能体 “$name”',
        tone: ToastTone.success,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      FloatingToast.show(context, '保存失败: $e', tone: ToastTone.danger);
    }
  }

  Future<void> _delete() async {
    final agent = widget.agent;
    if (agent == null) return;

    final confirmed = await showConfirmAction(
      context,
      title: '删除智能体',
      message: '确定要删除 “${agent.name}” 吗？此操作无法撤销。',
      confirmLabel: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) return;

    final db = await ref.read(databaseProvider.future);
    await db.deleteAgent(agent.id);
    if (!mounted) return;

    NexusUndoToast.show(
      context,
      message: '已删除 Agent “${agent.name}”',
      onUndo: () async {
        final dbInstance = await ref.read(databaseProvider.future);
        await dbInstance.saveAgent(agent);
      },
    );
    Navigator.of(context).pop(true);
  }

  Widget _advancedParameters(Widget fields) {
    if (DesktopTheme.maybeOf(context) != null) return fields;
    return NexusDisclosure(
      key: const ValueKey('agent-advanced-parameters'),
      leading: const Icon(Icons.tune_rounded, size: 20),
      headerPadding: const EdgeInsets.all(16),
      contentPadding: EdgeInsets.zero,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('高级执行参数', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 4),
        Text('最多 $_steps 步 · 输出${_autoMaxTokens ? "自动" : " $_maxTokens Token"}',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      child: fields,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desktop = DesktopTheme.maybeOf(context);
    final hairline = desktop?.border ??
        (isDark ? AppPalette.darkHairline : AppPalette.lightHairline);
    final surface = desktop?.panel ??
        (isDark ? AppPalette.darkSurface : AppPalette.lightSurface);
    final textColor =
        desktop?.text ?? (isDark ? AppPalette.darkText : AppPalette.lightText);
    final textMuted = desktop?.muted ??
        (isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted);

    final visibleTools = _availableTools
        .where((tool) => '${tool.manifest.name} ${tool.manifest.description}'
            .toLowerCase()
            .contains(_toolQuery.toLowerCase()))
        .toList();
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: MobileTheme.pageBackground(context),
        appBar: NexusPageHeader(
          title: widget.agent == null ? '新建智能体' : '编辑智能体',
          subtitle: widget.agent == null ? '定制专属角色的系统指令与能力' : '调整配置与工具箱授权',
          onBack: () async {
            final shouldPop = await _onWillPop();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          actions: [
            if (widget.agent != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppPalette.danger),
                tooltip: '删除智能体',
                onPressed: _delete,
              ),
          ],
        ),
        body: NexusPageLayout(
            child: DesktopEditorLayout(
                title: 'Agent 配置摘要',
                icon: Icons.smart_toy_outlined,
                status: _isSaving
                    ? '正在保存…'
                    : _isDirty
                        ? '有尚未保存的更改'
                        : widget.agent == null
                            ? '新 Agent · 尚未保存'
                            : '配置未修改',
                facts: [
                  (label: '最大执行步数', value: '$_steps 步'),
                  (
                    label: '输出 Token',
                    value: _autoMaxTokens ? '自动匹配模型' : '$_maxTokens'
                  ),
                  (
                    label: '工具选择',
                    value: _loadingTools
                        ? '正在读取工具…'
                        : '${_enabledTools.length} 项已选择'
                  ),
                ],
                notes: const [
                  '工具勾选决定可用范围，不会绕过运行时的风险审批。',
                  '生成的角色草稿必须确认保存后才会成为可用 Agent。',
                  '删除和放弃修改仍需要明确确认。'
                ],
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    if (widget.draft != null) ...[
                      _DraftNotice(draft: widget.draft!),
                      const SizedBox(height: 20),
                    ],
                    // 1. 基础信息卡片
                    const _SectionTitle(
                        title: '基本设定', icon: Icons.badge_outlined),
                    SectionCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _nameController,
                              style: TextStyle(
                                  fontSize: AppTokens.fontSizeBody,
                                  color: textColor),
                              decoration: InputDecoration(
                                labelText: '智能体名称 *',
                                labelStyle: TextStyle(
                                    fontSize: AppTokens.fontSizeCaption,
                                    color: textMuted),
                                hintText: '如：代码审计专家、架构顾问、翻译助手',
                                hintStyle: TextStyle(
                                    fontSize: AppTokens.fontSizeSubhead,
                                    color: textMuted),
                                prefixIcon: const Icon(Icons.smart_toy_outlined,
                                    size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      MobileTheme.controlRadius(context)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _promptController,
                              maxLines: 5,
                              minLines: 3,
                              style: TextStyle(
                                  fontSize: AppTokens.fontSizeSubhead,
                                  height: 1.4,
                                  color: textColor),
                              decoration: InputDecoration(
                                labelText: '系统提示词 (System Prompt) *',
                                labelStyle: TextStyle(
                                    fontSize: AppTokens.fontSizeCaption,
                                    color: textMuted),
                                hintText: '明确描述该 Agent 的角色人设、专业领域、工作流规范与输出限制…',
                                hintStyle: TextStyle(
                                    fontSize: AppTokens.fontSizeCaption,
                                    color: textMuted),
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      MobileTheme.controlRadius(context)),
                                ),
                                contentPadding: const EdgeInsets.all(14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 2. 模型与调优参数
                    if (DesktopTheme.maybeOf(context) != null)
                      const _SectionTitle(
                          title: '模型与推理参数', icon: Icons.tune_rounded),
                    SectionCard(
                      child: _advancedParameters(Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ParamSlider(
                              label: '最大思考执行步数',
                              valueText: '$_steps 步',
                              description: 'Agent 自主循环规划与调用工具的最大上限',
                              value: _steps.toDouble(),
                              min: 1,
                              max: 100,
                              divisions: 99,
                              onChanged: (val) {
                                _markDirty();
                                setState(() => _steps = val.round());
                              },
                            ),
                            const Divider(height: 24),
                            _ParamSlider(
                              label: '发散度 (Temperature)',
                              valueText: _temperature.toStringAsFixed(2),
                              description: '较低值更具确定性与严谨，较高值更具创造力',
                              value: _temperature,
                              min: 0.0,
                              max: 2.0,
                              divisions: 40,
                              onChanged: (val) {
                                _markDirty();
                                setState(() => _temperature = val);
                              },
                            ),
                            const Divider(height: 24),
                            SwitchListTile.adaptive(
                              key: const ValueKey('agent-max-tokens-auto'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '单次最大输出：自动（推荐）',
                                style: TextStyle(
                                  fontSize: AppTokens.fontSizeBodySmall,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                agentMaxTokensSubtitle(
                                  auto: _autoMaxTokens,
                                  manualTokens: _maxTokens,
                                  activeModel: _activeModel,
                                  activeContextTokens: _activeContextTokens,
                                ),
                                style: const TextStyle(
                                    fontSize: AppTokens.fontSizeFootnote),
                              ),
                              value: _autoMaxTokens,
                              onChanged: (value) {
                                _markDirty();
                                setState(() => _autoMaxTokens = value);
                              },
                            ),
                            if (!_autoMaxTokens)
                              _ParamSlider(
                                label: '单次最大输出 (Max Tokens)',
                                valueText: '$_maxTokens Tokens',
                                description: '推理模型的上限同时包含思考与正文，过小会导致回答被截断',
                                value:
                                    _maxTokenStepIndex(_maxTokens).toDouble(),
                                min: 0,
                                max: (_maxTokenSteps.length - 1).toDouble(),
                                divisions: _maxTokenSteps.length - 1,
                                onChanged: (val) {
                                  _markDirty();
                                  setState(() =>
                                      _maxTokens = _maxTokenSteps[val.round()]);
                                },
                              ),
                            const Divider(height: 24),
                            _ParamSlider(
                              label: '核采样阈值 (Top P)',
                              valueText: _topP.toStringAsFixed(2),
                              description: '与 Temperature 共同控制文本采样的候选词概率质量',
                              value: _topP,
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              onChanged: (val) {
                                _markDirty();
                                setState(() => _topP = val);
                              },
                            ),
                          ],
                        ),
                      )),
                    ),
                    const SizedBox(height: 20),

                    // 3. 工具箱授权
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionTitle(
                            title: '可用工具箱授权', icon: Icons.handyman_outlined),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            _markDirty();
                            setState(() {
                              _enabledTools = {
                                'calculator',
                                'get_time',
                                'json_query',
                                'http_request',
                                'web_search',
                              };
                            });
                          },
                          child: const Text('推荐预设',
                              style: TextStyle(
                                  fontSize: AppTokens.fontSizeFootnote)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        decoration: const InputDecoration(
                            hintText: '搜索工具名称或用途',
                            prefixIcon: Icon(Icons.search_rounded)),
                        onChanged: (value) =>
                            setState(() => _toolQuery = value),
                      ),
                    ),
                    SectionCard(
                      child: _loadingTools
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: NexusListSkeleton(itemCount: 3),
                            )
                          : _availableTools.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Center(
                                    child: Text(
                                      '未检测到已注册工具',
                                      style: TextStyle(
                                          fontSize: AppTokens.fontSizeCaption,
                                          color: textMuted),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: visibleTools.length,
                                  separatorBuilder: (_, __) =>
                                      Divider(height: 1, color: hairline),
                                  itemBuilder: (context, index) {
                                    final tool = visibleTools[index];
                                    final isChecked = _enabledTools
                                        .contains(tool.manifest.name);
                                    final isDanger = tool.manifest.risk ==
                                        ToolRisk.dangerous;
                                    final isConfirm = tool.manifest.risk ==
                                        ToolRisk.requiresConfirmation;

                                    return CheckboxListTile(
                                      value: isChecked,
                                      activeColor: MobileTheme.brand(context),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 4),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tool.manifest.name,
                                              style: TextStyle(
                                                fontSize:
                                                    AppTokens.fontSizeSubhead,
                                                fontFamily:
                                                    AppTokens.fontFamilyMono,
                                                fontWeight: FontWeight.w600,
                                                color: textColor,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isDanger
                                                  ? AppPalette.danger
                                                      .withAlpha(25)
                                                  : isConfirm
                                                      ? AppPalette.warning
                                                          .withAlpha(25)
                                                      : MobileTheme.brand(
                                                              context)
                                                          .withAlpha(25),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isDanger
                                                  ? '危险操作'
                                                  : isConfirm
                                                      ? '需确认'
                                                      : '安全',
                                              style: TextStyle(
                                                fontSize: AppTokens
                                                    .fontSizeMetricSmall,
                                                fontWeight: FontWeight.w500,
                                                color: isDanger
                                                    ? AppPalette.danger
                                                    : isConfirm
                                                        ? AppPalette.warning
                                                        : MobileTheme.brand(
                                                            context),
                                              ),
                                            ),
                                          ),
                                          if (widget.draft?.pendingTools
                                                  .contains(
                                                      tool.manifest.name) ==
                                              true) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color:
                                                    MobileTheme.brand(context)
                                                        .withAlpha(25),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'AI 建议',
                                                style: TextStyle(
                                                  fontSize: AppTokens
                                                      .fontSizeMetricSmall,
                                                  fontWeight: FontWeight.w500,
                                                  color: MobileTheme.brand(
                                                      context),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          tool.manifest.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize:
                                                  AppTokens.fontSizeFootnote,
                                              color: textMuted),
                                        ),
                                      ),
                                      onChanged: (val) {
                                        _markDirty();
                                        setState(() {
                                          if (val == true) {
                                            _enabledTools
                                                .add(tool.manifest.name);
                                          } else {
                                            _enabledTools
                                                .remove(tool.manifest.name);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ))),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: surface,
            border: Border(top: BorderSide(color: hairline, width: 1.0)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
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
                    onPressed: () async {
                      final shouldPop = await _onWillPop();
                      if (shouldPop && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text(AppStrings.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(AppTokens.kControlHeight),
                      backgroundColor:
                          desktop?.accent ?? MobileTheme.brand(context),
                      foregroundColor: desktop != null
                          ? Theme.of(context).colorScheme.onPrimary
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            MobileTheme.controlRadius(context)),
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存智能体',
                            style: TextStyle(
                                fontSize: AppTokens.fontSizeSubhead,
                                fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppPalette.brandTextFor(isDark)),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: AppTokens.fontSizeCaption,
              fontWeight: FontWeight.w600,
              color: textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Agent 编辑页“单次最大输出”开关下的说明：自动时给出当前服务商模型的
/// 实际生效值，手动且为推理模型时提示过小的风险。
@visibleForTesting
String agentMaxTokensSubtitle({
  required bool auto,
  required int manualTokens,
  String? activeModel,
  int activeContextTokens = 0,
}) {
  final model = activeModel?.trim();
  final hasModel = model != null && model.isNotEmpty;
  final reasoning = hasModel && OutputTokenPolicy.isReasoningModel(model);
  if (auto) {
    const rule = '推理模型 ${OutputTokenPolicy.reasoningDefault}、其他模型 '
        '${OutputTokenPolicy.standardDefault} Tokens，且不超过上下文窗口的一半';
    if (!hasModel) return rule;
    final effective = OutputTokenPolicy.resolve(
      model: model,
      configured: OutputTokenPolicy.legacyDefault,
      contextWindow: activeContextTokens,
    );
    return '当前 $model（${reasoning ? '推理模型' : '普通模型'}）：$effective Tokens\n$rule';
  }
  if (reasoning && manualTokens < 8192) {
    return '已关闭：使用下方的固定上限。当前 $model 是推理模型，上限同时包含'
        '思考过程，过小容易被截断';
  }
  return '已关闭：使用下方的固定上限';
}

/// 手动输出上限的可选刻度。刻意不含 2048：它是“自动”的存储值
/// （[OutputTokenPolicy.legacyDefault]），手动选中会与自动混淆。
const _maxTokenSteps = <int>[
  256, 512, 1024, 1536, 2560, 3072, 4096, 6144, 8192, 12288, 16384, 24576, //
  32768,
];

int _maxTokenStepIndex(int value) {
  var best = 0;
  for (var i = 1; i < _maxTokenSteps.length; i++) {
    if ((_maxTokenSteps[i] - value).abs() <
        (_maxTokenSteps[best] - value).abs()) {
      best = i;
    }
  }
  return best;
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.valueText,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTokens.fontSizeBodySmall,
                      fontWeight: FontWeight.w500,
                      color: textColor)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MobileTheme.pageBackground(context),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark
                      ? AppPalette.darkHairline
                      : AppPalette.lightHairline,
                ),
              ),
              child: Text(
                valueText,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  fontWeight: FontWeight.w600,
                  color: MobileTheme.brand(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: TextStyle(
              fontSize: AppTokens.fontSizeSubcaption, color: textMuted),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: MobileTheme.brand(context),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 展示 AI 草稿的来源与取舍。
///
/// 用户要审的不只是预填出来的文字，还有背后的授权决定：模型想要哪些工具、哪些因为
/// 风险高于安全级没有被默认勾选、哪些因为当前不可用被剔除。这些都必须说出来，
/// 而不是让它们悄悄发生在预填过程里。
class _DraftNotice extends StatelessWidget {
  const _DraftNotice({required this.draft});

  final AgentDraft draft;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 16, color: AppPalette.brandText(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    draft.fromModel ? 'AI 已按你的描述预填' : '已用本地模板预填',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeBodySmall,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.brandText(context),
                    ),
                  ),
                ),
              ],
            ),
            if (draft.goal.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '目标：${draft.goal.trim()}',
                style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    height: 1.5,
                    color: textMuted),
              ),
            ],
            if (draft.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final note in draft.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· $note',
                    style: TextStyle(
                        fontSize: AppTokens.fontSizeFootnote,
                        height: 1.5,
                        color: textColor),
                  ),
                ),
            ],
            if (draft.hasPendingTools) ...[
              const SizedBox(height: 4),
              Text(
                '这些工具高于安全级，因此没有默认勾选，需要就去下面的工具箱里手动打开：'
                '${draft.pendingTools.join('、')}',
                style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    height: 1.5,
                    color: textColor),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '保存前你可以修改任何内容；只有点了保存才会写入。',
              style: TextStyle(
                  fontSize: AppTokens.fontSizeSubcaption, color: textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
