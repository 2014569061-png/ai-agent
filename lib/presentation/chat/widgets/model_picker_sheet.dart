import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../infrastructure/providers/provider_config.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';

class ModelPickerSelection {
  const ModelPickerSelection({
    required this.profile,
    required this.reasoningEffort,
    required this.planMode,
  });

  final ProviderConfig profile;
  final ReasoningEffort reasoningEffort;
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
    this.onOpenSettings,
    this.onOpenTools,
  });

  final List<ProviderConfig> profiles;
  final String selectedId;
  final ReasoningEffort reasoningEffort;
  final bool planMode;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenTools;

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  late final TextEditingController _searchController;
  late ReasoningEffort _reasoningEffort;
  late bool _planMode;
  late String _executionMode;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _reasoningEffort = widget.reasoningEffort;
    _planMode = widget.planMode;
    _executionMode = widget.planMode ? 'Agent' : 'Chat';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProviderConfig> get _filteredProfiles {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.profiles;
    return widget.profiles
        .where((profile) =>
            profile.name.toLowerCase().contains(query) ||
            profile.model.toLowerCase().contains(query) ||
            profile.baseUrl.toLowerCase().contains(query))
        .toList();
  }

  void _select(ProviderConfig profile) {
    Navigator.pop(
      context,
      ModelPickerSelection(
        profile: profile.copyWith(reasoningEffort: _reasoningEffort),
        reasoningEffort: _reasoningEffort,
        planMode: _planMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.semanticOf(context);
    final grouped = <String, List<ProviderConfig>>{};
    for (final profile in _filteredProfiles) {
      final group = profile.name.trim().isEmpty ? '其他服务' : profile.name;
      grouped.putIfAbsent(group, () => <ProviderConfig>[]).add(profile);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Chat', label: Text('Chat')),
                      ButtonSegment(value: 'Agent', label: Text('Agent')),
                    ],
                    selected: {_executionMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      final mode = selection.first;
                      setState(() {
                        _executionMode = mode;
                        _planMode = mode == 'Agent';
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '搜索模型…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              _OptionBar(
                reasoningEffort: _reasoningEffort,
                planMode: _planMode,
                onReasoningChanged: (effort) =>
                    setState(() => _reasoningEffort = effort),
                onPlanModeChanged: (enabled) => setState(() {
                  _planMode = enabled;
                  _executionMode = enabled ? 'Agent' : 'Chat';
                }),
                onOpenTools: widget.onOpenTools,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: grouped.isEmpty
                    ? _EmptyModels(
                        onOpenSettings: widget.onOpenSettings,
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: Text(
                                entry.key,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.textMuted,
                                  fontWeight: FontWeight.w700,
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
    required this.planMode,
    required this.onReasoningChanged,
    required this.onPlanModeChanged,
    this.onOpenTools,
  });

  final ReasoningEffort reasoningEffort;
  final bool planMode;
  final ValueChanged<ReasoningEffort> onReasoningChanged;
  final ValueChanged<bool> onPlanModeChanged;
  final VoidCallback? onOpenTools;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.language_rounded, size: 18),
            label: const Text('联网工具'),
            onPressed: onOpenTools,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<ReasoningEffort>(
            initialValue: reasoningEffort,
            onSelected: onReasoningChanged,
            itemBuilder: (context) => ReasoningEffort.values
                .map(
                  (effort) => PopupMenuItem(
                    value: effort,
                    child: Text('思考 · ${_effortLabel(effort)}'),
                  ),
                )
                .toList(),
            child: Chip(
              avatar: const Icon(Icons.psychology_outlined, size: 18),
              label: Text('思考 · ${_effortLabel(reasoningEffort)}'),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            selected: planMode,
            onSelected: onPlanModeChanged,
            avatar: Icon(
              Icons.play_circle_outline_rounded,
              size: 18,
              color: planMode
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: const Text('执行模式'),
          ),
        ],
      ),
    );
  }

  static String _effortLabel(ReasoningEffort effort) => switch (effort) {
        ReasoningEffort.off => '关',
        ReasoningEffort.low => '低',
        ReasoningEffort.medium => '中',
        ReasoningEffort.high => '高',
      };
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

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.semanticOf(context);
    return ImmersiveSurface(
      level: selected
          ? ImmersiveMaterialLevel.ultraThin
          : ImmersiveMaterialLevel.ultraThick,
      borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            profile.model,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            profile.isConfigured ? profile.name : '${profile.name} · 未配置',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          trailing: selected
              ? Icon(Icons.check_rounded,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          onTap: onTap,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 38),
            const SizedBox(height: 10),
            const Text('还没有可用模型'),
            if (onOpenSettings != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('去设置添加 Provider'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
