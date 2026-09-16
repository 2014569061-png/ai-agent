import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late double _topP;

  late Set<String> _enabledTools;
  bool _loadingTools = true;
  List<AgentTool> _availableTools = const [];

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
      text: a?.systemPrompt ??
          draft?.systemPrompt ??
          '你是一个智能、严谨且富有创造力的 AI 助手。',
    )..addListener(_markDirty);

    _steps = (a?.maxSteps ?? draft?.maxSteps ?? 8).clamp(1, 32);
    _temperature = (a?.temperature ?? draft?.temperature ?? 0.7).clamp(0.0, 2.0);
    _maxTokens = (a?.maxTokens ?? draft?.maxTokens ?? 2048).clamp(256, 8192);
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
        _enabledTools = decoded is List
            ? decoded.whereType<String>().toSet()
            : <String>{};
      } catch (_) {
        _enabledTools = <String>{};
      }
    }

    // 带草稿进入时视为「未保存的修改」：直接返回会丢掉生成结果，
    // 应当和后端返回键一样先确认。
    _isDirty = draft != null;

    _loadTools();
  }

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
          maxTokens: Value(_maxTokens),
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
          maxTokens: _maxTokens,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
    final hairline = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

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
        backgroundColor: canvas,
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
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (widget.draft != null) ...[
              _DraftNotice(draft: widget.draft!),
              const SizedBox(height: 20),
            ],
            // 1. 基础信息卡片
            const _SectionTitle(title: '基本设定', icon: Icons.badge_outlined),
            SectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 15, color: textColor),
                      decoration: InputDecoration(
                        labelText: '智能体名称 *',
                        labelStyle: TextStyle(fontSize: 13, color: textMuted),
                        hintText: '如：代码审计专家、架构顾问、翻译助手',
                        hintStyle: TextStyle(fontSize: 14, color: textMuted),
                        prefixIcon: const Icon(Icons.smart_toy_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
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
                      style: TextStyle(fontSize: 14, height: 1.4, color: textColor),
                      decoration: InputDecoration(
                        labelText: '系统提示词 (System Prompt) *',
                        labelStyle: TextStyle(fontSize: 13, color: textMuted),
                        hintText: '明确描述该 Agent 的角色人设、专业领域、工作流规范与输出限制…',
                        hintStyle: TextStyle(fontSize: 13, color: textMuted),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
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
            const _SectionTitle(title: '模型与推理参数', icon: Icons.tune_rounded),
            SectionCard(
              child: Padding(
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
                      max: 32,
                      divisions: 31,
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
                    _ParamSlider(
                      label: '单次最大输出 (Max Tokens)',
                      valueText: '$_maxTokens Tokens',
                      description: '单轮回答生成的最大长度保护上限',
                      value: _maxTokens.toDouble(),
                      min: 256,
                      max: 8192,
                      divisions: 31,
                      onChanged: (val) {
                        _markDirty();
                        setState(() => _maxTokens = val.round());
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
              ),
            ),
            const SizedBox(height: 20),

            // 3. 工具箱授权
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionTitle(title: '可用工具箱授权', icon: Icons.handyman_outlined),
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
                  child: const Text('推荐预设', style: TextStyle(fontSize: 12)),
                ),
              ],
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
                              style: TextStyle(fontSize: 13, color: textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _availableTools.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: hairline),
                          itemBuilder: (context, index) {
                            final tool = _availableTools[index];
                            final isChecked =
                                _enabledTools.contains(tool.manifest.name);
                            final isDanger =
                                tool.manifest.risk == ToolRisk.dangerous;
                            final isConfirm = tool.manifest.risk ==
                                ToolRisk.requiresConfirmation;

                            return CheckboxListTile(
                              value: isChecked,
                              activeColor: AppPalette.brand,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      tool.manifest.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDanger
                                          ? AppPalette.danger.withAlpha(25)
                                          : isConfirm
                                              ? AppPalette.warning.withAlpha(25)
                                              : AppPalette.brand.withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isDanger
                                          ? '危险操作'
                                          : isConfirm
                                              ? '需确认'
                                              : '安全',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                        color: isDanger
                                          ? AppPalette.danger
                                          : isConfirm
                                              ? AppPalette.warning
                                              : AppPalette.brand,
                                      ),
                                    ),
                                  ),
                                  if (widget.draft?.pendingTools
                                          .contains(tool.manifest.name) ==
                                      true) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppPalette.brand.withAlpha(25),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'AI 建议',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: AppPalette.brand,
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
                                      fontSize: 12, color: textMuted),
                                ),
                              ),
                              onChanged: (val) {
                                _markDirty();
                                setState(() {
                                  if (val == true) {
                                    _enabledTools.add(tool.manifest.name);
                                  } else {
                                    _enabledTools.remove(tool.manifest.name);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
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
                      minimumSize: const Size.fromHeight(AppTokens.kControlHeight),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
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
                      minimumSize: const Size.fromHeight(AppTokens.kControlHeight),
                      backgroundColor: AppPalette.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
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
                                fontSize: 14, fontWeight: FontWeight.w500)),
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
          Icon(icon, size: 16, color: AppPalette.brand),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
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
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: textColor)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark
                      ? AppPalette.darkHairline
                      : AppPalette.lightHairline,
                ),
              ),
              child: Text(
                valueText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.brand,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: TextStyle(fontSize: 11.5, color: textMuted),
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
            activeColor: AppPalette.brand,
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
                const Icon(Icons.auto_awesome_outlined,
                    size: 16, color: AppPalette.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    draft.fromModel ? 'AI 已按你的描述预填' : '已用本地模板预填',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.brand,
                    ),
                  ),
                ),
              ],
            ),
            if (draft.goal.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '目标：${draft.goal.trim()}',
                style: TextStyle(fontSize: 12, height: 1.5, color: textMuted),
              ),
            ],
            if (draft.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final note in draft.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· $note',
                    style:
                        TextStyle(fontSize: 12, height: 1.5, color: textColor),
                  ),
                ),
            ],
            if (draft.hasPendingTools) ...[
              const SizedBox(height: 4),
              Text(
                '这些工具高于安全级，因此没有默认勾选，需要就去下面的工具箱里手动打开：'
                '${draft.pendingTools.join('、')}',
                style: TextStyle(fontSize: 12, height: 1.5, color: textColor),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '保存前你可以修改任何内容；只有点了保存才会写入。',
              style: TextStyle(fontSize: 11.5, color: textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
