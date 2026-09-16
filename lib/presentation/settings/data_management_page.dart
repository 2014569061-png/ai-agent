import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../audit/audit_log_page.dart';
import '../knowledge/knowledge_page.dart';
import '../l10n/app_strings.dart';
import '../memory/memory_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../scheduled/scheduled_tasks_page.dart';
import '../theme/app_palette.dart';
import 'data_backup_page.dart';
import 'workspace_files_page.dart';

/// 数据管理中心：汇聚长期记忆、知识库、沙箱工作区、自动化定时任务、安全审计日志与备份
class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  int _memoryCount = 0;
  int _knowledgeCount = 0;
  int _scheduledCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final memories = await db.allMemories();
      final docs = await db.allKnowledgeDocs();
      final tasks = await db.allScheduledTasks();
      if (mounted) {
        setState(() {
          _memoryCount = memories.length;
          _knowledgeCount = docs.length;
          _scheduledCount = tasks.length;
        });
      }
    } catch (_) {}
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? AppPalette.darkCanvas : const Color(0xFFF7F8FA);
    final textColor = isDark ? AppPalette.darkText : const Color(0xFF1F2329);
    final textMuted = isDark ? AppPalette.darkTextMuted : const Color(0xFF8E9297);

    return Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark ? AppPalette.darkSurface : const Color(0xFFF2F3F5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: '返回',
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: textColor,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '数据管理',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 36), // 占位对称
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildSectionHeader('上下文与知识库', textMuted),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      _buildRow(
                        icon: Icons.auto_stories_rounded,
                        title: AppStrings.knowledgeSectionTitle,
                        trailing: _knowledgeCount > 0 ? '$_knowledgeCount 条文档' : '空',
                        isDark: isDark,
                        onTap: () => _openPage(const KnowledgePage()),
                      ),
                      _buildDivider(isDark),
                      _buildRow(
                        icon: Icons.psychology_alt_rounded,
                        title: AppStrings.memorySectionTitle,
                        trailing: _memoryCount > 0 ? '$_memoryCount 条' : '未建立',
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
                        trailing: _scheduledCount > 0 ? '$_scheduledCount 个计划' : '无计划',
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
              ),
            ),
          ],
        ),
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppPalette.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppPalette.darkHairline : const Color(0xFFECEEF2),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 0.8,
      thickness: 0.8,
      indent: 48,
      endIndent: 0,
      color: isDark ? AppPalette.darkHairline : const Color(0xFFF0F2F5),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    required String trailing,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final textColor = isDark ? AppPalette.darkText : const Color(0xFF1F2329);
    final textMuted = isDark ? AppPalette.darkTextMuted : const Color(0xFF8E9297);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: textColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                  ),
                ),
              ),
              Text(
                trailing,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: textMuted,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: textMuted.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
