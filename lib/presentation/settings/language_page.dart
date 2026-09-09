import 'package:flutter/material.dart';
import '../l10n/app_locale_controller.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String _current = 'system';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _current = _codeForLocale(AppLocaleController.locale.value);
      _loading = false;
    });
  }

  String _codeForLocale(Locale? locale) => locale?.languageCode ?? 'system';

  Future<void> _select(String code) async {
    setState(() => _current = code);
    await AppLocaleController.setCode(code);
    if (mounted) {
      FloatingToast.show(
        context,
        code == 'en' ? 'Language switched to English (Partial)' : '语言设置已更新',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '语言 / Language',
        subtitle: '选择应用界面显示语言与多语言支持',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('界面显示语言'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.devices_rounded,
                      iconColor: const Color(0xFF007AFF),
                      title: '跟随系统 (System Default)',
                      subtitle: '优先采用移动操作系统的默认语言设置',
                      selected: _current == 'system',
                      onTap: () => _select('system'),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.translate_rounded,
                      iconColor: const Color(0xFFFF9500),
                      title: '简体中文',
                      subtitle: '完整支持 · 默认语言',
                      selected: _current == 'zh',
                      onTap: () => _select('zh'),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.language_rounded,
                      iconColor: const Color(0xFF34C759),
                      title: 'English',
                      subtitle: 'Partial translation in progress',
                      trailingBadge: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '部分翻译',
                          style: TextStyle(
                            fontSize: 11,
                            color: settingsMutedColor(context),
                          ),
                        ),
                      ),
                      selected: _current == 'en',
                      onTap: () => _select('en'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

