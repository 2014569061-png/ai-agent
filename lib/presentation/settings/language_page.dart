import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import '../l10n/app_locale_controller.dart';
import '../widgets/async_state_view.dart';
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
        code == 'en' ? '语言已切换（English 未完整翻译）' : '语言设置已更新',
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
      body: NexusPageLayout(
          desktopMaxWidth: 920,
          child: AsyncStateView(
            loading: _loading,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('界面显示语言'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.devices_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '跟随系统 (System Default)',
                      subtitle: '优先采用移动操作系统的默认语言设置',
                      selected: _current == 'system',
                      onTap: () => _select('system'),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.translate_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '简体中文',
                      subtitle: '完整支持 · 默认语言',
                      selected: _current == 'zh',
                      onTap: () => _select('zh'),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.language_rounded,
                      iconColor: settingsMutedColor(context),
                      title: 'English',
                      // 此前写的是「Partial translation in progress」，暗示翻译仍在
                      // 推进。已确认不打算完善英文，因此改成陈述事实，避免承诺一件
                      // 不会发生的事。
                      subtitle: '未完整翻译 · 暂不计划完善',
                      selected: _current == 'en',
                      onTap: () => _select('en'),
                    ),
                  ],
                ),
              ],
            ),
          )),
    );
  }
}
