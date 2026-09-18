import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../application/mcp_service.dart';
import '../../infrastructure/system/battery_optimization.dart';
import '../diagnostics/run_analysis_page.dart';
import '../l10n/app_strings.dart';
import '../mcp/mcp_servers_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../plugins/plugins_page.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/floating_toast.dart';
import '../widgets/glass_surface.dart';
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
        setState(() => _mcpCount = servers.where((s) => s.enabled).length);
      }
    } catch (_) {}

    if (!kIsWeb) {
      try {
        final battery = await BatteryOptimization.isIgnoring();
        if (mounted) setState(() => _ignoringBattery = battery);
      } catch (_) {}
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
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Scaffold(
      backgroundColor: isFlat ? canvas : Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurfaceHover,
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
                      '扩展与环境',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildSectionHeader('扩展协议与技能', textMuted),
                  _buildCard(
                    isDark: isDark,
                    children: [
                      _buildRow(
                        icon: Icons.dns_rounded,
                        title: AppStrings.mcpServersSectionTitle,
                        trailing: _mcpCount > 0 ? '$_mcpCount 个连接' : '未连接',
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
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    if (isFlat) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
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
    return GlassSurface(
      role: GlassRole.content,
      variant: GlassVariant.regular,
      intensity: AppAppearanceController.resolvedGlassIntensity,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    return Divider(
      height: 0.8,
      thickness: 0.8,
      indent: 48,
      endIndent: 0,
      color: isDark
          ? AppPalette.darkHairline
          : (isFlat ? AppPalette.lightHairline : const Color(0x28000000)),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    required String trailing,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

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
                  fontSize: AppTokens.fontSizeSubhead,
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
