import 'dart:async';

import '../theme/app_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/environment_service.dart';
import '../chat/widgets/environment_sheet.dart';
import '../environment/environment_status_view.dart';
import '../diagnostics/log_viewer_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../theme/app_tokens.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';

class LinuxEnvironmentPage extends ConsumerStatefulWidget {
  const LinuxEnvironmentPage({
    super.key,
    this.environmentService,
    this.preferencesLoader,
    this.preferencesTimeout = const Duration(seconds: 2),
    this.environmentCheckTimeout = const Duration(seconds: 10),
  });

  /// Test seam; production callers continue to use the Riverpod provider.
  final EnvironmentService? environmentService;

  /// Test seam for storage initialization failures.
  final Future<SharedPreferences> Function()? preferencesLoader;
  final Duration preferencesTimeout;
  final Duration environmentCheckTimeout;

  @override
  ConsumerState<LinuxEnvironmentPage> createState() =>
      _LinuxEnvironmentPageState();
}

class _LinuxEnvironmentPageState extends ConsumerState<LinuxEnvironmentPage> {
  static const _workDirKey = 'settings.linux.default_work_dir';
  static const _shellTypeKey = 'settings.linux.shell_type';

  bool _loading = true;
  String _shellType = 'bash';
  String _defaultWorkDir = '/data/data/com.termux/files/home';
  String _diagnosticSummary = '未检测';
  EnvironmentSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await (widget.preferencesLoader?.call() ??
              SharedPreferences.getInstance())
          .timeout(widget.preferencesTimeout);
      if (!mounted) return;
      _shellType = prefs.getString(_shellTypeKey) ?? 'bash';
      _defaultWorkDir = prefs.getString(_workDirKey) ??
          (kIsWeb ? '/workspace' : '/data/data/com.termux/files/home');

      await _checkEnvironment();
    } on TimeoutException {
      _finishLoading(
          '偏好设置读取超时（${_formatTimeout(widget.preferencesTimeout)}），请重试。');
    } catch (error) {
      _finishLoading('偏好设置读取失败：$error');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _checkEnvironment() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final EnvironmentService service =
          widget.environmentService ?? ref.read(environmentServiceProvider);
      service.invalidate();
      final snapshot = await service
          .inspect(force: true)
          .timeout(widget.environmentCheckTimeout);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _diagnosticSummary = snapshot.scenarioLabel;
        _loading = false;
      });
    } on TimeoutException {
      _finishLoading(
          '环境检测超时（${_formatTimeout(widget.environmentCheckTimeout)}）；'
          '请打开 Termux、检查桥授权后重试。');
    } catch (error) {
      _finishLoading('检测出错：$error');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  void _finishLoading(String diagnostic) {
    if (!mounted) return;
    setState(() {
      _diagnosticSummary = diagnostic;
      _loading = false;
    });
  }

  String _formatTimeout(Duration timeout) {
    if (timeout.inMilliseconds < 1000) return '${timeout.inMilliseconds}ms';
    return '${timeout.inSeconds}s';
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
        if (!mounted) return;
        setState(() => _defaultWorkDir = text);
        FloatingToast.show(context, '工作目录已更新');
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
      if (!mounted) return;
      setState(() => _shellType = chosen);
      FloatingToast.show(context, 'Shell 类型已更新为 $chosen');
    }
  }

  Future<void> _reinitialize() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新初始化环境？'),
        content: const Text('将清空环境缓存并重新检查四个运行时。'),
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
    showNexusSheet(
      context: context,
      builder: (_) => const EnvironmentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final ready = snapshot?.selected.available == true;
    final bridgeColor = kIsWeb
        ? AppPalette.lightTextMuted
        : (ready ? AppPalette.success : AppPalette.warning);
    final bridgeText = kIsWeb ? '仅预览' : (ready ? '已连接' : '待配置');

    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: const NexusPageHeader(
        title: 'Linux 工具环境',
        subtitle: 'Termux · proot · 宿主终端交互管理',
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: NexusListSkeleton(itemCount: 4),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
              children: [
                const SettingsSectionTitle('运行环境状态'),
                SettingsGroupCard(
                  children: [
                    SettingsTile(
                      icon: Icons.terminal_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '当前运行环境',
                      subtitle: kIsWeb
                          ? 'Web Sandbox'
                          : (snapshot?.summary ?? '尚未检测'),
                      trailingBadge: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: bridgeColor.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusControl),
                        ),
                        child: Text(
                          bridgeText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: bridgeColor,
                          ),
                        ),
                      ),
                      showChevron: false,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.health_and_safety_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '环境状态诊断',
                      subtitle: _diagnosticSummary,
                      trailingWidget: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: '重新检测',
                        onPressed: _checkEnvironment,
                      ),
                    ),
                    if (snapshot != null) ...[
                      const SettingsDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: EnvironmentStatusView(
                          snapshot: snapshot,
                          compact: true,
                        ),
                      ),
                    ],
                    if (snapshot == null && !kIsWeb)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text(
                          '检测超时或平台桥不可用。请先打开 Termux，配置 '
                          'allow-external-apps，并允许后台运行后重试。',
                        ),
                      ),
                    if (!kIsWeb && snapshot?.termuxAvailable != true) ...[
                      const SettingsDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openSetupGuide,
                            icon: const Icon(Icons.settings_suggest_rounded,
                                size: 18),
                            label: Text(snapshot?.alpineAvailable == true
                                ? '去补充 Termux 工具链'
                                : '去配置运行环境'),
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
                      iconColor: AppPalette.warning,
                      title: '默认工作目录',
                      subtitle: _defaultWorkDir,
                      onTap: _editWorkDir,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.code_rounded,
                      iconColor: settingsMutedColor(context),
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
                      iconColor: AppPalette.success,
                      title: '环境检测与安装引导',
                      subtitle: '检测 Alpine / Termux / Android Shell / 本机进程',
                      onTap: _openSetupGuide,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      iconColor: AppPalette.warning,
                      title: '重新初始化环境',
                      subtitle: '重设桥接状态并执行环境重新连接',
                      onTap: _reinitialize,
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: Icons.receipt_long_rounded,
                      iconColor: settingsMutedColor(context),
                      title: '查看诊断日志',
                      subtitle: '查看终端与工具执行的详细运行记录',
                      onTap: () {
                        Navigator.push(
                          context,
                          NexusPageRoute.detail(
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
