import '../theme/mobile_theme.dart';
import '../widgets/nexus_list_tile.dart';
import '../widgets/section_card.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../application/mcp_service.dart';
import '../../infrastructure/system/battery_optimization.dart';
import '../agents/agents_page.dart';
import '../dashboard/dashboard_page.dart';
import '../diagnostics/run_analysis_page.dart';
import '../l10n/app_strings.dart';
import '../diagnostics/log_viewer_page.dart';
import '../mcp/mcp_servers_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../plugins/plugins_page.dart';
import '../prompts/prompt_library_page.dart';
import '../workflows/mobile_workflows_page.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_content_box.dart';
import '../widgets/nexus_page_header.dart';
import 'linux_environment_page.dart';
import 'tool_list_page.dart';
import 'workspace_files_page.dart';

/// 扩展与环境：管理 MCP 服务器、Skills 技能包、受控工具清单与 Linux 运行环境
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  final _mcpService = McpService();
  int _mcpCount = 0;

  /// 读取失败时不能显示「未连接」——那会被读成「没有服务器」，
  /// 与「读取失败」是两件事。
  bool _mcpLoadFailed = false;
  bool _ignoringBattery = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final servers = await _mcpService.loadAll();
      if (mounted) {
        setState(() {
          _mcpCount = servers.where((s) => s.enabled).length;
          _mcpLoadFailed = false;
        });
      }
    } catch (_) {
      // 计数为 0 会被读成「没有启用任何 MCP 服务器」，因此失败要明说：
      // 既弹提示，也把行尾从「未连接」换成「读取失败」。
      if (mounted) {
        setState(() => _mcpLoadFailed = true);
        FloatingToast.show(context, 'MCP 服务器列表读取失败', tone: ToastTone.warning);
      }
    }

    if (!kIsWeb) {
      try {
        final battery = await BatteryOptimization.isIgnoring();
        if (mounted) setState(() => _ignoringBattery = battery);
      } catch (_) {
        // 电池优化状态探测失败时保持默认「未豁免」，这是保守取值：界面会提示
        // 用户去申请豁免，而不是错误地宣称已经豁免。
      }
    }
  }

  Future<void> _requestBattery() async {
    if (kIsWeb) {
      FloatingToast.show(context, 'Web 环境不需要电池优化豁免');
      return;
    }
    final launched = await BatteryOptimization.requestIgnore();
    if (!mounted) return;
    if (!launched) {
      FloatingToast.show(context, '请在系统设置中允许后台运行');
      unawaited(openAppSettings());
    }
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted = DesktopTheme.maybeOf(context)?.muted ??
        (isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted);

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: const NexusPageHeader(
        title: '扩展与环境',
      ),
      body: NexusPageLayout(
          child: SafeArea(
        top: false,
        child: NexusContentBox(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _buildSectionHeader('扩展协议与技能', textMuted),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildRow(
                    icon: Icons.dns_rounded,
                    title: AppStrings.mcpServersSectionTitle,
                    trailing: _mcpLoadFailed
                        ? '读取失败'
                        : (_mcpCount > 0 ? '$_mcpCount 个连接' : '未连接'),
                    isDark: isDark,
                    onTap: () => _openPage(const McpServersPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.extension_rounded,
                    title: AppStrings.skillsSectionTitle,
                    trailing: '技能管理',
                    isDark: isDark,
                    onTap: () => _openPage(const PluginsPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.smart_toy_outlined,
                    title: 'Agent 预设管理',
                    trailing: '角色与技能绑定',
                    isDark: isDark,
                    onTap: () => _openPage(const AgentsPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.library_books_outlined,
                    title: '提示词模板库',
                    trailing: '复用系统与任务模板',
                    isDark: isDark,
                    onTap: () => _openPage(const PromptLibraryPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.account_tree_outlined,
                    title: '可复用工作流',
                    trailing: '确定性编排与沙盒试跑',
                    isDark: isDark,
                    onTap: () => _openPage(const MobileWorkflowsPage()),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('工具与运行时', textMuted),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildRow(
                    icon: Icons.build_rounded,
                    title: AppStrings.toolListEntry,
                    trailing: '清单与安全策略',
                    isDark: isDark,
                    onTap: () => _openPage(const ToolListPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.folder_open_rounded,
                    title: AppStrings.workspaceFilesEntry,
                    trailing: '选择项目目录',
                    isDark: isDark,
                    onTap: () => _openPage(const WorkspaceFilesPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.computer_rounded,
                    title: AppStrings.linuxEnvironmentEntry,
                    trailing: 'Termux / proot',
                    isDark: isDark,
                    onTap: () => _openPage(const LinuxEnvironmentPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.analytics_outlined,
                    title: '用量与可观测性',
                    trailing: 'Token 水位分析',
                    isDark: isDark,
                    onTap: () => _openPage(const RunAnalysisPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.bar_chart_outlined,
                    title: '用量看板与统计',
                    trailing: '调用与消耗统计',
                    isDark: isDark,
                    onTap: () => _openPage(const DashboardPage()),
                  ),
                  _buildDivider(isDark),
                  _buildRow(
                    icon: Icons.receipt_long_outlined,
                    title: '系统与运行日志',
                    trailing: '检索事件与诊断',
                    isDark: isDark,
                    onTap: () => _openPage(const LogViewerPage()),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('系统保活与权限', textMuted),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildRow(
                    icon: Icons.battery_charging_full_rounded,
                    title: AppStrings.batteryExemption,
                    trailing: _ignoringBattery ? '已豁免' : '未允许',
                    isDark: isDark,
                    onTap: _requestBattery,
                  ),
                ],
              ),
            ],
          ),
        ),
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
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) {
      return Container(
        decoration: BoxDecoration(
            color: desktop.panel,
            borderRadius: BorderRadius.circular(DesktopTheme.panelRadius),
            border: Border.all(color: desktop.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    }
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
    if (DesktopTheme.maybeOf(context) == null) {
      return NexusListTile(
        icon: icon,
        title: title,
        subtitle: trailing,
        onTap: onTap,
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        showDivider: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
    }
    final textColor = DesktopTheme.maybeOf(context)?.text ??
        (isDark ? AppPalette.darkText : AppPalette.lightText);
    final textMuted = DesktopTheme.maybeOf(context)?.muted ??
        (isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted);

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
                flex: 3,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                  flex: 2,
                  child: Text(
                    trailing,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeSubhead,
                      fontWeight: FontWeight.w400,
                      color: textMuted,
                    ),
                  )),
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
