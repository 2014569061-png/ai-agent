import '../theme/mobile_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/project_kind.dart';
import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../motion/nexus_page_route_factory.dart';
import '../motion/nexus_motion.dart';
import '../widgets/async_state_view.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/section_card.dart';
import 'task_details_page.dart';

/// 开发任务中心列表页 (DevelopmentTasksPage)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 顶部增加统计摘要与数量徽标筛选（全部、进行中、等待审批、已完成、失败）。
/// 2. 支持搜索任务标题、工作区与任务指令。
/// 3. 等待审批任务醒目标记并支持一键“立即处理”。
/// 4. 点击任务跳转到全新独立的 TaskDetailsPage 完整详情页。
class DevelopmentTasksPage extends ConsumerStatefulWidget {
  const DevelopmentTasksPage({super.key, this.onConversationSelected});

  final ValueChanged<String>? onConversationSelected;

  @override
  ConsumerState<DevelopmentTasksPage> createState() =>
      _DevelopmentTasksPageState();
}

class _DevelopmentTasksPageState extends ConsumerState<DevelopmentTasksPage> {
  List<DevelopmentTaskInfo> _tasks = const [];
  String _filter = 'all';
  String _searchQuery = '';
  bool _loading = true;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      final db = await ref.read(databaseProvider.future);
      final rows = await ref.read(taskServiceProvider).allTasks(db);
      if (!mounted) return;
      setState(() {
        _tasks = rows
            .map(ref.read(taskServiceProvider).describe)
            .where((task) => task.type != 'agent')
            .toList(growable: false);
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

  List<DevelopmentTaskInfo> get _filtered {
    final query = _searchQuery.trim().toLowerCase();
    return _tasks.where((task) {
      // 状态筛选
      final matchesStatus = switch (_filter) {
        'running' => task.status == 'running',
        'waiting_approval' => task.status == 'waiting_approval' ||
            task.status == 'awaiting_approval',
        'completed' => task.status == 'completed',
        'failed' => task.status == 'failed' || task.status == 'cancelled',
        _ => true,
      };
      if (!matchesStatus) return false;

      // 关键词搜索
      if (query.isNotEmpty) {
        final inTitle = task.title.toLowerCase().contains(query);
        final inPrompt = task.prompt.toLowerCase().contains(query);
        final inWs = task.workspacePath?.toLowerCase().contains(query) ?? false;
        return inTitle || inPrompt || inWs;
      }
      return true;
    }).toList(growable: false);
  }

  int _countFor(String filterKey) {
    if (filterKey == 'all') return _tasks.length;
    if (filterKey == 'running') {
      return _tasks.where((t) => t.status == 'running').length;
    }
    if (filterKey == 'waiting_approval') {
      return _tasks
          .where((t) =>
              t.status == 'waiting_approval' || t.status == 'awaiting_approval')
          .length;
    }
    if (filterKey == 'completed') {
      return _tasks.where((t) => t.status == 'completed').length;
    }
    if (filterKey == 'failed') {
      return _tasks
          .where((t) => t.status == 'failed' || t.status == 'cancelled')
          .length;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _filtered;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: NexusPageHeader(
        title: '开发任务中心',
        actions: [
          IconButton(
            tooltip: _showSearch ? '收起搜索' : '搜索任务',
            icon: Icon(
                _showSearch ? Icons.search_off_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          IconButton(
            tooltip: '刷新任务列表',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: NexusPageLayout(
          child: AsyncStateView(
        loading: _loading,
        refreshing: _loading && _tasks.isNotEmpty,
        retainContentOnError: _tasks.isNotEmpty,
        error: _error,
        onRetry: _load,
        child: Column(
          children: [
            // 搜索输入栏
            if (_showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                // W6：与设置 / 历史页一致的无描边浅底胶囊搜索；聚焦时品牌色细描边。
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '搜索任务标题、工作区路径或指令…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor:
                        (isDark ? AppPalette.darkText : AppPalette.lightText)
                            .withValues(alpha: isDark ? 0.08 : 0.05),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      borderSide: BorderSide(
                        color: AppPalette.brandTextFor(isDark),
                        width: 1.2,
                      ),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

            // 统计与筛选胶囊标签行
            if (_tasks.isNotEmpty) _filtersRow(context),

            // 任务列表
            Expanded(
              child: tasks.isEmpty
                  ? EmptyStateView(
                      icon: Icons.task_alt_outlined,
                      title: _searchQuery.isNotEmpty
                          ? '未搜到相关任务'
                          : _filter != 'all'
                              ? '当前筛选下暂无任务'
                              : '暂无开发任务记录',
                      actionLabel: _searchQuery.isNotEmpty || _filter != 'all'
                          ? '清除筛选'
                          : null,
                      onAction: () => setState(() {
                        _filter = 'all';
                        _searchQuery = '';
                        _searchController.clear();
                      }),
                      message: _searchQuery.isNotEmpty || _filter != 'all'
                          ? '可以更换关键词，或清除筛选查看全部任务。'
                          : '从助手对话或工作区发起开发任务后，这里会呈现历史任务、执行步骤与产物。',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _taskCard(tasks[index]),
                      ),
                    ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _filtersRow(BuildContext context) {
    final values = <String, String>{
      'all': '全部',
      'waiting_approval': '待审批',
      'running': '进行中',
      'completed': '已完成',
      'failed': '失败',
    };

    return SizedBox(
      height: (MediaQuery.textScalerOf(context).scale(12) * 1.6 + 24)
          .clamp(48, 120),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        children: values.entries.where((entry) {
          final count = _countFor(entry.key);
          return entry.key == 'all' || entry.key == _filter || count > 0;
        }).map((entry) {
          final count = _countFor(entry.key);
          final isSelected = _filter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _filterPill(entry.key, entry.value, count, isSelected),
          );
        }).toList(),
      ),
    );
  }

  /// W4：筛选改为无描边填充胶囊（与历史页一致）——选中品牌浅底 + 品牌字，
  /// 数字弱化；待审批有任务时保留琥珀小圆点。
  Widget _filterPill(String key, String label, int count, bool selected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppPalette.darkText : AppPalette.lightText;
    final fg =
        selected ? MobileTheme.brand(context) : base.withValues(alpha: 0.72);
    final radius = BorderRadius.circular(MobileTheme.controlRadius(context));
    return Center(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _filter = key);
            },
            child: AnimatedContainer(
              duration: NexusMotion.durationFast(context),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark
                        ? AppPalette.brandSoftDark
                        : AppPalette.brandSoftLight)
                    : base.withValues(alpha: isDark ? 0.08 : 0.05),
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? MobileTheme.brand(context).withValues(alpha: 0.35)
                      : Colors.transparent,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (count > 0 && key == 'waiting_approval') ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppPalette.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeFootnote,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeFootnote,
                      color: fg.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskCard(DevelopmentTaskInfo task) {
    final theme = Theme.of(context);
    final isWaitingApproval =
        task.status == 'waiting_approval' || task.status == 'awaiting_approval';
    // W2：类型标签显示中文短名；标题已以该名开头（如「问题修复：…」）时不重复。
    final typeLabel = TaskService.taskTypeLabel(task.type);
    final showTypeLabel = !task.title.startsWith(typeLabel);
    final metaColor = theme.colorScheme.onSurfaceVariant;
    // W3：项目类型未识别时不显示「未知项目」，把位置留给工作区名。
    final projectKind = task.projectKind;
    final showProjectKind =
        projectKind != null && projectKind != ProjectKind.unknown;

    // Linear Pro：二级/三级工程任务卡片统一 12px 圆角。
    return SectionCard(
      borderRadius: BorderRadius.circular(MobileTheme.cardRadius(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(MobileTheme.cardRadius(context)),
        onTap: () {
          HapticFeedback.lightImpact();
          _openTaskDetails(task);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Long titles and status remain separate, readable targets.
              LayoutBuilder(builder: (context, constraints) {
                final title = Tooltip(
                    message: task.title,
                    child: Text(task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: AppTokens.fontSizeBody)));
                final status =
                    NexusStatusPill.fromString(task.status, isCompact: true);
                if (constraints.maxWidth < 420 &&
                    MediaQuery.textScalerOf(context).scale(14) > 19) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 8),
                        status,
                      ]);
                }
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      status,
                    ]);
              }),
              if (task.prompt.isNotEmpty && task.prompt != task.title) ...[
                const SizedBox(height: 4),
                Text(
                  task.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeFootnote,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(210),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 6),

              // 任务类型与工作区/模型说明
              Row(
                children: [
                  if (showTypeLabel) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: metaColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                            MobileTheme.controlRadius(context)),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: AppTokens.fontSizeBadge,
                          fontWeight: FontWeight.w600,
                          color: metaColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      '${_relativeTime(task.updatedAt)}'
                      '${task.workspacePath != null ? ' · ${task.workspacePath!.split(RegExp(r'[\\\\/]')).last}' : ''}'
                      '${showProjectKind ? ' · ${projectKind.label}' : ''}'
                      '${task.resumeCount > 0 ? ' · 恢复 ${task.resumeCount} 次' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeFootnote,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),

              // 等待审批时的高亮操作条
              if (isWaitingApproval) ...[
                const SizedBox(height: 10),
                Container(
                  // W5：提示条去描边、圆角 12（嵌套在 16 卡片内），按钮降为琥珀浅底胶囊。
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: AppPalette.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(MobileTheme.insetRadius),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppPalette.warning),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '此任务正在等待您的审批授权',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.warning,
                          ),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              AppPalette.warning.withValues(alpha: 0.16),
                          foregroundColor: AppPalette.warning,
                          elevation: 0,
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _openTaskDetails(task),
                        child:
                            const Text('立即处理', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTaskDetails(DevelopmentTaskInfo task) async {
    await Navigator.of(context).push(
      NexusPageRoute.detail(
        builder: (_) => TaskDetailsPage(
          task: task,
          onConversationSelected: widget.onConversationSelected,
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
