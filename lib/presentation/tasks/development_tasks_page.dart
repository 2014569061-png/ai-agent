import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/task_service.dart';
import '../../infrastructure/database/app_database.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
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

  final ValueChanged<Conversation>? onConversationSelected;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tasks = _filtered;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
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
      body: AsyncStateView(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: Column(
          children: [
            // 搜索输入栏
            if (_showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

            // 统计与筛选胶囊标签行
            _filtersRow(context),

            // 任务列表
            Expanded(
              child: tasks.isEmpty
                  ? EmptyStateView(
                      icon: Icons.task_alt_outlined,
                      title: _searchQuery.isNotEmpty ? '未搜到相关任务' : '暂无开发任务记录',
                      message: _searchQuery.isNotEmpty
                          ? '可以尝试更换关键词搜索'
                          : '从首页发起开发任务后，这里会呈现所有任务步骤、结构化产物与协作记录。',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _taskCard(tasks[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        children: values.entries.map((entry) {
          final count = _countFor(entry.key);
          final isSelected = _filter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: count > 0 && entry.key == 'waiting_approval'
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppPalette.warning,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
              label: Text('${entry.value} $count'),
              selected: isSelected,
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _taskCard(DevelopmentTaskInfo task) {
    final theme = Theme.of(context);
    final isWaitingApproval =
        task.status == 'waiting_approval' || task.status == 'awaiting_approval';

    return SectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: () => _openTaskDetails(task),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题与状态徽标
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NexusStatusPill.fromString(task.status, isCompact: true),
                ],
              ),
              const SizedBox(height: 6),

              // 任务类型与工作区/模型说明
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                    ),
                    child: Text(
                      task.type,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_relativeTime(task.updatedAt)}'
                      '${task.workspacePath != null ? ' · ${task.workspacePath!.split('/').last}' : ''}'
                      '${task.resumeCount > 0 ? ' · 恢复 ${task.resumeCount} 次' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              // 等待审批时的高亮操作条
              if (isWaitingApproval) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppPalette.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                    border: Border.all(
                      color: AppPalette.warning.withValues(alpha: 0.3),
                    ),
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
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
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
      MaterialPageRoute(
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
