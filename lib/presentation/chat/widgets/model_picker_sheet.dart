import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../widgets/empty_state_view.dart';
import '../../../infrastructure/providers/provider_config.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';

class ModelPickerSelection {
  const ModelPickerSelection({
    required this.profile,
    required this.reasoningEffort,
    required this.mode,
    required this.planMode,
  });

  final ProviderConfig profile;
  final ReasoningEffort reasoningEffort;
  final ChatMode mode;
  final bool planMode;
}

/// 首页模型选择面板：搜索、按服务分组，并在同一处调整 Chat/Agent、思考程度和工具入口。
class ModelPickerSheet extends StatefulWidget {
  const ModelPickerSheet({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.reasoningEffort,
    required this.planMode,
    this.mode,
    this.onOpenSettings,
    this.onOpenTools,
  });

  final List<ProviderConfig> profiles;
  final String selectedId;
  final ReasoningEffort reasoningEffort;
  final bool planMode;
  final ChatMode? mode;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenTools;

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  static const _categories = ['全部', 'DeepSeek', 'Anthropic', 'OpenAI', '本地'];
  late final TextEditingController _searchController;
  late ReasoningEffort _reasoningEffort;
  late ChatMode _mode;
  String _selectedCategory = '全部';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _reasoningEffort = widget.reasoningEffort;
    _mode = widget.mode ?? (widget.planMode ? ChatMode.plan : ChatMode.chat);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesKeyword(ProviderConfig p, List<String> keywords) {
    final text = '${p.name} ${p.model} ${p.baseUrl}'.toLowerCase();
    return keywords.any((kw) => text.contains(kw));
  }

  List<ProviderConfig> get _filteredProfiles {
    return widget.profiles.where((profile) {
      if (_selectedCategory != '全部') {
        final matchesCat = switch (_selectedCategory) {
          'DeepSeek' => _matchesKeyword(profile, ['deepseek']),
          'Anthropic' => _matchesKeyword(profile, ['anthropic', 'claude']),
          'OpenAI' => _matchesKeyword(profile, ['openai', 'gpt']),
          '本地' => profile.id == 'local' ||
              _matchesKeyword(profile, [
                '本地',
                'local',
                'ollama',
                '127.0.0.1',
                'localhost',
                'qwen',
                'llama'
              ]),
          _ => true,
        };
        if (!matchesCat) return false;
      }
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return profile.name.toLowerCase().contains(query) ||
          profile.model.toLowerCase().contains(query) ||
          profile.baseUrl.toLowerCase().contains(query);
    }).toList();
  }

  void _select(ProviderConfig profile) {
    Navigator.pop(
      context,
      ModelPickerSelection(
        profile: profile.copyWith(reasoningEffort: _reasoningEffort),
        reasoningEffort: _reasoningEffort,
        mode: _mode,
        planMode: _mode == ChatMode.plan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = AppTheme.semanticOf(context);
    final grouped = <String, List<ProviderConfig>>{};
    for (final profile in _filteredProfiles) {
      final group = profile.name.trim().isEmpty ? '其他服务' : profile.name;
      grouped.putIfAbsent(group, () => <ProviderConfig>[]).add(profile);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择模型',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  SegmentedButton<ChatMode>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: ChatMode.chat, label: Text('聊天')),
                      ButtonSegment(
                          value: ChatMode.agent, label: Text('Agent')),
                      ButtonSegment(value: ChatMode.plan, label: Text('计划')),
                    ],
                    selected: {_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() => _mode = selection.first);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppPalette.darkText : AppPalette.lightText),
                decoration: InputDecoration(
                  hintText: '搜索模型…',
                  hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppPalette.darkTextMuted
                          : AppPalette.lightTextMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  filled: true,
                  fillColor:
                      isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppPalette.darkHairline
                          : AppPalette.lightHairline,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppPalette.darkHairline
                          : AppPalette.lightHairline,
                    ),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),

              // 厂商过滤 Tab 栏 (对标效果图 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) {
                    final selected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: selected,
                        label: Text(cat),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? Colors.white
                              : (isDark
                                  ? AppPalette.darkText
                                  : AppPalette.lightText),
                        ),
                        selectedColor: AppPalette.brand,
                        backgroundColor: isDark
                            ? AppPalette.darkSurface
                            : AppPalette.lightSurface,
                        checkmarkColor: Colors.white,
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusPill),
                          side: BorderSide(
                            color: selected
                                ? Colors.transparent
                                : (isDark
                                    ? AppPalette.darkHairline
                                    : AppPalette.lightHairline),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() => _selectedCategory = cat);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),

              Flexible(
                child: grouped.isEmpty
                    ? _EmptyModels(
                        onOpenSettings: widget.onOpenSettings,
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final entry in grouped.entries) ...[
                            if (grouped.length > 1)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 6, 4, 4),
                                child: Text(
                                  entry.key,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ...entry.value.map(
                              (profile) => _ModelTile(
                                profile: profile,
                                selected: profile.id == widget.selectedId,
                                onTap: () => _select(profile),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 10),

              // 底部：内嵌式思考强度切换栏与工具入口 (对标效果图 1)
              _OptionBar(
                reasoningEffort: _reasoningEffort,
                onReasoningChanged: (effort) =>
                    setState(() => _reasoningEffort = effort),
                onOpenTools: widget.onOpenTools,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionBar extends StatelessWidget {
  const _OptionBar({
    required this.reasoningEffort,
    required this.onReasoningChanged,
    this.onOpenTools,
  });

  final ReasoningEffort reasoningEffort;
  final ValueChanged<ReasoningEffort> onReasoningChanged;
  final VoidCallback? onOpenTools;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(
          color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_outlined, size: 17, color: AppPalette.brand),
          const SizedBox(width: 6),
          Text(
            '思考',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _effortChip('关', ReasoningEffort.off),
                  _effortChip('低', ReasoningEffort.low),
                  _effortChip('中', ReasoningEffort.medium),
                  _effortChip('高', ReasoningEffort.high),
                  _effortChip('自动', ReasoningEffort.auto),
                ],
              ),
            ),
          ),
          if (onOpenTools != null) ...[
            Container(
              height: 16,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
            ),
            GestureDetector(
              onTap: onOpenTools,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.language_rounded, size: 15, color: textMuted),
                    const SizedBox(width: 3),
                    Text(
                      '工具',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _effortChip(String label, ReasoningEffort effort) {
    final selected = reasoningEffort == effort;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => onReasoningChanged(effort),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? AppPalette.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : AppPalette.darkTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final ProviderConfig profile;
  final bool selected;
  final VoidCallback onTap;

  List<String> _extractCapabilities(String model, int contextTokens) {
    final lower = model.toLowerCase();
    final tags = <String>[];
    if (lower.contains('r1') ||
        lower.contains('reasoner') ||
        lower.contains('o1') ||
        lower.contains('o3') ||
        lower.contains('thinking')) {
      tags.add('深度推理');
    }
    if (contextTokens >= 64000 ||
        lower.contains('claude') ||
        lower.contains('gemini') ||
        lower.contains('r1')) {
      tags.add('64K+ 上下文');
    }
    if (lower.contains('flash') ||
        lower.contains('mini') ||
        lower.contains('turbo') ||
        lower.contains('haiku')) {
      tags.add('超快响应');
    }
    if (lower.contains('vision') ||
        lower.contains('4o') ||
        lower.contains('gemini') ||
        lower.contains('claude')) {
      tags.add('多模态');
    }
    return tags;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final tags = _extractCapabilities(profile.model, profile.contextTokens);

    const accentCyan = Color(0xFF00E5FF);
    final borderColor = selected
        ? accentCyan
        : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline);
    final cardBg = selected
        ? (isDark ? const Color(0xFF10252C) : const Color(0xFFEDFCFF))
        : (isDark ? AppPalette.darkSurface : AppPalette.lightSurface);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: borderColor, width: selected ? 1.5 : 1.0),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accentCyan.withValues(alpha: 0.18),
                  blurRadius: 8,
                  spreadRadius: 0,
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        profile.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          size: 18, color: accentCyan)
                    else
                      Text(
                        profile.name,
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  profile.isConfigured
                      ? profile.baseUrl
                      : '${profile.name} · 未配置 API Key',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: textMuted),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? accentCyan.withValues(alpha: 0.12)
                              : (isDark
                                  ? AppPalette.darkCanvas
                                  : AppPalette.lightCanvas),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selected
                                ? accentCyan.withValues(alpha: 0.4)
                                : (isDark
                                    ? AppPalette.darkHairline
                                    : AppPalette.lightHairline),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: selected ? accentCyan : textMuted,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyModels extends StatelessWidget {
  const _EmptyModels({this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyStateView.compact(
        icon: Icons.tune_rounded,
        title: '还没有可用模型',
        actionLabel: onOpenSettings == null ? null : '去设置添加 Provider',
        onAction: onOpenSettings,
      ),
    );
  }
}
