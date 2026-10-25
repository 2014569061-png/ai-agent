import '../widgets/section_card.dart';
import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/data_management_stats_query.dart';
import '../../domain/data_management_stats.dart';
import '../artifacts/artifact_center_page.dart';
import '../audit/audit_log_page.dart';
import '../knowledge/knowledge_page.dart';
import '../l10n/app_strings.dart';
import '../memory/memory_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../scheduled/scheduled_tasks_page.dart';
import '../theme/app_palette.dart';
import '../widgets/nexus_page_header.dart';
import 'data_backup_page.dart';
import 'personal_context_page.dart';
import 'workspace_files_page.dart';
import 'settings_components.dart';

/// 数据管理中心：汇聚长期记忆、知识库、沙箱工作区、自动化定时任务、安全审计日志与备份
class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  DataManagementStats? _stats;
  bool _statsLoading = true;
  bool _statsFailed = false;
  int _statsRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    final request = ++_statsRequest;
    setState(() {
      _statsLoading = true;
      _statsFailed = false;
    });
    try {
      final stats = await ref.read(dataManagementStatsQueryProvider).load();
      if (!mounted || request != _statsRequest) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _statsRequest) return;
      setState(() {
        _statsLoading = false;
        _statsFailed = true;
      });
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => page),
    );
    if (mounted) await _loadStats();
  }

  String _countLabel(int? count, String unit, String empty) {
    if (count == null) return _statsLoading ? '统计中…' : '未读取';
    return count > 0 ? '$count$unit' : empty;
  }

  Widget _buildStatsNotice(Color textMuted) {
    final message = _statsLoading
        ? _stats == null
            ? '正在读取统计信息'
            : '正在刷新统计，暂时显示上次结果'
        : _stats == null
            ? '统计信息读取失败，尚无法确认数据量'
            : '统计刷新失败，当前显示上次成功结果';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            liveRegion: true,
            child: Text(message,
                style: TextStyle(
                    color: _statsFailed
                        ? Theme.of(context).colorScheme.error
                        : textMuted))),
        if (_statsLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(semanticsLabel: '正在读取数据统计'),
          ),
        if (_statsFailed)
          TextButton.icon(
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试统计'),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: NexusPageHeader(
        title: '数据管理',
        subtitle: '知识库、沙箱工作区与数据备份',
        actions: [
          IconButton(
            tooltip: '刷新统计',
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh_rounded),
          )
        ],
      ),
      body: NexusPageLayout(
          desktopMaxWidth: 920,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (_statsLoading || _statsFailed) _buildStatsNotice(textMuted),
              _buildSectionHeader('上下文与知识库', textMuted),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildRow(
                    icon: Icons.auto_stories_rounded,
                    title: AppStrings.knowledgeSectionTitle,
                    trailing: _countLabel(_stats?.knowledgeCount, ' 条文档', '空'),
                    isDark: isDark,
                    onTap: () => _openPage(const KnowledgePage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.psychology_alt_rounded,
                    title: AppStrings.memorySectionTitle,
                    trailing: _countLabel(_stats?.memoryCount, ' 条', '未建立'),
                    isDark: isDark,
                    onTap: () => _openPage(const MemoryPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.folder_rounded,
                    title: AppStrings.workspaceFilesEntry,
                    trailing: '沙箱目录',
                    isDark: isDark,
                    onTap: () => _openPage(const WorkspaceFilesPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.inventory_2_outlined,
                    title: '成果中心',
                    trailing: '产出文件与结果卡',
                    isDark: isDark,
                    onTap: () => _openPage(const ArtifactCenterPage()),
                  ),
                  _buildDivider(isDark),
                  // 实体/引用关联是对话指代的基础能力，放在同一分组便于用户
                  // 先看到"助手记住了谁/什么"，再进入记忆与知识库。
                  _buildRow(
                    icon: Icons.hub_rounded,
                    title: '个人上下文',
                    trailing: '实体与关联',
                    isDark: isDark,
                    onTap: () => _openPage(const PersonalContextPage()),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('自动化与审计', textMuted),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildRow(
                    icon: Icons.schedule_rounded,
                    title: AppStrings.scheduledTasksEntry,
                    trailing:
                        _countLabel(_stats?.scheduledCount, ' 个计划', '无计划'),
                    isDark: isDark,
                    onTap: () => _openPage(const ScheduledTasksPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.fact_check_rounded,
                    title: AppStrings.auditLogEntry,
                    trailing: '审批追踪',
                    isDark: isDark,
                    onTap: () => _openPage(const AuditLogPage()),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('备份与还原', textMuted),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildRow(
                    icon: Icons.cloud_upload_rounded,
                    title: AppStrings.dataBackup,
                    trailing: '快照与恢复',
                    isDark: isDark,
                    onTap: () => _openPage(const DataBackupPage()),
                  ),
                ],
              ),
            ],
          )),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCard({required bool isDark, required List<Widget> children}) {
    return SectionCard(
        child: Column(mainAxisSize: MainAxisSize.min, children: children));
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
        height: 1,
        thickness: .7,
        indent: 70,
        endIndent: 16,
        color: Theme.of(context).colorScheme.outlineVariant);
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    required String trailing,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return SettingsTile(
      icon: icon,
      title: title,
      trailingText: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
