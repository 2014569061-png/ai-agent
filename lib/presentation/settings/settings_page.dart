import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/providers/provider_config.dart';
import '../../infrastructure/providers/provider_config_store.dart';
import '../../infrastructure/update/update_service.dart';
import '../feedback/feedback_page.dart';
import '../l10n/app_strings.dart';
import '../motion/nexus_page_route_factory.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_theme_controller.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/liquid_glass.dart' show GlassIntensity;
import '../widgets/nexus_async_content.dart';
import '../widgets/nexus_content_box.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/section_card.dart';
import '../widgets/confirm_action.dart';
import 'appearance_theme_page.dart';
import 'data_management_page.dart';
import 'device_automation_page.dart';
import 'device_backups_page.dart';
import 'device_capabilities_page.dart';
import 'extensions_page.dart';
import 'language_page.dart';
import 'provider_list_page.dart';
import 'update_sheet.dart';

typedef SettingsLoader = Future<SettingsSnapshot> Function();

/// Values loaded before the settings menu is rendered.
class SettingsSnapshot {
  const SettingsSnapshot({
    this.activeProvider,
    this.currentLanguage = '跟随系统',
    this.fontSizeLabel = '标准',
    this.appVersion,
    this.appBuildNumber,
    this.isEmpty = false,
  });

  const SettingsSnapshot.empty()
      : activeProvider = null,
        currentLanguage = '跟随系统',
        fontSizeLabel = '标准',
        appVersion = null,
        appBuildNumber = null,
        isEmpty = true;

  final ProviderConfig? activeProvider;
  final String currentLanguage;
  final String fontSizeLabel;
  final String? appVersion;
  final String? appBuildNumber;
  final bool isEmpty;
}

enum _SettingsLoadState { loading, ready, empty, error }

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.loadSettings});

  /// Optional loader seam used by embedders and widget tests.
  final SettingsLoader? loadSettings;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _providerStore = ProviderConfigStore();
  final _updateService = UpdateService();

  ProviderConfig? _activeProvider;
  String _currentLanguage = '跟随系统';
  String _fontSizeLabel = '标准';
  String? _appVersion;
  String? _appBuildNumber;
  _SettingsLoadState _loadState = _SettingsLoadState.loading;
  Object? _loadError;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isInTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (mounted && _loadState != _SettingsLoadState.loading) {
      setState(() {
        _loadState = _SettingsLoadState.loading;
        _loadError = null;
      });
    }

    try {
      final snapshot = widget.loadSettings != null
          ? await widget.loadSettings!()
          : await _loadFromPlatform();

      if (!mounted) return;
      setState(() {
        _activeProvider = snapshot.activeProvider;
        _currentLanguage = snapshot.currentLanguage;
        _fontSizeLabel = snapshot.fontSizeLabel;
        _appVersion = snapshot.appVersion;
        _appBuildNumber = snapshot.appBuildNumber;
        _loadState = snapshot.isEmpty
            ? _SettingsLoadState.empty
            : _SettingsLoadState.ready;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadState = _SettingsLoadState.error;
        _loadError = error;
      });
    }
  }

  Future<SettingsSnapshot> _loadFromPlatform() async {
    final prefs = await SharedPreferences.getInstance();

    // Active provider
    ProviderConfig? activeProvider;
    if (!_isInTest) {
      activeProvider = await _providerStore.load().timeout(
            const Duration(milliseconds: 300),
            onTimeout: () =>
                const ProviderConfig(baseUrl: '', model: '', apiKey: ''),
          );
    } else {
      activeProvider = const ProviderConfig(baseUrl: '', model: '', apiKey: '');
    }

    // Language
    final lang = prefs.getString('settings.language');
    _currentLanguage = switch (lang) {
      'zh' => '中文(简体中文)',
      'en' => 'English',
      _ => '跟随系统',
    };

    // Font size
    final fontScale = prefs.getDouble('settings.font_scale') ?? 1.0;
    _fontSizeLabel = fontScale <= 0.9
        ? '较小'
        : fontScale >= 1.25
            ? '特大'
            : fontScale >= 1.12
                ? '较大'
                : '标准';

    // App version (从平台 PackageInfo 读取单一来源)
    String? appVersion;
    String? appBuildNumber;
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(milliseconds: 300));
      appVersion = info.version;
      appBuildNumber = info.buildNumber;
    } catch (_) {
      // 平台信息不可用或处于测试环境无 mock 时保持 null
    }

    return SettingsSnapshot(
      activeProvider: activeProvider,
      currentLanguage: _currentLanguage,
      fontSizeLabel: _fontSizeLabel,
      appVersion: appVersion,
      appBuildNumber: appBuildNumber,
      isEmpty: _isEmptySettings(prefs, activeProvider),
    );
  }

  bool _isEmptySettings(
    SharedPreferences prefs,
    ProviderConfig? activeProvider,
  ) {
    final hasStoredSettings = prefs.getKeys().any(
              (key) =>
                  key.startsWith('settings.') || key.startsWith('provider.'),
            ) ||
        activeProvider?.isConfigured == true;
    return !hasStoredSettings;
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => page),
    );
  }

  Future<void> _showPrivacyNotice() async {
    await showNexusDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('服务协议与隐私'),
        content: const Text(
          '1. NEXUS Agent 在本地沙箱中安全运行，对敏感文件和终端操作实行前置鉴权与审计。\n\n'
          '2. API Key 和个人认证凭据经由本机硬件安全模块及安全存储加密，绝不上传至任何第三方同步服务器。\n\n'
          '3. 剪贴板和图片附件仅在当前对话回合按需使用，且敏感参数自动在持久化与导出时脱敏。\n\n'
          '4. 内容由 AI 生成，请仔细甄别，并在合法合规框架内使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectFontSize() async {
    if (!mounted) return;

    await showNexusSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '字体大小设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('较小 (Small)'),
              trailing: _fontSizeLabel == '较小'
                  ? const Icon(Icons.check, color: AppPalette.brand)
                  : null,
              onTap: () async {
                await AppAppearanceController.setFontScale(0.88);
                setState(() => _fontSizeLabel = '较小');
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              title: const Text('标准 (Standard)'),
              trailing: _fontSizeLabel == '标准'
                  ? const Icon(Icons.check, color: AppPalette.brand)
                  : null,
              onTap: () async {
                await AppAppearanceController.setFontScale(1.0);
                setState(() => _fontSizeLabel = '标准');
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              title: const Text('较大 (Large)'),
              trailing: _fontSizeLabel == '较大'
                  ? const Icon(Icons.check, color: AppPalette.brand)
                  : null,
              onTap: () async {
                await AppAppearanceController.setFontScale(1.15);
                setState(() => _fontSizeLabel = '较大');
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              title: const Text('特大 (Extra Large)'),
              trailing: _fontSizeLabel == '特大'
                  ? const Icon(Icons.check, color: AppPalette.brand)
                  : null,
              onTap: () async {
                await AppAppearanceController.setFontScale(1.28);
                setState(() => _fontSizeLabel = '特大');
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final result = await _updateService.checkUpdate();
    if (!mounted) return;
    switch (result.status) {
      case UpdateCheckStatus.update:
        unawaited(showNexusSheet(
          context: context,
          builder: (_) => UpdateSheet(info: result.info!),
        ));
      case UpdateCheckStatus.upToDate:
        FloatingToast.show(
          context,
          '当前已是最新版本 ${result.currentVersion ?? (_appVersion != null ? 'v$_appVersion' : '')}'
              .trim(),
        );
      case UpdateCheckStatus.failed:
        FloatingToast.show(context, result.error ?? '检查失败');
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showConfirmAction(
      context,
      title: '清除本地凭证？',
      message: '将移除服务商配置和工具凭证，但不会删除聊天记录。清除后需要重新配置模型。',
      confirmLabel: '清除凭证',
      isDanger: true,
    );

    if (!confirmed) return;
    try {
      await _providerStore.clearAll();
      if (!context.mounted) return;
      unawaited(_loadAll());
      FloatingToast.show(context, '本地凭证已清除');
    } catch (error) {
      if (context.mounted) {
        FloatingToast.error(context, '清除凭证失败', rawDetail: error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? AppPalette.darkCanvas : AppPalette.lightSurface;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final themeMode = AppThemeController.mode.value;
    final themeLabel = switch (themeMode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      ThemeMode.system => '系统',
    };

    final providerText =
        (_activeProvider != null && _activeProvider!.name.isNotEmpty)
            ? _activeProvider!.name
            : '未配置';

    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;

    return Scaffold(
      backgroundColor: isFlat ? canvas : Colors.transparent,
      body: SafeArea(
        child: NexusContentBox(
          child: Column(
            children: [
              // 顶栏：微圆角后退键 + 居中标题「设置」
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
                      child: Semantics(
                        header: true,
                        child: Text(
                          '设置',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 36), // 保持居中对称
                  ],
                ),
              ),
              Expanded(
                child: NexusAsyncContent(
                  loading: _loadState == _SettingsLoadState.loading,
                  error: _loadState == _SettingsLoadState.error
                      ? _loadError
                      : null,
                  onRetry: _loadAll,
                  child: RefreshIndicator(
                    onRefresh: _loadAll,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
                        // 0. 搜索栏
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val.trim()),
                            style: TextStyle(
                              fontSize: AppTokens.fontSizeBody,
                              color: textColor,
                            ),
                            decoration: InputDecoration(
                              hintText: AppStrings.searchSettingsPlaceholder,
                              hintStyle: TextStyle(
                                fontSize: AppTokens.fontSizeBody,
                                color: textMuted,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: textMuted,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded,
                                          size: 18),
                                      tooltip: '清空搜索',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              // T2：搜索做成无描边浅底胶囊；聚焦时才出现品牌色细描边。
                              fillColor: textColor.withValues(
                                  alpha: isDark ? 0.08 : 0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusPill),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusPill),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusPill),
                                borderSide: BorderSide(
                                  color: AppPalette.brandTextFor(isDark),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),

                        if (_loadState == _SettingsLoadState.empty &&
                            _searchQuery.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: EmptyStateView.compact(
                              icon: Icons.settings_outlined,
                              title: '尚未配置服务商',
                              message: '可以先配置一个服务商，其他设置仍可继续使用。',
                              actionLabel: '配置服务商',
                              onAction: () =>
                                  _openPage(const ProviderListPage()),
                            ),
                          ),

                        if (_searchQuery.isNotEmpty &&
                            !_hasAnyMatch(
                              providerText: providerText,
                              themeLabel: themeLabel,
                            ))
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: EmptyStateView.compact(
                              icon: Icons.search_off_rounded,
                              title: '未找到相关设置',
                              message: '请尝试其他关键词',
                            ),
                          ),

                        // 1. 账户组
                        if (_matchesSearch('账号管理', providerText) ||
                            _matchesSearch('数据管理')) ...[
                          _buildSectionHeader('账户', textMuted),
                          _buildCard(
                            children: _joinWithDividers([
                              if (_matchesSearch('账号管理', providerText))
                                _buildRow(
                                  icon: Icons.person_outline_rounded,
                                  title: '账号管理',
                                  trailing: providerText,
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const ProviderListPage()),
                                ),
                              if (_matchesSearch('数据管理'))
                                _buildRow(
                                  icon: Icons.storage_outlined,
                                  title: '数据管理',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const DataManagementPage()),
                                ),
                            ], isDark),
                          ),
                          const SizedBox(height: AppTokens.sp4),
                        ],

                        // 2. 应用组
                        if (_matchesSearch('语言', _currentLanguage) ||
                            _matchesSearch('外观', themeLabel) ||
                            _matchesSearch('字体大小', _fontSizeLabel) ||
                            _matchesSearch('扩展与环境', 'MCP / 技能 / 工具') ||
                            _matchesSearch('设备能力',
                                'Root / Magisk / KernelSU / Termux / Linux Runtime / SAF')) ...[
                          _buildSectionHeader('应用', textMuted),
                          _buildCard(
                            children: _joinWithDividers([
                              if (_matchesSearch('语言', _currentLanguage))
                                _buildRow(
                                  icon: Icons.language_rounded,
                                  title: '语言',
                                  trailing: _currentLanguage,
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () => _openPage(const LanguagePage()),
                                ),
                              if (_matchesSearch('外观', themeLabel))
                                _buildRow(
                                  icon: Icons.wb_sunny_outlined,
                                  title: '外观',
                                  trailing: themeLabel,
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const AppearanceThemePage()),
                                ),
                              if (_matchesSearch('字体大小', _fontSizeLabel))
                                _buildRow(
                                  icon: Icons.format_size_rounded,
                                  title: '字体大小',
                                  trailing: _fontSizeLabel,
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: _selectFontSize,
                                ),
                              if (_matchesSearch('扩展与环境', 'MCP / 技能 / 工具'))
                                _buildRow(
                                  icon: Icons.extension_outlined,
                                  title: '扩展与环境',
                                  trailing: 'MCP / 技能 / 工具',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const ExtensionsPage()),
                                ),
                              if (_matchesSearch('设备能力',
                                  'Root / Magisk / KernelSU / Termux / Linux Runtime / SAF'))
                                _buildRow(
                                  icon: Icons.admin_panel_settings_outlined,
                                  title: '设备能力',
                                  trailing: 'Root / Termux / Linux / SAF',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const DeviceCapabilitiesPage()),
                                ),
                              if (_matchesSearch('设备自动化', '定时 / Wi-Fi / 电量触发'))
                                _buildRow(
                                  icon: Icons.bolt_outlined,
                                  title: '设备自动化',
                                  trailing: '定时 / Wi-Fi / 电量',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const DeviceAutomationPage()),
                                ),
                              if (_matchesSearch('备份与恢复', '通讯录 / 短信 / 应用数据'))
                                _buildRow(
                                  icon: Icons.backup_outlined,
                                  title: '备份与恢复',
                                  trailing: '通讯录 / 应用数据',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: () =>
                                      _openPage(const DeviceBackupsPage()),
                                ),
                            ], isDark),
                          ),
                          const SizedBox(height: AppTokens.sp4),
                        ],

                        // 3. 关于组
                        if (_matchesSearch('检查更新', _appVersion) ||
                            _matchesSearch('服务协议')) ...[
                          _buildSectionHeader('关于', textMuted),
                          _buildCard(
                            children: _joinWithDividers([
                              if (_matchesSearch('检查更新', _appVersion))
                                _buildRow(
                                  icon: Icons.info_outline_rounded,
                                  title: '检查更新',
                                  trailing: _appVersion != null
                                      ? '$_appVersion(${_appBuildNumber ?? '—'})'
                                      : '—',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: _checkUpdate,
                                ),
                              if (_matchesSearch('服务协议'))
                                _buildRow(
                                  icon: Icons.article_outlined,
                                  title: '服务协议',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  onTap: _showPrivacyNotice,
                                ),
                            ], isDark),
                          ),
                          const SizedBox(height: AppTokens.sp4),
                        ],

                        // 4. 单卡：帮助与反馈
                        if (_matchesSearch('帮助与反馈')) ...[
                          _buildCard(
                            children: [
                              _buildRow(
                                icon: Icons.help_outline_rounded,
                                title: '帮助与反馈',
                                textColor: textColor,
                                textMuted: textMuted,
                                onTap: () => _openPage(const FeedbackPage()),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTokens.sp4),
                        ],

                        // 5. 单卡：清除本地凭证
                        if (_matchesSearch('清除本地凭证'))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('危险操作', AppPalette.danger),
                              _buildCard(children: [
                                _buildRow(
                                  icon: Icons.delete_outline_rounded,
                                  title: '清除本地凭证',
                                  textColor: textColor,
                                  textMuted: textMuted,
                                  danger: true,
                                  semanticHint: '删除已保存的服务商和工具凭证，保留聊天记录',
                                  onTap: () => _confirmLogout(context),
                                ),
                              ]),
                            ],
                          ),

                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesSearch(String title, [String? trailing]) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (trailing != null && trailing.toLowerCase().contains(q)) {
      return true;
    }
    return false;
  }

  bool _hasAnyMatch({
    required String providerText,
    required String themeLabel,
  }) {
    return _matchesSearch('账号管理', providerText) ||
        _matchesSearch('数据管理') ||
        _matchesSearch('语言', _currentLanguage) ||
        _matchesSearch('外观', themeLabel) ||
        _matchesSearch('字体大小', _fontSizeLabel) ||
        _matchesSearch('扩展与环境', 'MCP / 技能 / 工具') ||
        _matchesSearch('设备能力',
            'Root / Magisk / KernelSU / Termux / Linux Runtime / SAF') ||
        _matchesSearch('检查更新', _appVersion) ||
        _matchesSearch('服务协议') ||
        _matchesSearch('帮助与反馈') ||
        _matchesSearch('清除本地凭证');
  }

  List<Widget> _joinWithDividers(List<Widget> items, bool isDark) {
    if (items.isEmpty) return const [];
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) result.add(_buildDivider(isDark));
      result.add(items[i]);
    }
    return result;
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      // T4：标题与卡片内图标对齐（卡片内边距 16），上方多留 8，
      // 分组间距 16 + 8 = 24，组内标题到卡片 8，层级更清楚。
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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

  Widget _buildCard({
    required List<Widget> children,
  }) {
    return SectionCard(
      // T3：分组卡片与消息区卡片统一 16 圆角（只传参，不改 SectionCard）。
      borderRadius: BorderRadius.circular(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildDivider(bool isDark) {
    final isGlass =
        AppAppearanceController.resolvedGlassIntensity != GlassIntensity.flat;
    return Divider(
      height: 0.8,
      thickness: 0.8,
      indent: 48,
      endIndent: 0,
      color: isGlass
          ? (isDark ? const Color(0x1AFFFFFF) : const Color(0x22000000))
          : (isDark ? AppPalette.darkHairline : AppPalette.lightHairline),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    String? trailing,
    required Color textColor,
    required Color textMuted,
    required VoidCallback onTap,
    bool danger = false,
    String? semanticHint,
  }) {
    final stackedValue = trailing != null &&
        trailing.isNotEmpty &&
        (MediaQuery.sizeOf(context).width <= 360 ||
            MediaQuery.textScalerOf(context).scale(14) >= 22);
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        container: true,
        label: title,
        value: trailing,
        hint: semanticHint ?? (danger ? '危险操作，$title' : '打开$title'),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon,
                    size: 20, color: danger ? AppPalette.danger : textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: danger ? AppPalette.danger : textColor,
                        ),
                      ),
                      if (stackedValue) ...[
                        const SizedBox(height: 2),
                        Text(
                          trailing,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTokens.fontSizeSubhead,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null &&
                    trailing.isNotEmpty &&
                    !stackedValue) ...[
                  // T1：值贴右、箭头统一对齐；原先 Flexible 与标题 Expanded
                  // 平分剩余宽度，值会停在行中间。最多占屏宽约 42%，超出省略。
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                    ),
                    child: Text(
                      trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeSubhead,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: textMuted.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
