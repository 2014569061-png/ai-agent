import 'dart:async';

import '../theme/app_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/development_target.dart';
import '../../application/environment_service.dart';
import '../../application/project_kind_detector.dart';
import '../chat/widgets/environment_sheet.dart';
import '../environment/environment_status_view.dart';
import '../diagnostics/log_viewer_page.dart';
import '../motion/nexus_page_route_factory.dart';
import '../theme/app_tokens.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/confirm_action.dart';
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
  bool _showFullInventory = false;
  DevelopmentTarget _target = DevelopmentTarget.staticWeb;
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
      final storedTarget = DevelopmentTargetX.parse(
        prefs.getString(DevelopmentTargetX.storageKey),
      );
      if (storedTarget != null) _target = storedTarget;
      await _detectWorkspaceTarget();
      // The runtime probe still runs in the background so changing the target
      // later is instant. The UI only exposes the selected target by default.
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

  Future<void> _detectWorkspaceTarget() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final workspace = prefs.getString('active_workspace_path');
      if (workspace == null || workspace.trim().isEmpty) return;
      final detection = await const ProjectKindDetector().detect(workspace);
      final detectedTarget = DevelopmentTargetX.fromProjectKind(detection.kind);
      if (detectedTarget == null || !mounted) return;
      // A manually selected target wins over a project guess once persisted.
      if (prefs.getString(DevelopmentTargetX.storageKey) == null) {
        setState(() => _target = detectedTarget);
      }
    } catch (_) {}
  }

  Future<void> _selectTarget() async {
    final chosen = await showNexusDialog<DevelopmentTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择开发目标'),
        children: [
          for (final target in DevelopmentTarget.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, target),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_targetIcon(target)),
                title: Text(target.label),
                subtitle: Text(target.description),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DevelopmentTargetX.storageKey, chosen.id);
    setState(() => _target = chosen);
  }

  IconData _targetIcon(DevelopmentTarget target) => switch (target) {
        DevelopmentTarget.staticWeb => Icons.web_rounded,
        DevelopmentTarget.nodeWeb => Icons.javascript_rounded,
        DevelopmentTarget.python => Icons.code_rounded,
        DevelopmentTarget.go => Icons.data_object_rounded,
        DevelopmentTarget.flutterAndroid => Icons.flutter_dash_rounded,
        DevelopmentTarget.androidNative => Icons.android_rounded,
        DevelopmentTarget.windowsExe => Icons.desktop_windows_rounded,
      };

  Set<String> get _targetToolIds =>
      _target.tools.map((tool) => tool.id).toSet();

  List<EnvironmentToolStatus> get _targetTools {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    return snapshot.tools
        .where((tool) => _targetToolIds.contains(tool.id))
        .toList(growable: false);
  }

  bool get _targetReady {
    if (!_target.canBuildHere) return false;
    return _target.tools.where((tool) => tool.required).every((required) =>
        _targetTools
            .any((actual) => actual.id == required.id && actual.available));
  }

  bool get _targetHasInstallableMissingTool {
    final actual = {for (final tool in _targetTools) tool.id: tool};
    return _target.tools.any((tool) =>
        tool.required &&
        actual[tool.id]?.available != true &&
        tool.canInstallOnLinux);
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
    final confirmed = await showNexusDialog<bool>(
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
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

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
    final chosen = await showNexusDialog<String>(
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
    final ok = await showConfirmAction(
      context,
      title: '重新初始化环境？',
      message: '将清空环境缓存并重新检查四个运行时。',
      confirmLabel: '确认重置',
      isDanger: true,
    );
    if (ok) {
      await _checkEnvironment();
      if (mounted) FloatingToast.show(context, '环境检测与握手已重新执行');
    }
  }

  void _openSetupGuide() {
    showNexusSheet(
      context: context,
      builder: (_) => EnvironmentSheet(target: _target),
    );
  }

  Future<void> _openTargetHelp() async {
    if (_target == DevelopmentTarget.windowsExe) {
      await showNexusDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Windows .exe 构建说明'),
          content: const Text(
            '手机上的 Alpine / Termux 可以编辑源码和运行部分跨平台工具，\n\n'
            '但不能把 Windows 专用运行库、MSVC 或 Windows SDK 当成本机工具链。\n\n'
            'Electron / Tauri / Python / Go 项目建议在 Windows 电脑上安装对应工具链并完成最终打包；本应用可以继续帮你编写和审查项目文件。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    _openSetupGuide();
  }

  String get _targetStatusText {
    if (_target == DevelopmentTarget.staticWeb) {
      return '无需安装编译器，可直接创建和预览 HTML / CSS / JS';
    }
    if (_target == DevelopmentTarget.windowsExe) {
      return '不能在手机 Linux 环境直接生成 Windows .exe';
    }
    final snapshot = _snapshot;
    if (snapshot == null) return '等待环境检测完成';
    if (!snapshot.selected.available) return '暂无可用 Linux 运行时，文件编辑仍可继续';
    if (_targetReady) return '当前目标所需工具已就绪';
    if (_targetHasInstallableMissingTool) {
      final actual = {for (final tool in _targetTools) tool.id: tool};
      final missing = _target.tools
          .where((tool) => tool.required && actual[tool.id]?.available != true)
          .map((tool) => tool.label)
          .join('、');
      return '缺少 $missing，可按需安装';
    }
    return '需要外部 SDK 或对应宿主机工具链';
  }

  Color get _targetStatusColor {
    if (_target == DevelopmentTarget.staticWeb || _targetReady) {
      return AppPalette.success;
    }
    if (_target == DevelopmentTarget.windowsExe ||
        !_target.canBuildHere ||
        _targetHasInstallableMissingTool) {
      return AppPalette.warning;
    }
    return AppPalette.danger;
  }

  bool get _showTargetSetup {
    if (kIsWeb || _target == DevelopmentTarget.staticWeb) return false;
    final snapshot = _snapshot;
    return !_target.canBuildHere ||
        snapshot?.selected.available != true ||
        _targetHasInstallableMissingTool;
  }

  bool get _showRuntimeDetails =>
      _showFullInventory || _target != DevelopmentTarget.staticWeb;

  Widget _runtimeRetryCard(BuildContext context) {
    final diagnostic =
        _diagnosticSummary == '未检测' ? '静态网页无需运行时；仍可随时手动检测' : _diagnosticSummary;
    return SettingsGroupCard(
      children: [
        SettingsTile(
          icon: Icons.health_and_safety_rounded,
          iconColor: settingsMutedColor(context),
          title: '运行时检测（可选）',
          subtitle: diagnostic,
          trailingWidget: IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '重新检测',
            onPressed: _checkEnvironment,
          ),
        ),
        if (_snapshot == null && !kIsWeb)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '检测超时或平台桥不可用。请先打开 Termux，配置 '
              'allow-external-apps，并允许后台运行后重试。',
            ),
          ),
      ],
    );
  }

  Widget _targetCard(BuildContext context) {
    final statusColor = _targetStatusColor;
    return SettingsGroupCard(
      children: [
        SettingsTile(
          icon: _targetIcon(_target),
          iconColor: settingsMutedColor(context),
          title: '当前开发目标',
          subtitle: '${_target.label} · ${_target.description}',
          trailingText: '更改',
          onTap: _selectTarget,
        ),
        const SettingsDivider(),
        SettingsTile(
          icon: Icons.fact_check_outlined,
          iconColor: statusColor,
          title: '目标检查结果',
          subtitle: _targetStatusText,
          showChevron: false,
          trailingBadge: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            ),
            child: Text(
              _target == DevelopmentTarget.staticWeb
                  ? '无需安装'
                  : _targetReady
                      ? '已就绪'
                      : '按需配置',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            _target.environmentNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SettingsDivider(),
        SettingsTile(
          icon: Icons.manage_search_rounded,
          iconColor: settingsMutedColor(context),
          title: '查看完整环境清单',
          subtitle: _showFullInventory
              ? '显示所有运行时和工具（高级诊断）'
              : '只显示当前目标相关工具，避免误以为都必须安装',
          showChevron: false,
          trailingWidget: Switch(
            value: _showFullInventory,
            onChanged: (value) => setState(() => _showFullInventory = value),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final ready = snapshot?.selected.available == true;
    final needsCommonTools = _targetHasInstallableMissingTool;
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
                const SettingsSectionTitle('开发目标'),
                _targetCard(context),
                if (_showRuntimeDetails) const SettingsSectionTitle('运行环境状态'),
                if (_showRuntimeDetails)
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
                            toolIds: _showFullInventory ? null : _targetToolIds,
                            toolSectionTitle: _showFullInventory
                                ? null
                                : '当前目标工具（${_target.label}）',
                            showGlobalMissing: _showFullInventory,
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
                      if (!kIsWeb && _showTargetSetup) ...[
                        const SettingsDivider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _openTargetHelp,
                              icon: Icon(_target == DevelopmentTarget.windowsExe
                                  ? Icons.open_in_new_rounded
                                  : Icons.settings_suggest_rounded),
                              label:
                                  Text(_target == DevelopmentTarget.windowsExe
                                      ? '查看 Windows 构建说明'
                                      : needsCommonTools
                                          ? '按需安装 ${_target.label} 工具'
                                          : '查看 ${_target.label} 环境说明'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else ...[
                  const SettingsSectionTitle('运行时检测'),
                  _runtimeRetryCard(context),
                ],
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
