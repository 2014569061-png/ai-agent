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
import '../../infrastructure/system/accessibility_status.dart';
import '../../infrastructure/update/update_service.dart';
import '../account/compliance_page.dart';
import '../feedback/feedback_page.dart';
import '../l10n/app_strings.dart';
import '../mcp/mcp_servers_page.dart';
import '../memory/memory_page.dart';
import '../onboarding/onboarding_page.dart';
import '../plugins/plugins_page.dart';
import '../theme/app_theme_controller.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import 'appearance_theme_page.dart';
import 'data_backup_page.dart';
import 'language_page.dart';
import 'linux_environment_page.dart';
import 'provider_list_page.dart';
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
  bool _deviceDirectEnabled = true;
  bool _sensitiveDeviceRead = false;
  bool _sensitiveDeviceAction = false;
  bool _terminalFileEnabled = true;

  // Permissions
  bool _accessibilityEnabled = false;
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
      _deviceDirectEnabled =
          prefs.getBool('settings.tool.device_direct') ?? true;
      _sensitiveDeviceRead =
          prefs.getBool('settings.tool.sensitive_read') ?? false;
      _sensitiveDeviceAction =
          prefs.getBool('settings.tool.sensitive_action') ?? false;
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

  bool get _isInTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  Future<void> _checkPermissions() async {
    if (kIsWeb || _isInTest) {
      final prefs = await SharedPreferences.getInstance();
      final access = prefs.getBool('settings.perm.accessibility') ?? false;
      if (mounted) {
        setState(() {
          _accessibilityEnabled = access;
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

    final access = await AccessibilityStatus.isEnabled();
    if (mounted) {
      setState(() {
        _accessibilityEnabled = access;
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

  Future<void> _toggleSensitiveTool(
    String key,
    String title,
    bool val,
    void Function(bool) update,
  ) async {
    if (val) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('开启 $title？'),
          content: const Text(
            AppStrings.sensitiveToolWarning,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9500),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('我已知晓并开启'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    update(val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  Future<void> _requestAccessibility() async {
    if (kIsWeb) {
      FloatingToast.show(context, 'Web 环境不支持无障碍服务');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('启用无障碍辅助服务'),
        content: const Text(
          '无障碍增强工具允许 Agent 感知当前屏幕内容并在授权后协助点击。\n\n点击确定将跳转到系统无障碍设置页，请在「已下载的服务」中找到并开启 NEXUS。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('前往系统设置'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await openAppSettings();
      if (mounted) {
        FloatingToast.show(context, '请在系统设置中开启服务，返回后将重新检测授权状态');
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
      FloatingToast.show(context, '当前系统不支持直接拉起，请手动前往电池设置');
      openAppSettings();
    }
  }

  Future<void> _checkUpdate() async {
    final result = await _updateService.checkUpdate();
    if (!mounted) return;
    switch (result.status) {
      case UpdateCheckStatus.update:
        showImmersiveSheet(
          context: context,
          builder: (_) => UpdateSheet(info: result.info!),
        );
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.maybePop(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '返回',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: theme.colorScheme.primary,
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
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : const Color(0xFF000000),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppStrings.settingsHeroSubtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE3E3E8);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: fillBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF000000),
          ),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: AppStrings.searchSettingsPlaceholder,
            hintStyle: const TextStyle(
              fontSize: 14,
              color: Color(0xFF8E8E93),
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF8E8E93),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () => _searchController.clear(),
                    child: const Icon(
                      Icons.cancel_rounded,
                      size: 16,
                      color: Color(0xFF8E8E93),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildGroupCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0x0F000000),
            width: 0.5,
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

  Widget _buildDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 54,
      endIndent: 0,
      color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
    );
  }

  Widget _buildSettingsRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    Color iconGlyphColor = Colors.white,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconGlyphColor, size: 17),
              ),
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
                        color: titleColor ??
                            (isDark ? Colors.white : const Color(0xFF000000)),
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: subtitleColor ??
                              (isDark
                                  ? const Color(0xFF8E8E93)
                                  : const Color(0xFF8E8E93)),
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
                    size: 20,
                    color: isDark
                        ? const Color(0xFF545458)
                        : const Color(0xFFC7C7CC),
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
                            fontSize: 14,
                            color: trailingTextColor ??
                                (isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF8E8E93)),
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
                        size: 20,
                        color: isDark
                            ? const Color(0xFF545458)
                            : const Color(0xFFC7C7CC),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
    Color activeColor = const Color(0xFF34C759),
  }) {
    return SizedBox(
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor,
          activeThumbColor: Colors.white,
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
              iconColor: const Color(0xFF5856D6),
              title: AppStrings.modelProviderEntry,
              trailingText: providerSummary,
              trailingTextColor: hasProvider
                  ? null
                  : const Color(0xFFFF9500),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProviderListPage(),
                  ),
                );
                _loadAll();
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.psychology_rounded,
              iconColor: const Color(0xFF4F46E5),
              title: AppStrings.enableDeepReasoning,
              subtitle: supportsReasoning
                  ? null
                  : '当前模型（$modelText）不支持深度推理，点此更换',
              subtitleColor: const Color(0xFF8E8E93),
              trailingWidget: _buildSwitch(
                value: supportsReasoning && _deepReasoningEnabled,
                onChanged: supportsReasoning ? _toggleDeepReasoning : null,
              ),
              showChevron: !supportsReasoning,
              onTap: supportsReasoning
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProviderListPage(),
                        ),
                      );
                      _loadAll();
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
        ? '未连接'
        : '$mcpEnabledCount 个已连接';

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
              iconColor: const Color(0xFFAF52DE),
              title: AppStrings.memorySectionTitle,
              trailingText: _memoryCount > 0 ? '$_memoryCount 条' : '未建立',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MemoryPage()),
                );
                _loadAll();
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.extension_rounded,
              iconColor: const Color(0xFFFF9500),
              title: AppStrings.skillsSectionTitle,
              trailingText: _skillCount > 0 ? '$_skillCount 个已安装' : '未安装',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PluginsPage()),
                );
                _loadAll();
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.dns_rounded,
              iconColor: const Color(0xFF30B0C7),
              title: AppStrings.mcpServersSectionTitle,
              trailingText: mcpSummary,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const McpServersPage()),
                );
                _loadAll();
              },
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
              iconColor: const Color(0xFF007AFF),
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
              iconColor: const Color(0xFF32ADE6),
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
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.phone_android_rounded,
              iconColor: const Color(0xFF34C759),
              title: AppStrings.enableDeviceDirectTool,
              trailingWidget: _buildSwitch(
                value: _deviceDirectEnabled,
                onChanged: (val) => _toggleTool(
                  'settings.tool.device_direct',
                  val,
                  (v) => setState(() => _deviceDirectEnabled = v),
                ),
              ),
              showChevron: false,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.visibility_rounded,
              iconColor: const Color(0xFFFF9500),
              title: AppStrings.allowSensitiveDeviceRead,
              titleColor: _sensitiveDeviceRead ? const Color(0xFFFF9500) : null,
              subtitle: '需二次确认',
              subtitleColor: const Color(0xFFFF9500),
              trailingWidget: _buildSwitch(
                value: _sensitiveDeviceRead,
                activeColor: const Color(0xFFFF9500),
                onChanged: (val) => _toggleSensitiveTool(
                  'settings.tool.sensitive_read',
                  '读取敏感设备信息',
                  val,
                  (v) => setState(() => _sensitiveDeviceRead = v),
                ),
              ),
              showChevron: false,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.security_rounded,
              iconColor: const Color(0xFFFF3B30),
              title: AppStrings.allowSensitiveDeviceAction,
              titleColor: _sensitiveDeviceAction ? const Color(0xFFFF3B30) : null,
              subtitle: '受审批策略管控',
              subtitleColor: const Color(0xFFFF3B30),
              trailingWidget: _buildSwitch(
                value: _sensitiveDeviceAction,
                activeColor: const Color(0xFFFF3B30),
                onChanged: (val) => _toggleSensitiveTool(
                  'settings.tool.sensitive_action',
                  '敏感设备操作',
                  val,
                  (v) => setState(() => _sensitiveDeviceAction = v),
                ),
              ),
              showChevron: false,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.terminal_rounded,
              iconColor: const Color(0xFF48484A),
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
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.computer_rounded,
              iconColor: const Color(0xFF636366),
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
              iconColor: const Color(0xFFFF9F0A),
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
              iconColor: const Color(0xFF1C1C1E),
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
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Color(0xFFC7C7CC),
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
              iconColor: const Color(0xFF007AFF),
              title: AppStrings.language,
              trailingText: _currentLanguage,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LanguagePage()),
                );
                _loadAll();
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.cloud_upload_rounded,
              iconColor: const Color(0xFF34C759),
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
    final accessLabel = kIsWeb
        ? AppStrings.permUnsupported
        : (_accessibilityEnabled
            ? AppStrings.permGranted
            : AppStrings.permDisabled);
    final accessColor = kIsWeb
        ? Colors.grey
        : (_accessibilityEnabled
            ? const Color(0xFF34C759)
            : const Color(0xFF007AFF));

    final batteryLabel = kIsWeb
        ? AppStrings.permUnsupported
        : (_ignoringBattery
            ? AppStrings.permGranted
            : AppStrings.permDenied);
    final batteryColor = kIsWeb
        ? Colors.grey
        : (_ignoringBattery
            ? const Color(0xFF34C759)
            : const Color(0xFFFF3B30));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(AppStrings.permissionsSection),
        _buildGroupCard(
          context: context,
          children: [
            _buildSettingsRow(
              context: context,
              icon: Icons.accessibility_new_rounded,
              iconColor: const Color(0xFF007AFF),
              title: AppStrings.accessibilityTool,
              trailingBadge: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: accessColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  accessLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accessColor,
                  ),
                ),
              ),
              onTap: _requestAccessibility,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.battery_charging_full_rounded,
              iconColor: const Color(0xFF34C759),
              title: AppStrings.batteryExemption,
              trailingBadge: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: batteryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  batteryLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
              icon: Icons.system_update_rounded,
              iconColor: const Color(0xFF007AFF),
              title: AppStrings.checkUpdate,
              trailingText: '检测更新',
              onTap: _checkUpdate,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.shield_rounded,
              iconColor: const Color(0xFF5856D6),
              title: AppStrings.privacyAndCompliance,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CompliancePage()),
                );
              },
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context: context,
              icon: Icons.feedback_rounded,
              iconColor: const Color(0xFFFF9500),
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
              iconColor: const Color(0xFF8E8E93),
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
      iconColor: const Color(0xFF5856D6),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ProviderListPage())),
    );
    checkItem(
      title: '记忆管理',
      subtitle: '查看与维护长期记忆事实库',
      icon: Icons.psychology_alt_rounded,
      iconColor: const Color(0xFFAF52DE),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const MemoryPage())),
    );
    checkItem(
      title: 'Skills 技能 / 插件',
      subtitle: '浏览与安装技能扩展包',
      icon: Icons.extension_rounded,
      iconColor: const Color(0xFFFF9500),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PluginsPage())),
    );
    checkItem(
      title: 'MCP 服务器',
      subtitle: '管理 Model Context Protocol 扩展端点',
      icon: Icons.dns_rounded,
      iconColor: const Color(0xFF30B0C7),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const McpServersPage())),
    );
    checkItem(
      title: '受控工具清单',
      subtitle: '查看全部 Agent 工具与权限策略',
      icon: Icons.build_rounded,
      iconColor: const Color(0xFF007AFF),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ToolListPage())),
    );
    checkItem(
      title: 'Linux 工具环境',
      subtitle: 'Termux, proot 与终端执行环境',
      icon: Icons.computer_rounded,
      iconColor: const Color(0xFF636366),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LinuxEnvironmentPage())),
    );
    checkItem(
      title: '工作区与文件',
      subtitle: '沙箱目录切换、文件导入导出与缓存清理',
      icon: Icons.folder_rounded,
      iconColor: const Color(0xFFFF9F0A),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const WorkspaceFilesPage())),
    );
    checkItem(
      title: '外观与主题',
      subtitle: '深浅模式、毛玻璃强度、动效与聊天气泡宽度',
      icon: Icons.palette_rounded,
      iconColor: const Color(0xFF1C1C1E),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AppearanceThemePage())),
    );
    checkItem(
      title: '语言 / Language',
      subtitle: '跟随系统、简体中文、English',
      icon: Icons.translate_rounded,
      iconColor: const Color(0xFF007AFF),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LanguagePage())),
    );
    checkItem(
      title: '数据备份',
      subtitle: '隐私保险箱加密导出、还原与清理',
      icon: Icons.cloud_upload_rounded,
      iconColor: const Color(0xFF34C759),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const DataBackupPage())),
    );

    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            '没有找到相关的设置项',
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
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
                  ? const Color(0xFF8E8E93)
                  : const Color(0xFF6C6C70),
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
