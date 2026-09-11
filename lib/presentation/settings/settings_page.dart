import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/mcp_service.dart';
import '../../application/providers.dart';
import '../../infrastructure/mcp/mcp_server_config.dart';
import '../../infrastructure/providers/provider_config.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../../infrastructure/system/battery_optimization.dart';
import '../../infrastructure/update/update_service.dart';
import '../feedback/feedback_page.dart';
import '../l10n/app_strings.dart';
import '../mcp/mcp_servers_page.dart';
import '../memory/memory_page.dart';
import '../onboarding/onboarding_page.dart';
import '../plugins/plugins_page.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme_controller.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import 'appearance_theme_page.dart';
import 'data_backup_page.dart';
import 'language_page.dart';
import '../diagnostics/run_analysis_page.dart';
import 'linux_environment_page.dart';
import 'provider_list_page.dart';
import 'settings_components.dart';
import 'tool_list_page.dart';
import 'update_sheet.dart';
import 'workspace_files_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  final _providerStore = ProviderConfigStore();
  final _mcpService = McpService();
  final _updateService = UpdateService();
  final _searchController = TextEditingController();

  String? _searchQuery;

  // Provider
  ProviderConfig? _activeProvider;
  bool _deepReasoningEnabled = true;

  // Context & Extensions
  int _memoryCount = 0;
  int _skillCount = 0;
  List<McpServerConfig> _mcpServers = [];

  // Tools
  bool _webBrowsingEnabled = true;
  bool _terminalFileEnabled = true;

  // Permissions
  bool _ignoringBattery = false;

  // General
  String _currentLanguage = '跟随系统';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      setState(() => _searchQuery = q.isEmpty ? null : q.toLowerCase());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Active provider
      _activeProvider = await _providerStore.load().timeout(
            const Duration(milliseconds: 300),
            onTimeout: () =>
                const ProviderConfig(baseUrl: '', model: '', apiKey: ''),
          );
      _deepReasoningEnabled =
          prefs.getBool('settings.llm.deep_reasoning') ?? true;

      // Memory & MCP (skipped in widget test environment if not mocked)
      if (!_isInTest) {
        try {
          final db = await ref
              .read(databaseProvider.future)
              .timeout(const Duration(milliseconds: 300));
          final memories = await db.allMemories();
          _memoryCount = memories.length;
          final skills = await db.allSkillPacks();
          _skillCount = skills.length;
        } catch (_) {}

        try {
          _mcpServers = await _mcpService
              .loadAll()
              .timeout(const Duration(milliseconds: 300));
        } catch (_) {}
      }

      // Tools toggles
      _webBrowsingEnabled = prefs.getBool('settings.tool.web_browsing') ?? true;
      _terminalFileEnabled =
          prefs.getBool('settings.tool.terminal_file') ?? true;

      // Language
      final langCode = prefs.getString('settings.language') ?? 'system';
      _currentLanguage = switch (langCode) {
        'zh' => '简体中文',
        'en' => 'English (部分翻译)',
        _ => '跟随系统',
      };

      await _checkPermissions();
    } catch (_) {
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _openMcpServers() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const McpServersPage()),
    );
    if (mounted) unawaited(_loadAll());
  }

  bool get _isInTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  Future<void> _checkPermissions() async {
    if (kIsWeb || _isInTest) {
      if (mounted) {
        setState(() {
          _ignoringBattery = false;
        });
      }
      return;
    }

    bool battery = false;
    try {
      battery = await BatteryOptimization.isIgnoring()
          .timeout(const Duration(milliseconds: 200));
    } catch (_) {}

    if (mounted) {
      setState(() {
        _ignoringBattery = battery;
      });
    }
  }

  bool _supportsReasoning(String? model) {
    if (model == null || model.isEmpty) return false;
    final lower = model.toLowerCase();
    return lower.contains('r1') ||
        lower.contains('reason') ||
        lower.contains('o1') ||
        lower.contains('o3') ||
        lower.contains('thinking') ||
        lower.contains('qwq') ||
        lower.contains('claude-3-7') ||
        lower.contains('gemini-2.0-flash-thinking');
  }

  Future<void> _showPrivacyNotice() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('数据与隐私边界'),
        content: const Text(
          '剪贴板和图片附件仅在当前回合按需使用。\n\n'
          '敏感工具的参数、结果和运行日志在本地持久化、备份与导出时会脱敏；模型当前回合仍可看到完成任务所需的原文。\n\n'
          '删除会话时会同时删除关联的运行事件、日志和审批轨迹。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDeepReasoning(bool val) async {
    setState(() => _deepReasoningEnabled = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings.llm.deep_reasoning', val);
  }

  Future<void> _toggleTool(
      String key, bool val, void Function(bool) update) async {
    update(val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  Future<void> _requestBattery() async {
    if (kIsWeb) {
      FloatingToast.show(context, 'Web 环境不需要电池优化豁免');
      return;
    }
    final launched = await BatteryOptimization.requestIgnore();
    if (!mounted) return;
    if (!launched) {
      FloatingToast.show(context, '当前系统不支持直接拉起，请手动前往电池设置');
      unawaited(openAppSettings());
    }
  }

  Future<void> _checkUpdate() async {
    final result = await _updateService.checkUpdate();
    if (!mounted) return;
    switch (result.status) {
      case UpdateCheckStatus.update:
        unawaited(showImmersiveSheet(
          context: context,
          builder: (_) => UpdateSheet(info: result.info!),
        ));
      case UpdateCheckStatus.upToDate:
        FloatingToast.show(
          context,
          '当前已是最新版本 ${result.currentVersion ?? AppStrings.appVersionName}',
        );
      case UpdateCheckStatus.failed:
        FloatingToast.show(context, result.error ?? '检查失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas;

    return Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 32),
            children: [
              _buildHeroHeader(context),
              const SizedBox(height: 8),
              _buildSearchBar(context),
              const SizedBox(height: 6),
              if (_searchQuery != null)
                _buildSearchResults(context)
              else ...[
                _buildLlmSection(context),
                _buildContextExtensionSection(context),
                _buildToolsSection(context),
                _buildGeneralSection(context),
                _buildPermissionsSection(context),
                _buildAboutSection(context),
                const SizedBox(height: 24),
                _buildLogoutCard(context),
                const SizedBox(height: 24),
                _buildFooter(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // 顶部大标题区域
  // ------------------------------------------------------------
  Widget _buildHeroHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                onTap: () => Navigator.maybePop(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '返回',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.settings,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 22,
              height: 1.35,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppStrings.settingsHeroSubtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(
            color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
            width: 0.8,
          ),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: textColor,
          ),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: AppStrings.searchSettingsPlaceholder,
            hintStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: textMuted,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: textMuted,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () => _searchController.clear(),
                    child: Icon(
                      Icons.cancel_rounded,
                      size: 16,
                      color: textMuted,
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              borderSide: const BorderSide(color: AppPalette.brand, width: 1.0),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }

  // 分组标题 13/500 textMuted，上 24 下 8
  Widget _buildSectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textMuted,
        ),
      ),
    );
  }

  // 分组卡片 12px 圆角、1px 描边、左右内边距 16px
  Widget _buildGroupCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(
            color: hairline,
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  // 卡内行分隔线：1px hairline，从图标右侧起始（左缩进 48px）
  Widget _buildDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    return Divider(
      height: 1.0,
      thickness: 1.0,
      indent: 48,
      endIndent: 0,
      color: hairline,
    );
  }

  // 行结构：20px 图标（textMuted）+ 12px 间隙 + 15/400 标题 + 弹性空间 + 13/400 textFaint 右值 + 4px 间隙 + 16px 箭头
  Widget _buildSettingsRow({
    required BuildContext context,
    required IconData icon,
    Color? iconColor,
    required String title,
    Color? titleColor,
    String? subtitle,
    Color? subtitleColor,
    String? trailingText,
    Color? trailingTextColor,
    Widget? trailingBadge,
    Widget? trailingWidget,
    bool showChevron = true,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppTokens.kListRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: titleColor ?? textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: subtitleColor ?? textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailingWidget != null) ...[
                  trailingWidget,
                  if (showChevron) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: textMuted,
                    ),
                  ],
                ] else ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trailingBadge != null) trailingBadge,
                      if (trailingText != null && trailingText.isNotEmpty) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            trailingText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: trailingTextColor ?? textFaint,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (showChevron)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: textMuted,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
    Color? activeColor,
  }) {
    return SizedBox(
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor ?? AppPalette.brand,
          activeThumbColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: AppTokens.kListRowHeight,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: hairline, width: 1.0),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          onTap: () => _confirmLogout(context),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.logout_rounded, size: 18, color: AppPalette.danger),
                SizedBox(width: 8),
                Text(
                  '退出登录',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('退出后将清除本地临时会话凭证，如需使用需重新输入或配置服务商。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      FloatingToast.show(context, '已退出登录');
    }
  }

  // 页脚 11px textFaint 居中、行高 1.6，与上方卡片间距 24px
  Widget _buildFooter(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFaint =
        isDark ? AppPalette.darkTextFaint : AppPalette.lightTextFaint;

    return Center(
      child: Text(
        '${AppStrings.appTitle} ${AppStrings.appVersionName}\n简洁克制 · 内容优先',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: textFaint,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // LLM 提供商
  // ------------------------------------------------------------
  Widget _buildLlmSection(BuildContext context) {
    final active = _activeProvider;
    final hasProvider = active != null && active.baseUrl.isNotEmpty;
    final modelText =
        (active != null && active.model.isNotEmpty) ? active.model : '未配置';
    final providerSummary = hasProvider
        ? '${active.name} / $modelText'
        : AppStrings.noProviderConfiguredHint;
    final supportsReasoning = _supportsReasoning(active?.model);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.llmProviderSection),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.auto_awesome_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.modelProviderEntry,
              trailingText: providerSummary,
              trailingTextColor: hasProvider ? null : AppPalette.warning,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProviderListPage(),
                  ),
                );
                unawaited(_loadAll());
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.psychology_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.enableDeepReasoning,
              subtitle:
                  supportsReasoning ? null : '当前模型（$modelText）不支持深度推理，点此更换',
              subtitleColor: settingsMutedColor(context),
              trailingWidget: _buildSwitch(
                value: supportsReasoning && _deepReasoningEnabled,
                onChanged: supportsReasoning ? _toggleDeepReasoning : null,
              ),
              showChevron: !supportsReasoning,
              onTap: supportsReasoning
                  ? () => _toggleDeepReasoning(!_deepReasoningEnabled)
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProviderListPage(),
                        ),
                      );
                      unawaited(_loadAll());
                    },
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 上下文与扩展
  // ------------------------------------------------------------
  Widget _buildContextExtensionSection(BuildContext context) {
    final mcpCount = _mcpServers.length;
    final mcpEnabledCount = _mcpServers.where((s) => s.enabled).length;
    final mcpSummary = mcpCount == 0
        ? AppStrings.mcpNotConnected
        : AppStrings.mcpConnectedCount(mcpEnabledCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.contextExtensionSection),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.psychology_alt_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.memorySectionTitle,
              trailingText: _memoryCount > 0 ? '$_memoryCount 条' : '未建立',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MemoryPage()),
                );
                unawaited(_loadAll());
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.extension_rounded,
              iconColor: AppPalette.warning,
              title: AppStrings.skillsSectionTitle,
              trailingText: _skillCount > 0 ? '$_skillCount 个已安装' : '未安装',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PluginsPage()),
                );
                unawaited(_loadAll());
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.dns_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.mcpServersSectionTitle,
              trailingText: mcpSummary,
              onTap: _openMcpServers,
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 工具
  // ------------------------------------------------------------
  Widget _buildToolsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.toolsSectionTitle),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.build_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.toolListEntry,
              trailingText: '清单与策略',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ToolListPage()),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.public_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.enableWebBrowsingTool,
              trailingWidget: _buildSwitch(
                value: _webBrowsingEnabled,
                onChanged: (val) => _toggleTool(
                  'settings.tool.web_browsing',
                  val,
                  (v) => setState(() => _webBrowsingEnabled = v),
                ),
              ),
              showChevron: false,
              onTap: () => _toggleTool(
                'settings.tool.web_browsing',
                !_webBrowsingEnabled,
                (v) => setState(() => _webBrowsingEnabled = v),
              ),
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.terminal_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.enableTerminalFileTool,
              trailingWidget: _buildSwitch(
                value: _terminalFileEnabled,
                onChanged: (val) => _toggleTool(
                  'settings.tool.terminal_file',
                  val,
                  (v) => setState(() => _terminalFileEnabled = v),
                ),
              ),
              showChevron: false,
              onTap: () => _toggleTool(
                'settings.tool.terminal_file',
                !_terminalFileEnabled,
                (v) => setState(() => _terminalFileEnabled = v),
              ),
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.computer_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.linuxEnvironmentEntry,
              trailingText: 'Termux / proot',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LinuxEnvironmentPage(),
                  ),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.folder_rounded,
              iconColor: AppPalette.warning,
              title: AppStrings.workspaceFilesEntry,
              trailingText: '导入与目录',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkspaceFilesPage(),
                  ),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.privacy_tip_outlined,
              iconColor: settingsMutedColor(context),
              title: '数据与隐私边界',
              trailingText: '查看说明',
              onTap: _showPrivacyNotice,
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 通用
  // ------------------------------------------------------------
  Widget _buildGeneralSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.generalSection),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.palette_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.appearanceAndTheme,
              trailingWidget: ValueListenableBuilder<ThemeMode>(
                valueListenable: AppThemeController.mode,
                builder: (_, mode, __) {
                  final label = switch (mode) {
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                    ThemeMode.system => '跟随系统',
                  };
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppPalette.lightTextFaint,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppPalette.lightTextFaint,
                      ),
                    ],
                  );
                },
              ),
              showChevron: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AppearanceThemePage(),
                  ),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.translate_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.language,
              trailingText: _currentLanguage,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LanguagePage()),
                );
                unawaited(_loadAll());
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.cloud_upload_rounded,
              iconColor: AppPalette.success,
              title: AppStrings.dataBackup,
              trailingText: '快照与还原',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DataBackupPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 权限
  // ------------------------------------------------------------
  Widget _buildPermissionsSection(BuildContext context) {
    final batteryLabel = kIsWeb
        ? AppStrings.permUnsupported
        : (_ignoringBattery ? AppStrings.permGranted : AppStrings.permDenied);
    final batteryColor = kIsWeb
        ? Colors.grey
        : (_ignoringBattery ? AppPalette.success : AppPalette.danger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.permissionsSection),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.battery_charging_full_rounded,
              iconColor: AppPalette.success,
              title: AppStrings.batteryExemption,
              trailingBadge: Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: batteryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                child: Text(
                  batteryLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: batteryColor,
                  ),
                ),
              ),
              onTap: _requestBattery,
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 关于
  // ------------------------------------------------------------
  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.aboutSection),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.analytics_outlined,
              iconColor: settingsMutedColor(context),
              title: 'Token 用量与可观测性',
              subtitle: '输入 / 输出 / 缓存命中率与上下文水位',
              trailingText: '查看',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RunAnalysisPage()),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.system_update_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.checkUpdate,
              trailingText: '检测更新',
              onTap: _checkUpdate,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.feedback_rounded,
              iconColor: AppPalette.warning,
              title: AppStrings.feedbackAndIssues,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FeedbackPage()),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.help_outline_rounded,
              iconColor: settingsMutedColor(context),
              title: AppStrings.onboardingGuide,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingPage()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 搜索结果
  // ------------------------------------------------------------
  Widget _buildSearchResults(BuildContext context) {
    final query = _searchQuery!;
    final results = <Widget>[];

    void checkItem({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color iconColor,
      required VoidCallback onTap,
    }) {
      if (title.toLowerCase().contains(query) ||
          subtitle.toLowerCase().contains(query)) {
        results.add(
          _buildSettingsRow(
            context: context,
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            onTap: onTap,
          ),
        );
      }
    }

    checkItem(
      title: '模型提供商',
      subtitle: '配置 OpenAI, Claude, Gemini 等服务商',
      icon: Icons.auto_awesome_rounded,
      iconColor: settingsMutedColor(context),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ProviderListPage())),
    );
    checkItem(
      title: '记忆管理',
      subtitle: '查看与维护长期记忆事实库',
      icon: Icons.psychology_alt_rounded,
      iconColor: settingsMutedColor(context),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const MemoryPage())),
    );
    checkItem(
      title: 'Skills 技能 / 插件',
      subtitle: '浏览与安装技能扩展包',
      icon: Icons.extension_rounded,
      iconColor: AppPalette.warning,
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PluginsPage())),
    );
    checkItem(
      title: AppStrings.mcpServers,
      subtitle: AppStrings.mcpServersSearchHint,
      icon: Icons.dns_rounded,
      iconColor: settingsMutedColor(context),
      onTap: _openMcpServers,
    );
    checkItem(
      title: '受控工具清单',
      subtitle: '查看全部 Agent 工具与权限策略',
      icon: Icons.build_rounded,
      iconColor: settingsMutedColor(context),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ToolListPage())),
    );
    checkItem(
      title: 'Linux 工具环境',
      subtitle: 'Termux, proot 与终端执行环境',
      icon: Icons.computer_rounded,
      iconColor: settingsMutedColor(context),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LinuxEnvironmentPage())),
    );
    checkItem(
      title: '工作区与文件',
      subtitle: '沙箱目录切换、文件导入导出与缓存清理',
      icon: Icons.folder_rounded,
      iconColor: AppPalette.warning,
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const WorkspaceFilesPage())),
    );
    checkItem(
      title: '外观与主题',
      subtitle: '深浅模式、毛玻璃强度、动效与聊天气泡宽度',
      icon: Icons.palette_rounded,
      iconColor: settingsMutedColor(context),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AppearanceThemePage())),
    );
    checkItem(
      title: '语言 / Language',
      subtitle: '跟随系统、简体中文、English',
      icon: Icons.translate_rounded,
      iconColor: settingsMutedColor(context),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LanguagePage())),
    );
    checkItem(
      title: '数据备份',
      subtitle: '隐私保险箱加密导出、还原与清理',
      icon: Icons.cloud_upload_rounded,
      iconColor: AppPalette.success,
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const DataBackupPage())),
    );

    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            '没有找到相关的设置项',
            style: TextStyle(color: AppPalette.lightTextFaint, fontSize: 14),
          ),
        ),
      );
    }

    final cardChildren = <Widget>[];
    for (var i = 0; i < results.length; i++) {
      cardChildren.add(results[i]);
      if (i < results.length - 1) {
        cardChildren.add(_buildDivider(context));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 16, 6),
          child: Text(
            '搜索结果（${results.length} 项）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppPalette.lightTextFaint
                  : AppPalette.lightTextMuted,
            ),
          ),
        ),
        _buildGroupCard(
          context: context,
          children: cardChildren,
        ),
      ],
    );
  }
}
