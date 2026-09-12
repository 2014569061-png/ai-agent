import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../infrastructure/background_service.dart';
import '../chat/chat_layout_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme_controller.dart';
import '../theme/app_appearance_controller.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_dropdown.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class AppearanceThemePage extends StatefulWidget {
  const AppearanceThemePage({super.key});

  @override
  State<AppearanceThemePage> createState() => _AppearanceThemePageState();
}

class _AppearanceThemePageState extends State<AppearanceThemePage> {
  static const _adaptiveWidth = 'adaptive';
  static const _compactWidth = 'compact';
  static const _standardWidth = 'standard';
  static const _wideWidth = 'wide';
  static const _customWidth = 'custom';

  final BackgroundService _backgroundService = BackgroundService();
  double _glassIntensity = 0.8;
  String _effectMode = 'full';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _glassIntensity = AppAppearanceController.glassIntensity.value;
      _effectMode = AppAppearanceController.effects.value;
      _loading = false;
    });
  }

  String _widthOption(double widthFactor) {
    if (widthFactor == ChatLayoutController.adaptive) return _adaptiveWidth;
    if (widthFactor == .62) return _compactWidth;
    if (widthFactor == .72) return _standardWidth;
    if (widthFactor == .86) return _wideWidth;
    return _customWidth;
  }

  double _defaultCustomWidth(double widthFactor) =>
      _widthOption(widthFactor) == _customWidth
          ? widthFactor
          : ChatLayoutController.customDefault;

  Future<void> _updateGlass(double val) async {
    setState(() => _glassIntensity = val);
    await AppAppearanceController.setGlass(val);
  }

  Future<void> _updateEffects(String val) async {
    setState(() => _effectMode = val);
    await AppAppearanceController.setEffects(val);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: '外观与主题',
        subtitle: '界面质感 · 动效与聊天视觉定制',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('主题模式'),
                SettingsGroupCard(
                  children: [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: AppThemeController.mode,
                      builder: (context, currentMode, _) {
                        return Column(
                          children: [
                            SettingsTile(
                              icon: Icons.brightness_auto_rounded,
                              iconColor: settingsMutedColor(context),
                              title: '跟随系统',
                              subtitle: '根据系统深浅色外观自动切换',
                              selected: currentMode == ThemeMode.system,
                              onTap: () =>
                                  AppThemeController.setMode(ThemeMode.system),
                            ),
                            const SettingsDivider(),
                            SettingsTile(
                              icon: Icons.light_mode_rounded,
                              iconColor: AppPalette.warning,
                              title: '浅色模式',
                              subtitle: '清新明亮的白蓝质感',
                              selected: currentMode == ThemeMode.light,
                              onTap: () =>
                                  AppThemeController.setMode(ThemeMode.light),
                            ),
                            const SettingsDivider(),
                            SettingsTile(
                              icon: Icons.dark_mode_rounded,
                              iconColor: settingsMutedColor(context),
                              title: '深色模式',
                              subtitle: '深邃专注的纯黑沉浸感',
                              selected: currentMode == ThemeMode.dark,
                              onTap: () =>
                                  AppThemeController.setMode(ThemeMode.dark),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SettingsSectionTitle('视觉与动效表现'),
                SettingsGroupCard(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('毛玻璃模糊强度',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(
                          '${(_glassIntensity * 100).round()}%',
                          style: const TextStyle(
                            color: AppPalette.brand,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _glassIntensity,
                      min: 0.2,
                      max: 1.0,
                      divisions: 8,
                      onChanged: _updateGlass,
                    ),
                    const Divider(height: 16),
                    const Text('动效等级',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(1.0);
                        if (textScale > 1.15 || constraints.maxWidth < 310) {
                          return Column(
                            children: [
                              _buildEffectOption('full', '完整动效', '沉浸式流体动画与转场'),
                              const SizedBox(height: 6),
                              _buildEffectOption(
                                  'reduced', '节能平滑', '减少大面积缩放与模糊'),
                              const SizedBox(height: 6),
                              _buildEffectOption('off', '关闭动效', '即时切换，性能最优'),
                            ],
                          );
                        }
                        return SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'full', label: Text('完整动效')),
                            ButtonSegment(
                                value: 'reduced', label: Text('节能平滑')),
                            ButtonSegment(value: 'off', label: Text('关闭动效')),
                          ],
                          selected: {_effectMode},
                          onSelectionChanged: (s) => _updateEffects(s.first),
                        );
                      },
                    ),
                  ],
                ),
                const SettingsSectionTitle('聊天气泡布局'),
                SettingsGroupCard(
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: ChatLayoutController.widthFactor,
                      builder: (context, widthFactor, _) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ImmersiveDropdown<String>(
                              key: ValueKey(_widthOption(widthFactor)),
                              labelText: '对话气泡宽度模式',
                              initialValue: _widthOption(widthFactor),
                              items: const [
                                DropdownMenuItem(
                                    value: _adaptiveWidth,
                                    child: Text('自适应屏幕')),
                                DropdownMenuItem(
                                    value: _compactWidth,
                                    child: Text('紧凑 (62%)')),
                                DropdownMenuItem(
                                    value: _standardWidth,
                                    child: Text('标准 (72%)')),
                                DropdownMenuItem(
                                    value: _wideWidth, child: Text('宽松 (86%)')),
                                DropdownMenuItem(
                                    value: _customWidth, child: Text('自定义比例')),
                              ],
                              onChanged: (selection) {
                                if (selection == null) return;
                                final value = switch (selection) {
                                  _adaptiveWidth =>
                                    ChatLayoutController.adaptive,
                                  _compactWidth => .62,
                                  _standardWidth => .72,
                                  _wideWidth => .86,
                                  _ => _defaultCustomWidth(widthFactor),
                                };
                                ChatLayoutController.setWidthFactor(value);
                              },
                            ),
                            if (_widthOption(widthFactor) == _customWidth) ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('自定义气泡最大宽度比例'),
                                  Text(
                                    '${(widthFactor * 100).round()}%',
                                    style: const TextStyle(
                                      color: AppPalette.brand,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: widthFactor
                                    .clamp(ChatLayoutController.customMin,
                                        ChatLayoutController.customMax)
                                    .toDouble(),
                                min: ChatLayoutController.customMin,
                                max: ChatLayoutController.customMax,
                                divisions: 10,
                                label: '${(widthFactor * 100).round()}%',
                                onChanged:
                                    ChatLayoutController.updateWidthFactor,
                                onChangeEnd:
                                    ChatLayoutController.setWidthFactor,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SettingsSectionTitle('聊天背景'),
                SettingsGroupCard(
                  children: [
                    FutureBuilder<BackgroundConfig>(
                      future: _backgroundService.load(),
                      builder: (context, snapshot) {
                        final current = snapshot.data ??
                            const BackgroundConfig(mode: 'default');

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.preview_rounded,
                                        size: 16,
                                        color: settingsMutedColor(context),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '真实效果预览',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: settingsMutedColor(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildChatPreview(current),
                                ],
                              ),
                            ),
                            const SettingsDivider(),
                            SettingsTile(
                              icon: Icons.wallpaper_rounded,
                              iconColor: settingsMutedColor(context),
                              title: '默认（跟随主题）',
                              subtitle: '极简纯色纯净底色，与顶栏完全融为一体',
                              selected: current.mode == 'default',
                              onTap: () async {
                                await _backgroundService.setMode('default');
                                if (mounted) setState(() {});
                              },
                            ),
                            const SettingsDivider(),
                            SettingsTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Image.asset(
                                    BackgroundService.cloudsAsset,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              title: '云朵栈桥',
                              subtitle: '内置梦幻艺术插画背景',
                              selected: current.mode == 'clouds',
                              onTap: () async {
                                await _backgroundService.setMode('clouds');
                                if (mounted) setState(() {});
                              },
                            ),
                            const SettingsDivider(),
                            SettingsTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: (current.mode == 'custom' &&
                                          current.customPath != null)
                                      ? Image.file(
                                          File(current.customPath!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 16),
                                        )
                                      : const Icon(Icons.image_outlined,
                                          size: 16),
                                ),
                              ),
                              title: '自定义相册图片',
                              subtitle: current.mode == 'custom'
                                  ? '当前已使用自定义背景（点击更换）'
                                  : '从手机相册挑选个性化图片',
                              selected: current.mode == 'custom',
                              onTap: () async {
                                try {
                                  final x = await ImagePicker()
                                      .pickImage(source: ImageSource.gallery);
                                  if (x == null) return;
                                  await _backgroundService
                                      .setCustomBackground(x.path);
                                  if (mounted) setState(() {});
                                } catch (_) {
                                  if (!context.mounted) return;
                                  FloatingToast.show(context, '选图失败，请重试');
                                }
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildEffectOption(String value, String title, String subtitle) {
    final isSelected = _effectMode == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _updateEffects(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppPalette.brandAction
                  : (isDark
                      ? AppPalette.darkHairline
                      : AppPalette.lightHairline),
              width: isSelected ? 1.5 : 1.0,
            ),
            color: isSelected
                ? (isDark
                    ? AppPalette.darkBrandSoft
                    : AppPalette.lightBrandSoft)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected
                            ? AppPalette.brandAction
                            : (isDark
                                ? AppPalette.darkText
                                : AppPalette.lightText),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: settingsMutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppPalette.brandAction,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatPreview(BackgroundConfig config) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    Widget backgroundWidget;
    if (config.mode == 'clouds') {
      backgroundWidget = Image.asset(
        BackgroundService.cloudsAsset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (config.mode == 'custom' && config.customPath != null) {
      backgroundWidget = Image.file(
        File(config.customPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(
            color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface),
      );
    } else {
      backgroundWidget = Container(
        color: isDark ? AppPalette.darkCanvas : AppPalette.lightSurface,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 136,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
            width: 0.8,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: backgroundWidget),
            Positioned.fill(
              child: Container(
                color: (isDark ? Colors.black : Colors.white)
                    .withValues(alpha: 0.18),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF222938)
                            : const Color(0xFFE5ECF6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '你好，请帮我分析项目进度',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF161B26).withValues(alpha: 0.88)
                            : Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 11, color: AppPalette.brand),
                              const SizedBox(width: 4),
                              Text(
                                'NEXUS',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '已就绪，当前有 3 个待办任务。',
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
