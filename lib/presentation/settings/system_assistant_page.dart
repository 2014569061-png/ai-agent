import 'package:flutter/material.dart';

import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class SystemAssistantPage extends StatelessWidget {
  const SystemAssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: 'Eta 系统助手',
        subtitle: '选择 Eta 作为默认系统数字助理',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          const SettingsSectionTitle('接管状态'),
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.assistant_rounded,
                iconColor: const Color(0xFFFF9500),
                title: '当前默认助手',
                subtitle: '尚未完成系统级接管 (Beta)',
                showChevron: false,
                trailingWidget: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '未就绪',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF9500),
                    ),
                  ),
                ),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.settings_suggest_rounded,
                iconColor: const Color(0xFF007AFF),
                title: '系统默认助手设置',
                subtitle: '前往 Android「默认应用」>「数字助理」指定 Eta',
                trailingWidget: const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: Color(0xFF8E8E93),
                ),
                onTap: () {
                  FloatingToast.show(
                    context,
                    '系统级接入通道正在适配中，请关注后续版本更新',
                  );
                },
              ),
            ],
          ),
          const SettingsSectionTitle('唤醒与快捷入口'),
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.mic_rounded,
                iconColor: const Color(0xFF5856D6),
                title: '语音热词唤醒',
                subtitle: '离线低功耗热词检测（实验性规划中）',
                showChevron: false,
                trailingWidget: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '规划中',
                    style: TextStyle(
                      fontSize: 11,
                      color: settingsMutedColor(context),
                    ),
                  ),
                ),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.widgets_rounded,
                iconColor: const Color(0xFF34C759),
                title: '桌面快捷小组件',
                subtitle: '在手机桌面上添加快速对话与截屏分析微件',
                onTap: () {
                  FloatingToast.show(
                    context,
                    '长按手机桌面即可添加 NEXUS 快捷微件',
                  );
                },
              ),
            ],
          ),
          const SettingsSectionTitle('接管能力说明'),
          SettingsGroupCard(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '什么是 Eta 系统助手？',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Eta 是深度集成于移动端的自主 Agent 助手。在获得系统助手角色后：\n\n'
                '• 支持从任意应用长按 Home 键或电源键即时呼出；\n'
                '• 支持前台多模态屏幕感知与跨应用任务自动化；\n'
                '• 系统助手执行任何敏感设备能力与数据变更均强制受到审批策略管控。',
                style: TextStyle(
                  height: 1.5,
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
