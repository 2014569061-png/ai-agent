import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/widgets/environment_sheet.dart';
import '../diagnostics/log_viewer_page.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class LinuxEnvironmentPage extends StatefulWidget {
  const LinuxEnvironmentPage({super.key});

  @override
  State<LinuxEnvironmentPage> createState() => _LinuxEnvironmentPageState();
}

class _LinuxEnvironmentPageState extends State<LinuxEnvironmentPage> {
  static const _bridge = MethodChannel('nexus/termux_bridge');
  static const _workDirKey = 'settings.linux.default_work_dir';
  static const _shellTypeKey = 'settings.linux.shell_type';

  bool _loading = true;
  bool _termuxInstalled = false;
  bool _bridgeAvailable = false;
  String _shellType = 'bash';
  String _defaultWorkDir = '/data/data/com.termux/files/home';
  String _diagnosticSummary = '未检测';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _shellType = prefs.getString(_shellTypeKey) ?? 'bash';
    _defaultWorkDir = prefs.getString(_workDirKey) ??
        (kIsWeb ? '/workspace' : '/data/data/com.termux/files/home');

    await _checkEnvironment();
  }

  Future<void> _checkEnvironment() async {
    setState(() => _loading = true);
    if (kIsWeb) {
      setState(() {
        _termuxInstalled = false;
        _bridgeAvailable = false;
        _diagnosticSummary = 'Web 预览环境（不支持底层 Linux 运行时）';
        _loading = false;
      });
      return;
    }

    try {
      bool installed = false;
      try {
        installed = await _bridge.invokeMethod('isTermuxInstalled') == true;
      } catch (_) {}

      bool bridgeOk = false;
      if (installed) {
        try {
          final res = await _bridge.invokeMethod<Map>('execute', {
            'command': 'echo bridge-ok',
            'timeoutMs': 5000,
          });
          bridgeOk = res?['exitCode'] == 0;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _termuxInstalled = installed;
          _bridgeAvailable = bridgeOk;
          _diagnosticSummary = installed
              ? (bridgeOk ? 'Termux 桥接已连接，环境正常' : 'Termux 已安装，但外部应用调用未授权')
              : 'Termux 尚未安装';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _diagnosticSummary = '检测出错：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editWorkDir() async {
    final controller = TextEditingController(text: _defaultWorkDir);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改默认工作目录'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/data/data/com.termux/files/home',
            labelText: '工作目录绝对路径',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final text = controller.text.trim();
      if (text.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_workDirKey, text);
        setState(() => _defaultWorkDir = text);
        if (mounted) FloatingToast.show(context, '工作目录已更新');
      }
    }
  }

  Future<void> _chooseShell() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择 Shell 类型'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'bash'),
            child: const Text('bash (默认，推荐)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'zsh'),
            child: const Text('zsh (支持高度自定义)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'sh'),
            child: const Text('sh (标准 POSIX 基础 Shell)'),
          ),
        ],
      ),
    );

    if (chosen != null && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_shellTypeKey, chosen);
      setState(() => _shellType = chosen);
      if (mounted) FloatingToast.show(context, 'Shell 类型已更新为 $chosen');
    }
  }

  Future<void> _reinitialize() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新初始化环境？'),
        content: const Text('将重置环境检测状态并重新触发 Termux 桥接握手。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _checkEnvironment();
      if (mounted) FloatingToast.show(context, '环境检测与握手已重新执行');
    }
  }

  void _openSetupGuide() {
    showImmersiveSheet(
      context: context,
      builder: (_) => const EnvironmentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridgeColor = kIsWeb
        ? const Color(0xFF8E8E93)
        : (_bridgeAvailable
            ? const Color(0xFF34C759)
            : const Color(0xFFFF9500));
    final bridgeText = kIsWeb
        ? '仅预览'
        : (_bridgeAvailable ? '已连接' : '待配置');

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: 'Linux 工具环境',
        subtitle: 'Termux · proot · 宿主终端交互管理',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('运行环境状态'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.terminal_rounded,
                      iconColor: const Color(0xFF48484A),
                      title: '当前运行环境',
                      subtitle: kIsWeb
                          ? 'Web Sandbox'
                          : (_termuxInstalled
                              ? 'Termux / Android Shell'
                              : '未安装 Termux 环境'),
                      trailingBadge: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: bridgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          bridgeText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: bridgeColor,
                          ),
                        ),
                      ),
                      showChevron: false,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.health_and_safety_rounded,
                      iconColor: const Color(0xFF007AFF),
                      title: '环境状态诊断',
                      subtitle: _diagnosticSummary,
                      trailingWidget: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: '重新检测',
                        onPressed: _checkEnvironment,
                      ),
                    ),
                    if (!kIsWeb && !_bridgeAvailable) ...[
                      const SettingsDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openSetupGuide,
                            icon: const Icon(
                                Icons.settings_suggest_rounded, size: 18),
                            label: Text(_termuxInstalled
                                ? '去配置：授权 Termux 外部调用'
                                : '去配置：安装 Termux'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SettingsSectionTitle('环境参数设置'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.folder_rounded,
                      iconColor: const Color(0xFFFF9F0A),
                      title: '默认工作目录',
                      subtitle: _defaultWorkDir,
                      onTap: _editWorkDir,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.code_rounded,
                      iconColor: const Color(0xFF5856D6),
                      title: 'Shell 类型',
                      trailingText: _shellType,
                      onTap: _chooseShell,
                    ),
                  ],
                ),
                const SettingsSectionTitle('环境运维与检测'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.play_circle_filled_rounded,
                      iconColor: const Color(0xFF34C759),
                      title: '环境检测与安装引导',
                      subtitle: '分步检测 Termux、桥授权与 Go 工具链',
                      onTap: _openSetupGuide,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      iconColor: const Color(0xFFFF9500),
                      title: '重新初始化环境',
                      subtitle: '重设桥接状态并执行环境重新连接',
                      onTap: _reinitialize,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.receipt_long_rounded,
                      iconColor: const Color(0xFF636366),
                      title: '查看诊断日志',
                      subtitle: '查看终端与工具执行的详细运行记录',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LogViewerPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
