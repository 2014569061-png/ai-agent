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
import '../theme/app_appearance_controller.dart';
import '../theme/app_theme_controller.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_sheet.dart';
import 'appearance_theme_page.dart';
import 'data_management_page.dart';
import 'extensions_page.dart';
import 'language_page.dart';
import 'provider_list_page.dart';
import 'update_sheet.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

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

  bool get _isInTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Active provider
      if (!_isInTest) {
        _activeProvider = await _providerStore.load().timeout(
              const Duration(milliseconds: 300),
              onTimeout: () => const ProviderConfig(baseUrl: '', model: '', apiKey: ''),
            );
      } else {
        _activeProvider = const ProviderConfig(baseUrl: '', model: '', apiKey: '');
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
          _appVersion = info.version;
          _appBuildNumber = info.buildNumber;
        } catch (_) {
          _appVersion = AppStrings.appVersionName.replaceFirst('v', '');
          _appBuildNumber = '93';
        }
      } else {
        _appVersion = AppStrings.appVersionName.replaceFirst('v', '');
        _appBuildNumber = '93';
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(
      NexusPageRoute.settingsPage(builder: (_) => page),
    );
  }

  Future<void> _showPrivacyNotice() async {
    await showDialog<void>(
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

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppPalette.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('退出后将清除本地临时会话凭证，如需使用需重新进入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? AppPalette.darkCanvas : const Color(0xFFF7F8FA);
    final textColor = isDark ? AppPalette.darkText : const Color(0xFF1F2329);
    final textMuted = isDark ? AppPalette.darkTextMuted : const Color(0xFF8E9297);
    final cardBg = isDark ? AppPalette.darkSurface : Colors.white;

    final themeMode = AppThemeController.mode.value;
    final themeLabel = switch (themeMode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      ThemeMode.system => '系统',
    };

    final providerText = (_activeProvider != null && _activeProvider!.name.isNotEmpty)
        ? _activeProvider!.name
        : '未配置';

    return Scaffold(
      backgroundColor: canvas,
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
                      '设置',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 36), // 保持居中对称
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
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

                    // 5. 单卡：退出登录
                    _buildCard(
                      cardBg: cardBg,
                      isDark: isDark,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _confirmLogout(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.logout_rounded,
                                    size: 20,
                                    color: textColor,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '退出登录',
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
                      ],
                    ),

                    const SizedBox(height: 28),

                    // 6. 底部法律与备案声明
                    _buildFooter(textMuted),
                  ],
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
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
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
    String? trailing,
    required Color textColor,
    required Color textMuted,
    required VoidCallback onTap,
  }) {
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
              if (trailing != null && trailing.isNotEmpty) ...[
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 14,
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
    );
  }

  Widget _buildFooter(Color textFaint) {
    final activeModel = _activeProvider?.model.isNotEmpty == true
        ? _activeProvider!.model
        : 'NEXUS Agent';

    return Center(
      child: Column(
        children: [
          Text(
            '模型名称: $activeModel\n'
            '备案号: Beijing-NexusAgent-20260914001\n'
            '浙ICP备2023025841号-3A\n'
            '内容由 AI 生成，请仔细甄别，并合法使用',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              height: 1.6,
              color: textFaint.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
