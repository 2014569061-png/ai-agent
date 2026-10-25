import '../widgets/nexus_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/personal_context_service.dart';
import '../../application/providers.dart';
import '../../domain/personal_context.dart';
import '../theme/app_palette.dart';
import '../widgets/async_state_view.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/nexus_sheet.dart';
import 'settings_components.dart';

/// 个人上下文管理页。
///
/// 只做"用户可见、可纠正"这一层：列表按实体类型分组，展示来源/确认状态/
/// 有效期标签；所有写操作（新建、确认、更正、遗忘、别名、关联）都直接落到
/// 个人上下文仓储，页面不缓存业务状态，避免与对话注入看到的数据不一致。
class PersonalContextPage extends ConsumerStatefulWidget {
  const PersonalContextPage({super.key});

  @override
  ConsumerState<PersonalContextPage> createState() =>
      _PersonalContextPageState();
}

class _PersonalContextPageState extends ConsumerState<PersonalContextPage> {
  final TextEditingController _searchController = TextEditingController();

  PersonalContextService? _service;
  List<PersonalContextEntity> _entities = const <PersonalContextEntity>[];
  List<PersonalContextRelation> _relations = const <PersonalContextRelation>[];
  List<PersonalContextConflict> _conflicts = const <PersonalContextConflict>[];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final database = await ref.read(databaseProvider.future);
      final service = PersonalContextService.forDatabase(database);
      await service.ensureReady();
      final query = _searchController.text.trim();
      final entities = await service.list(query: query.isEmpty ? null : query);
      final relations = await service.relations();
      final conflicts = await service.conflicts();
      if (!mounted) return;
      setState(() {
        _service = service;
        _entities = entities;
        _relations = relations;
        _conflicts = conflicts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(
        title: '个人上下文',
        subtitle: '人物、项目、文件与临时事项的关联档案',
        actions: <Widget>[
          IconButton(
            tooltip: '新建条目',
            onPressed: () => unawaited(_showCreateDialog()),
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: NexusPageLayout(
        desktopMaxWidth: 920,
        child: AsyncStateView(
          loading: _loading,
          isEmpty: _entities.isEmpty && _conflicts.isEmpty,
          error: _error,
          onRetry: () => unawaited(_load()),
          emptyIcon: Icons.hub_rounded,
          emptyTitle: '还没有关联上下文',
          emptySubtitle: '记下人物、项目、文件与临时事项，助手在对话中才能把"上次那份方案"指到同一个对象。',
          emptyAction: FilledButton.icon(
            onPressed: () => unawaited(_showCreateDialog()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建条目'),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
            children: <Widget>[
              _buildSearchCard(context),
              if (_conflicts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                const SettingsSectionTitle('需要处理的冲突'),
                _buildConflictCard(context),
              ],
              if (_entities.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                const SettingsSectionTitle('关联关系拓扑图谱'),
                _buildRelationGraphCard(context),
              ],
              ..._buildEntityGroups(context),
              const SizedBox(height: 16),
              Text(
                '推测条目确认前、授权资料未获授权时不会进入上下文。遗忘会清理别名与关联，阻止名称、旧称、别名及同来源资料自动回库；重新添加需你明确确认。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: settingsFaintColor(context),
                      height: 1.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelationGraphCard(BuildContext context) {
    final byId = <String, PersonalContextEntity>{
      for (final e in _entities) e.id: e,
    };
    final activeRelations = _relations
        .where((r) =>
            byId.containsKey(r.fromEntityId) && byId.containsKey(r.toEntityId))
        .toList(growable: false);
    return SettingsGroupCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '节点 ${_entities.length} 个 · 关联边 ${activeRelations.length} 条',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              if (activeRelations.isEmpty)
                Text(
                  '暂无实体间关联边；在下方条目点击「关联」即可构建人物—项目—文件拓扑图谱。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: settingsMutedColor(context),
                      ),
                )
              else
                for (final rel in activeRelations.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.account_tree_rounded, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${byId[rel.fromEntityId]!.label} ──[${rel.relationType}]──> ${byId[rel.toEntityId]!.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: NexusSearchField(
        controller: _searchController,
        hintText: '搜索名称，或试试“上次那份方案”',
        onChanged: (_) => setState(() {}),
        onSubmitted: (value) => unawaited(_resolveReference(value)),
        onClear: () {
          _searchController.clear();
          unawaited(_load());
        },
      ),
    );
  }

  Widget _buildConflictCard(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < _conflicts.length; index++) {
      final conflict = _conflicts[index];
      if (index > 0) children.add(const SettingsDivider());
      children.add(
        SettingsTile(
          icon: Icons.merge_rounded,
          title: conflict.label,
          subtitle: '${conflict.entities.length} 条同名记录，助手不会自动挑选，请更正或遗忘多余条目',
          trailingText: '需处理',
          trailingTextColor: AppPalette.warning,
          onTap: () => _showConflictCandidates(conflict),
        ),
      );
    }
    return SettingsGroupCard(children: children);
  }

  List<Widget> _buildEntityGroups(BuildContext context) {
    final sections = <Widget>[];
    for (final kind in PersonalContextEntityKind.values) {
      final entities = _entities
          .where((entity) => entity.kind == kind)
          .toList(growable: false);
      if (entities.isEmpty) continue;
      sections.add(const SizedBox(height: 20));
      sections.add(SettingsSectionTitle('${kind.label} · ${entities.length}'));
      sections.add(_buildEntityCard(context, entities));
    }
    return sections;
  }

  Widget _buildEntityCard(
    BuildContext context,
    List<PersonalContextEntity> entities,
  ) {
    final children = <Widget>[];
    for (var index = 0; index < entities.length; index++) {
      final entity = entities[index];
      if (index > 0) children.add(const SettingsDivider());
      children.add(
        SettingsTile(
          icon: _iconForKind(entity.kind),
          title: entity.label,
          subtitle: _subtitleFor(entity),
          subtitleMaxLines: 3,
          trailingText: entity.isConfirmed ? '已确认' : '待确认',
          trailingTextColor:
              entity.isConfirmed ? AppPalette.success : AppPalette.warning,
          onTap: () => unawaited(_showActions(entity)),
        ),
      );
    }
    return SettingsGroupCard(children: children);
  }

  static IconData _iconForKind(PersonalContextEntityKind kind) {
    return switch (kind) {
      PersonalContextEntityKind.person => Icons.person_rounded,
      PersonalContextEntityKind.project => Icons.workspaces_rounded,
      PersonalContextEntityKind.file => Icons.description_rounded,
      PersonalContextEntityKind.topic => Icons.topic_rounded,
      PersonalContextEntityKind.preference => Icons.tune_rounded,
      PersonalContextEntityKind.organization => Icons.business_rounded,
      PersonalContextEntityKind.temporaryTask => Icons.timer_rounded,
      PersonalContextEntityKind.other => Icons.label_rounded,
    };
  }

  String _subtitleFor(PersonalContextEntity entity) {
    final parts = <String>[entity.provenanceLabel];
    if (entity.isSpeculative) {
      parts.add('不能作为敏感动作的唯一依据');
    }
    final qualifier = entity.qualifierOrNull;
    if (qualifier != null) parts.add('限定：$qualifier');
    if (entity.projectId != null && entity.projectId!.isNotEmpty) {
      parts.add('项目：${entity.projectId}');
    }
    final validUntil = entity.validUntil;
    if (validUntil != null) {
      parts.add(
        entity.isExpiredAt(DateTime.now().toUtc())
            ? '已过期（${_formatDate(validUntil)}）'
            : '有效至 ${_formatDate(validUntil)}',
      );
    }
    if (entity.revision > 1) parts.add('第 ${entity.revision} 版');
    return parts.join(' · ');
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  PersonalContextService? get _readyService => _service;

  // ---------------------------------------------------------------------------
  // 新建
  // ---------------------------------------------------------------------------

  Future<void> _showCreateDialog() async {
    final service = _readyService;
    if (service == null) return;
    final labelController = TextEditingController();
    final qualifierController = TextEditingController();
    final projectController = TextEditingController();
    final daysController = TextEditingController(
      text: PersonalContextService.defaultTemporaryValidity.inDays.toString(),
    );
    var kind = PersonalContextEntityKind.person;
    var source = PersonalContextSource.userExplicit;
    try {
      final created = await showNexusDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('新建关联条目'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        controller: labelController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          hintText: '例如：王工 / 需求评审方案.pdf',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButton<PersonalContextEntityKind>(
                        isExpanded: true,
                        value: kind,
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => kind = value);
                        },
                        items: PersonalContextEntityKind.values
                            .map((item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item.label),
                                ))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      DropdownButton<PersonalContextSource>(
                        isExpanded: true,
                        value: source,
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => source = value);
                        },
                        items: PersonalContextSource.values
                            .map((item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item.label),
                                ))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: qualifierController,
                        decoration: const InputDecoration(
                          labelText: '限定词（可选）',
                          hintText: '同名人物/文件靠它区分，例如：甲方',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectController,
                        decoration: const InputDecoration(
                          labelText: '所属项目 ID（可选）',
                          hintText: '留空表示全局可见',
                        ),
                      ),
                      if (kind ==
                          PersonalContextEntityKind.temporaryTask) ...<Widget>[
                        const SizedBox(height: 12),
                        TextField(
                          controller: daysController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '有效期（天）',
                            helperText: '临时事项过期后不再参与召回',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (!mounted || created != true) return;
      final label = labelController.text.trim();
      if (label.isEmpty) {
        _toast('名称不能为空', tone: ToastTone.warning);
        return;
      }
      var validUntil = null as DateTime?;
      if (kind == PersonalContextEntityKind.temporaryTask) {
        final days = int.tryParse(daysController.text.trim());
        if (days == null || days <= 0) {
          _toast('有效期需要是大于 0 的天数', tone: ToastTone.warning);
          return;
        }
        validUntil = DateTime.now().toUtc().add(Duration(days: days));
      }
      Future<void> save({bool reentry = false}) async => service.add(
            label: label,
            kind: kind,
            source: source,
            qualifier: qualifierController.text.trim().isEmpty
                ? null
                : qualifierController.text.trim(),
            projectId: projectController.text.trim().isEmpty
                ? null
                : projectController.text.trim(),
            validUntil: validUntil,
            confirmation: source.isSpeculative
                ? PersonalContextConfirmation.unconfirmed
                : PersonalContextConfirmation.confirmed,
            allowForgottenReentry: reentry,
          );
      try {
        await save();
      } on PersonalContextException catch (error) {
        if (error.code != PersonalContextErrorCode.blocked ||
            source != PersonalContextSource.userExplicit) {
          rethrow;
        }
        if (!mounted) return;
        final reentry = await showConfirmAction(context,
            title: '重新添加已遗忘条目？',
            message:
                '「$label」命中名称、旧称、别名或来源遗忘记录。确认只允许你这次明确添加，不会解除后续自动回库保护，也不会恢复旧别名、关联或历史。',
            confirmLabel: '仅重新添加这一次',
            isDanger: false);
        if (!mounted || !reentry) return;
        await save(reentry: true);
      }
      if (!mounted) return;
      _toast('已保存：$label', tone: ToastTone.success);
      await _load();
    } on PersonalContextException catch (error) {
      if (!mounted) return;
      _toast(error.userMessage, tone: ToastTone.warning);
    } finally {
      labelController.dispose();
      qualifierController.dispose();
      projectController.dispose();
      daysController.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // 条目操作
  // ---------------------------------------------------------------------------

  Future<void> _showActions(PersonalContextEntity entity) async {
    final service = _readyService;
    if (service == null) return;
    final aliases = await service.aliases(entityId: entity.id);
    final relations = await service.relations(entityId: entity.id);
    if (!mounted) return;
    final action = await showNexusSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '${entity.kind.label} · ${entity.label}',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitleFor(entity),
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: settingsMutedColor(sheetContext),
                      ),
                ),
                if (aliases.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '别名：${aliases.map((alias) => alias.alias).join('、')}',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: settingsMutedColor(sheetContext),
                        ),
                  ),
                ],
                if (relations.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '关联 ${relations.length} 条',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: settingsMutedColor(sheetContext),
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                if (!entity.isConfirmed)
                  SettingsTile(
                    icon: Icons.verified_rounded,
                    title: '确认这是事实',
                    subtitle:
                        entity.isSpeculative ? '推测来源只能由你确认，助手不会自动升级' : null,
                    showChevron: true,
                    onTap: () => Navigator.of(sheetContext).pop('confirm'),
                  ),
                SettingsTile(
                  icon: Icons.edit_rounded,
                  title: '更正信息',
                  subtitle: '旧版本会保留来源与时间，版本号自动递增',
                  onTap: () => Navigator.of(sheetContext).pop('correct'),
                ),
                SettingsTile(
                  icon: Icons.link_rounded,
                  title: '添加别名',
                  subtitle: '让"上次那份方案"能指到这个对象',
                  onTap: () => Navigator.of(sheetContext).pop('alias'),
                ),
                SettingsTile(
                  icon: Icons.hub_rounded,
                  title: '关联到其他条目',
                  onTap: () => Navigator.of(sheetContext).pop('relate'),
                ),
                SettingsTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppPalette.danger,
                  title: '遗忘并清理关联',
                  titleColor: AppPalette.danger,
                  subtitle: '级联删除别名与关系，并阻止同一名称自动重新写入',
                  showChevron: false,
                  onTap: () => Navigator.of(sheetContext).pop('forget'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'confirm':
        await _confirmEntity(entity);
      case 'correct':
        await _showCorrectDialog(entity);
      case 'alias':
        await _showAliasDialog(entity);
      case 'relate':
        await _showRelationDialog(entity);
      case 'forget':
        await _forgetEntity(entity);
    }
  }

  Future<void> _confirmEntity(PersonalContextEntity entity) async {
    final service = _readyService;
    if (service == null) return;
    try {
      final confirmed = await service.confirm(
        entity.id,
        expectedRevision: entity.revision,
      );
      if (!mounted) return;
      _toast(
        confirmed.isSpeculative ? '已确认（仍标注为推测来源）' : '已确认',
        tone: ToastTone.success,
      );
      await _load();
    } on PersonalContextException catch (error) {
      if (!mounted) return;
      _toast(error.userMessage, tone: ToastTone.warning);
    }
  }

  Future<void> _showCorrectDialog(PersonalContextEntity entity) async {
    final service = _readyService;
    if (service == null) return;
    final labelController = TextEditingController(text: entity.label);
    final qualifierController =
        TextEditingController(text: entity.qualifierOrNull ?? '');
    final noteController = TextEditingController(text: entity.correctionNote);
    final daysController = TextEditingController();
    try {
      final confirmed = await showNexusDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('更正信息'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qualifierController,
                    decoration: const InputDecoration(labelText: '限定词'),
                  ),
                  if (entity.kind ==
                      PersonalContextEntityKind.temporaryTask) ...<Widget>[
                    const SizedBox(height: 12),
                    TextField(
                      controller: daysController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '新的有效期（天，留空保持不变）',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '更正说明（可选）'),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('保存更正'),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmed != true) return;
      final label = labelController.text.trim();
      if (label.isEmpty) {
        _toast('名称不能为空', tone: ToastTone.warning);
        return;
      }
      final days = int.tryParse(daysController.text.trim());
      final validUntil = days == null || days <= 0
          ? null
          : DateTime.now().toUtc().add(Duration(days: days));
      await service.correct(
        entity.id,
        label: label,
        qualifier: qualifierController.text.trim(),
        correctionNote: noteController.text.trim(),
        validUntil: validUntil,
        expectedRevision: entity.revision,
      );
      if (!mounted) return;
      _toast('已更正，版本号递增', tone: ToastTone.success);
      await _load();
    } on PersonalContextException catch (error) {
      if (!mounted) return;
      _toast(error.userMessage, tone: ToastTone.warning);
    } finally {
      labelController.dispose();
      qualifierController.dispose();
      noteController.dispose();
      daysController.dispose();
    }
  }

  Future<void> _showAliasDialog(PersonalContextEntity entity) async {
    final service = _readyService;
    if (service == null) return;
    final controller = TextEditingController();
    try {
      final add = await showNexusDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('添加别名'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '别名',
                hintText: '例如：上次那份方案',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('添加'),
              ),
            ],
          );
        },
      );
      if (!mounted || add != true) return;
      final alias = controller.text.trim();
      if (alias.isEmpty) return;
      await service.addAlias(entity.id, alias);
      if (!mounted) return;
      _toast('已添加别名：$alias', tone: ToastTone.success);
      await _load();
    } on PersonalContextException catch (error) {
      if (!mounted) return;
      _toast(error.userMessage, tone: ToastTone.warning);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showRelationDialog(PersonalContextEntity entity) async {
    final service = _readyService;
    if (service == null) return;
    final candidates = _entities
        .where((other) => other.id != entity.id)
        .toList(growable: false);
    if (candidates.isEmpty) {
      _toast('至少需要两条上下文才能建立关联', tone: ToastTone.warning);
      return;
    }
    final picked = await showNexusSheet<PersonalContextEntity>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  '把「${entity.label}」关联到',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final other in candidates)
                SettingsTile(
                  icon: _iconForKind(other.kind),
                  title: other.label,
                  subtitle: other.kind.label,
                  onTap: () => Navigator.of(sheetContext).pop(other),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    try {
      await service.addRelation(entity.id, picked.id);
      if (!mounted) return;
      _toast('已关联到 ${picked.label}', tone: ToastTone.success);
      await _load();
    } on PersonalContextException catch (error) {
      if (!mounted) return;
      _toast(error.userMessage, tone: ToastTone.warning);
    }
  }

  Future<void> _forgetEntity(PersonalContextEntity entity) async {
    final service = _readyService;
    if (service == null) return;
    final scope = await service.describeForgetScope(entity.id);
    if (!mounted) return;
    final confirmed = await showConfirmAction(
      context,
      title: '遗忘「${entity.label}」？',
      message:
          '遗忘后不再从个人上下文召回；旧名称、别名、改变限定词或从同一来源重新提取，都需要你明确同意后才能重新添加。原始历史保留；同来源保护会保守拦截该来源的新提取，不会删除其他已有条目。',
      confirmLabel: '确认遗忘',
      isDanger: true,
      bulletItems: <String>[
        '别名 ${scope['aliasCount'] ?? 0} 个将被删除',
        '关联 ${scope['relationCount'] ?? 0} 条将被删除',
        '历史版本 ${scope['revisionCount'] ?? 0} 条保留',
        '范围：${scope['scope'] ?? '当前条目'}',
      ],
    );
    if (!mounted || !confirmed) return;
    try {
      final report =
          await service.forget(entity.id, expectedRevision: entity.revision);
      if (!mounted) return;
      _toast(
        '已遗忘，清理别名 ${report.removedAliases} 个、关联 ${report.removedRelations} 条',
        tone: ToastTone.success,
      );
      await _load();
    } on PersonalContextException catch (error) {
      if (!mounted) return;
      _toast(error.userMessage, tone: ToastTone.warning);
    }
  }

  // ---------------------------------------------------------------------------
  // 指代消歧
  // ---------------------------------------------------------------------------

  Future<void> _resolveReference(String value) async {
    final reference = value.trim();
    final service = _readyService;
    if (reference.isEmpty || service == null) return;
    final resolution =
        await service.resolve(PersonalContextLookup(reference: reference));
    if (!mounted) return;
    switch (resolution.status) {
      case PersonalContextResolutionStatus.resolved:
        final entity = resolution.entity!;
        _toast(
          '已定位到「${entity.label}」${entity.qualifierOrNull == null ? '' : '（${entity.qualifierOrNull}）'}',
          tone: ToastTone.success,
        );
      case PersonalContextResolutionStatus.ambiguous:
        await _showCandidateDialog(
          '「$reference」有多个可能对象，请选择一个',
          resolution.candidates,
        );
      case PersonalContextResolutionStatus.expired:
        _toast('该事项已过期，不再参与召回', tone: ToastTone.warning);
      case PersonalContextResolutionStatus.blocked:
        _toast('该条目已被遗忘，不会自动召回', tone: ToastTone.warning);
      case PersonalContextResolutionStatus.unauthorized:
        _toast('来源未授权或属于推测，不能作为敏感动作依据', tone: ToastTone.warning);
      case PersonalContextResolutionStatus.missing:
        _toast('没有匹配的条目', tone: ToastTone.warning);
    }
  }

  Future<void> _showConflictCandidates(PersonalContextConflict conflict) async {
    await _showCandidateDialog(
      '「${conflict.label}」有 ${conflict.entities.length} 条同名记录',
      conflict.entities.map((entity) => PersonalContextCandidate(
            entity: entity,
            score: 0,
            reasons: const <String>['同名冲突'],
          )),
    );
  }

  Future<void> _showCandidateDialog(
    String title,
    Iterable<PersonalContextCandidate> candidates,
  ) async {
    final picked = await showNexusDialog<PersonalContextEntity>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final candidate in candidates)
                  SettingsTile(
                    icon: _iconForKind(candidate.entity.kind),
                    title: candidate.entity.label,
                    subtitle: candidate.explanation,
                    showChevron: false,
                    onTap: () =>
                        Navigator.of(dialogContext).pop(candidate.entity),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('不选择'),
            ),
          ],
        );
      },
    );
    if (!mounted || picked == null) return;
    _toast('已定位到「${picked.label}」', tone: ToastTone.success);
  }

  void _toast(String message, {ToastTone tone = ToastTone.neutral}) {
    FloatingToast.show(context, message, tone: tone);
  }
}
