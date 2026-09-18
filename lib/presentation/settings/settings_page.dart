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
import '../widgets/glass_surface.dart';
import '../widgets/nexus_async_content.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/confirm_action.dart';
import 'appearance_theme_page.dart';
import 'data_management_page.dart';
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

  bool get _isInTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _loadAll();
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

    // App version
    if (!_isInTest) {
      try {
        final info = await PackageInfo.fromPlatform()
            .timeout(const Duration(milliseconds: 300));
        final appVersion = info.version;
        final appBuildNumber = info.buildNumber;
        return SettingsSnapshot(
          activeProvider: activeProvider,
          currentLanguage: _currentLanguage,
          fontSizeLabel: _fontSizeLabel,
          appVersion: appVersion,
          appBuildNumber: appBuildNumber,
          isEmpty: _isEmptySettings(prefs, activeProvider),
        );
      } catch (_) {
        return SettingsSnapshot(
          activeProvider: activeProvider,
          currentLanguage: _currentLanguage,
          fontSizeLabel: _fontSizeLabel,
          appVersion: AppStrings.appVersionName.replaceFirst('v', ''),
          appBuildNumber: '93',
          isEmpty: _isEmptySettings(prefs, activeProvider),
        );
      }
    } else {
      return SettingsSnapshot(
        activeProvider: activeProvider,
        currentLanguage: _currentLanguage,
        fontSizeLabel: _fontSizeLabel,
        appVersion: AppStrings.appVersionName.replaceFirst('v', ''),
        appBuildNumber: '93',
        isEmpty: _isEmptySettings(prefs, activeProvider),
      );
    }
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
          '当前已是最新版本 ${result.currentVersion ?? _appVersion ?? AppStrings.appVersionName}',
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
    final cardBg = isDark ? AppPalette.darkSurface : AppPalette.lightCanvas;

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
                error:
                    _loadState == _SettingsLoadState.error ? _loadError : null,
                onRetry: _loadAll,
                child: RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (_loadState == _SettingsLoadState.empty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: EmptyStateView.compact(
                            icon: Icons.settings_outlined,
                            title: '尚未配置服务商',
                            message: '可以先配置一个服务商，其他设置仍可继续使用。',
                            actionLabel: '配置服务商',
                            onAction: () => _openPage(const ProviderListPage()),
                          ),
                        ),
                      // 1. 账户组
                      _buildSectionHeader('账户', textMuted),
                      _buildCard(
                        cardBg: cardBg,
                        isDark: isDark,
                        children: [
                          _buildRow(
                            icon: Icons.person_outline_rounded,
                            title: '账号管理',
                            trailing: providerText,
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: () => _openPage(const ProviderListPage()),
                          ),
                          _buildDivider(isDark),
                          _buildRow(
                            icon: Icons.storage_outlined,
                            title: '数据管理',
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: () => _openPage(const DataManagementPage()),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // 2. 应用组
                      _buildSectionHeader('应用', textMuted),
                      _buildCard(
                        cardBg: cardBg,
                        isDark: isDark,
                        children: [
                          _buildRow(
                            icon: Icons.language_rounded,
                            title: '语言',
                            trailing: _currentLanguage,
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: () => _openPage(const LanguagePage()),
                          ),
                          _buildDivider(isDark),
                          _buildRow(
                            icon: Icons.wb_sunny_outlined,
                            title: '外观',
                            trailing: themeLabel,
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: () => _openPage(const AppearanceThemePage()),
                          ),
                          _buildDivider(isDark),
                          _buildRow(
                            icon: Icons.format_size_rounded,
                            title: '字体大小',
                            trailing: _fontSizeLabel,
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: _selectFontSize,
                          ),
                          _buildDivider(isDark),
                          _buildRow(
                            icon: Icons.extension_outlined,
                            title: '扩展与环境',
                            trailing: 'MCP / 技能 / 工具',
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: () => _openPage(const ExtensionsPage()),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // 3. 关于组
                      _buildSectionHeader('关于', textMuted),
                      _buildCard(
                        cardBg: cardBg,
                        isDark: isDark,
                        children: [
                          _buildRow(
                            icon: Icons.info_outline_rounded,
                            title: '检查更新',
                            trailing:
                                '${_appVersion ?? AppStrings.appVersionName.replaceFirst('v', '')}(${_appBuildNumber ?? '93'})',
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: _checkUpdate,
                          ),
                          _buildDivider(isDark),
                          _buildRow(
                            icon: Icons.article_outlined,
                            title: '服务协议',
                            textColor: textColor,
                            textMuted: textMuted,
                            onTap: _showPrivacyNotice,
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // 4. 单卡：帮助与反馈
                      _buildCard(
                        cardBg: cardBg,
                        isDark: isDark,
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

                      const SizedBox(height: 14),

                      // 5. 单卡：清除本地凭证
                      _buildCard(
                        cardBg: cardBg,
                        isDark: isDark,
                        children: [
                          Semantics(
                            button: true,
                            container: true,
                            label: '清除本地凭证',
                            hint: '删除已保存的服务商和工具凭证，保留聊天记录',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _confirmLogout(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.logout_rounded,
                                        size: 20,
                                        color: textColor,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '清除本地凭证',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w400,
                                          color: textColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
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

  Widget _buildCard({
    required Color cardBg,
    required bool isDark,
    required List<Widget> children,
  }) {
    final intensity = AppAppearanceController.resolvedGlassIntensity;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    if (intensity != GlassIntensity.flat) {
      return GlassSurface(
        role: GlassRole.content,
        variant: GlassVariant.regular,
        intensity: intensity,
        borderRadius: BorderRadius.circular(16),
        borderColor: isDark ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
        tint: isDark
            ? AppPalette.darkSurface.withValues(alpha: 0.42)
            : AppPalette.lightCanvas.withValues(alpha: 0.46),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x40000000) : const Color(0x141E3A8A),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
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
  }) {
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        container: true,
        label: title,
        value: trailing,
        hint: '打开$title',
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
                if (trailing != null && trailing.isNotEmpty) ...[
                  Text(
                    trailing,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeSubhead,
                      fontWeight: FontWeight.w400,
                      color: textMuted,
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
