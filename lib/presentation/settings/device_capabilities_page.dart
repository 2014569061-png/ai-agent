import '../widgets/nexus_disclosure.dart';
import '../theme/mobile_theme.dart';
import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/environment_service.dart';
import '../../application/local_error_copy.dart';
import '../../infrastructure/terminal/linux_runtime.dart';
import '../../infrastructure/tools/android_device_tool.dart';
import '../theme/app_palette.dart';
import '../theme/app_status_colors.dart';
import '../widgets/nexus_status_pill.dart';
import '../theme/desktop_theme.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/nexus_loading_skeleton.dart';
import '../widgets/nexus_page_header.dart';
import 'settings_components.dart';
import '../widgets/nexus_switch.dart';

class DeviceCapabilitiesPage extends ConsumerStatefulWidget {
  const DeviceCapabilitiesPage({
    super.key,
    this.bridge,
    this.environmentService,
    this.isAndroidPlatform,
  });

  /// Injection seams keep the capability display testable without a device.
  final AndroidDeviceControlBridge? bridge;
  final EnvironmentService? environmentService;
  final bool? isAndroidPlatform;

  @override
  ConsumerState<DeviceCapabilitiesPage> createState() =>
      _DeviceCapabilitiesPageState();
}

class _DeviceCapabilitiesPageState extends ConsumerState<DeviceCapabilitiesPage>
    with WidgetsBindingObserver {
  static const _probeTimeout = Duration(seconds: 15);

  bool _loading = true;
  bool _androidSupported = true;
  bool _rootLoading = false;
  bool _actionBusy = false;
  _DeviceCapabilitySnapshot? _snapshot;
  _CapabilityProbe<Map<String, dynamic>>? _rootProbe;
  _CapabilityProbe<Map<String, dynamic>>? _privilegeProbe;

  AndroidDeviceControlBridge get _bridge =>
      widget.bridge ?? const AndroidDeviceControlBridge();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统授权页 / Shizuku 返回后自动刷新授权状态。
    if (state == AppLifecycleState.resumed && _androidSupported) {
      unawaited(_refreshPrivilege());
    }
  }

  /// 读取 Shizuku、特殊权限和本地 VPN 状态；不执行 su，不会弹 Root 授权框。
  Future<void> _refreshPrivilege() async {
    final result =
        await _capture(() => _bridge.privilegeStatus(probeRoot: false));
    if (!mounted) return;
    setState(() => _privilegeProbe = result);
  }

  Future<void> _runPrivilegeAction(
    String label,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    String message;
    try {
      message = _actionMessage(label, await action());
    } on PlatformException catch (error) {
      message = LocalErrorCopy.of(error, action: label).headline();
    } catch (error) {
      message = LocalErrorCopy.of(error, action: label).headline();
    }
    if (!mounted) return;
    setState(() => _actionBusy = false);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
    await _refreshPrivilege();
  }

  String _actionMessage(String label, Map<String, dynamic> result) {
    if (result['grantedCount'] is num) {
      return '$label：已授予 ${result['grantedCount']} 项权限';
    }
    if (result['granted'] == true) return '$label：已完成';
    if (result['userActionRequired'] == true || result['opened'] == true) {
      return '已打开系统页面，完成后返回此页会自动刷新';
    }
    final reason = result['reason'] ?? result['message'];
    if (reason != null) return '$label：$reason';
    return '$label：已完成';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final supported = widget.isAndroidPlatform ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (!supported) {
      setState(() {
        _androidSupported = false;
        _loading = false;
        _snapshot = null;
        _rootProbe = null;
      });
      return;
    }

    _androidSupported = true;
    final bridge = _bridge;
    final EnvironmentService environmentService =
        widget.environmentService ?? ref.read(environmentServiceProvider);
    environmentService.invalidate();

    final results = await Future.wait<Object>([
      _capture(bridge.deviceInfo),
      _capture(bridge.systemStatus),
      _capture(bridge.listAuthorizedFolders),
      _capture(() => environmentService.inspect(force: true)),
      _capture(() => bridge.privilegeStatus(probeRoot: false)),
    ]);
    if (!mounted) return;
    setState(() {
      _snapshot = _DeviceCapabilitySnapshot(
        deviceInfo: results[0] as _CapabilityProbe<Map<String, dynamic>>,
        systemStatus: results[1] as _CapabilityProbe<Map<String, dynamic>>,
        authorizedFolders:
            results[2] as _CapabilityProbe<List<Map<String, String>>>,
        environment: results[3] as _CapabilityProbe<EnvironmentSnapshot>,
        checkedAt: DateTime.now(),
      );
      _privilegeProbe = results[4] as _CapabilityProbe<Map<String, dynamic>>;
      _rootProbe = null;
      _rootLoading = false;
      _loading = false;
    });
  }

  Future<void> _checkRoot() async {
    if (!_androidSupported || _rootLoading) return;
    setState(() => _rootLoading = true);
    final bridge = widget.bridge ?? const AndroidDeviceControlBridge();
    final result = await _capture(bridge.rootStatus);
    if (!mounted) return;
    setState(() {
      _rootProbe = result;
      _rootLoading = false;
    });
  }

  Future<_CapabilityProbe<T>> _capture<T>(Future<T> Function() action) async {
    try {
      return _CapabilityProbe<T>(
        value: await action().timeout(_probeTimeout),
      );
    } catch (error) {
      // 探针自己记录失败原因，界面不再靠异常类型反推。
      final copy = LocalErrorCopy.of(error);
      return _CapabilityProbe<T>(
        error: error,
        failureCode: copy.code,
        failureSummary: copy.summary,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(
        title: '设备能力',
        subtitle: DesktopTheme.maybeOf(context) != null
            ? 'Root · Shizuku · 系统权限 · 本地 VPN · SAF'
            : _snapshot == null
                ? '检查可用能力与权限'
                : '最近检测 ${_snapshot!.checkedAt.toLocal().toString().substring(11, 16)}',
        statusPill: DesktopTheme.maybeOf(context) != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppPalette.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppPalette.success.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: const Text(
                  '● LIVE',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeBadge,
                    fontFamily: AppTokens.fontFamilyMono,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.success,
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '重新检测',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: NexusPageLayout(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_androidSupported) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: '此页面仅支持 Android',
                subtitle: 'Root、Magisk/KernelSU 和 SAF 授权状态需要 Android 系统接口。',
                showChevron: false,
              ),
            ],
          ),
        ],
      );
    }
    if (_loading && _snapshot == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: NexusListSkeleton(itemCount: 5),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SettingsGroupCard(
            children: [
              SettingsTile(
                icon: Icons.error_outline_rounded,
                title: '能力检测尚未完成',
                subtitle: '点右上角重新检测。',
                showChevron: false,
              ),
            ],
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 36),
        children: [
          if (DesktopTheme.maybeOf(context) != null)
            _capabilityMatrixCard(snapshot),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text('权限与通道按最近检测结果显示；未检查不代表不可用。',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SettingsSectionTitle('设备信息'),
          _deviceInfoCard(snapshot),
          if (DesktopTheme.maybeOf(context) == null)
            NexusDisclosure(
              title: const Text('系统与执行通道详情', style: TextStyle(fontSize: 14)),
              headerPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              contentPadding: EdgeInsets.zero,
              child: _capabilityMatrixCard(snapshot),
            ),
          NexusDisclosure(
            title: const Text('Root 与系统安全详情'),
            headerPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            contentPadding: EdgeInsets.zero,
            child: _rootCard(snapshot),
          ),
          const SettingsSectionTitle('免 Root 通道'),
          _shizukuCard(),
          const SettingsSectionTitle('系统特殊权限'),
          _permissionsCard(),
          const SettingsSectionTitle('本地 VPN 过滤器'),
          _networkFilterCard(),
          const SettingsSectionTitle('运行环境'),
          _runtimeCard(snapshot),
          const SettingsSectionTitle('文件访问授权'),
          _authorizedFoldersCard(snapshot),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '检测时间：${snapshot.checkedAt.toLocal().toString().substring(0, 19)}。'
              'Root 检查由你手动触发，只读取授权状态，不修改设备。'
              '无 Root 时按 Shizuku → 系统 API → 打开系统设置页依次降级。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceInfoCard(_DeviceCapabilitySnapshot snapshot) {
    final probe = snapshot.deviceInfo;
    final info = probe.value;
    final model = info == null
        ? ''
        : [
            info['manufacturer'],
            info['brand'],
            info['model'],
          ]
            .whereType<String>()
            .where((part) => part.trim().isNotEmpty)
            .toSet()
            .join(' ');
    final version = info == null
        ? ''
        : [
            if (info['androidVersion'] != null)
              'Android ${info['androidVersion']}',
            if (info['sdk'] != null) 'API ${info['sdk']}',
          ].join(' · ');
    return SettingsGroupCard(
      children: [
        _statusTile(
          icon: Icons.phone_android_rounded,
          title: '设备型号',
          status: probe.error != null ? '检测失败' : '已检测',
          available: info != null,
          error: probe.error,
          subtitle: probe.error == null
              ? [model, version].where((text) => text.isNotEmpty).join(' · ')
              : _probeSummary(probe),
          failureCode: _probeCode(probe),
        ),
        const SettingsDivider(),
        _probeSummaryStrip(),
      ],
    );
  }

  /// 顶部一行说清「这次检测到底查出什么」：可用 / 异常 / 未检测。
  /// 下面是逐项细节，但第一眼需要的是结论——原来要滚到底才知道有几项挂了。
  Widget _probeSummaryStrip() {
    final probes = <_CapabilityProbe<Object?>>[
      if (_snapshot != null) ...[
        _snapshot!.deviceInfo,
        _snapshot!.systemStatus,
        _snapshot!.authorizedFolders,
        _snapshot!.environment,
      ],
      if (_rootProbe != null) _rootProbe!,
      if (_privilegeProbe != null) _privilegeProbe!,
    ];
    if (probes.isEmpty) return const SizedBox.shrink();
    final ok = probes.where((p) => p.error == null && p.value != null).length;
    final failed = probes.where((p) => p.error != null).length;
    final pending = probes.length - ok - failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (ok > 0)
            NexusStatusPillShell(
              label: '可用 $ok 项',
              tone: AppStatusTone.success,
              icon: Icons.check_rounded,
            ),
          if (failed > 0)
            NexusStatusPillShell(
              label: '异常 $failed 项',
              tone: AppStatusTone.danger,
              icon: Icons.error_outline_rounded,
            ),
          if (pending > 0)
            NexusStatusPillShell(
              label: '未检测 $pending 项',
              tone: AppStatusTone.neutral,
              icon: Icons.help_outline_rounded,
            ),
        ],
      ),
    );
  }

  Widget _capabilityMatrixCard(_DeviceCapabilitySnapshot snapshot) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final info = snapshot.deviceInfo.value ?? const <String, dynamic>{};
    final sdkInt = info['sdk']?.toString() ?? '36';
    final release = info['androidVersion']?.toString() ?? '16';
    final sys = snapshot.systemStatus.value ?? const <String, dynamic>{};
    final selinux = (sys['selinux'] ?? 'Permissive').toString();
    final rootGranted = _rootProbe?.value?['rootGranted'] == true;
    final foldersCount = (snapshot.authorizedFolders.value ?? const []).length;

    Widget cell({
      required String label,
      required String value,
      required String tag,
      required Color tagColor,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTokens.fontSizeBadge,
                  fontFamily: AppTokens.fontFamilyMono,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: textMuted,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeSubhead,
                      fontFamily: AppTokens.fontFamilyMono,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: tagColor.withValues(alpha: 0.30),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTokens.fontSizeBadge,
                        fontFamily: AppTokens.fontFamilyMono,
                        fontWeight: FontWeight.w600,
                        color: tagColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SettingsGroupCard(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                cell(
                  label: 'ANDROID RUNTIME',
                  value: 'API $sdkInt',
                  tag: 'Android $release',
                  tagColor: AppPalette.success,
                ),
                VerticalDivider(width: 1, thickness: 1, color: hairline),
                cell(
                  label: 'SELINUX MAC',
                  value: selinux,
                  tag: 'POLICY',
                  tagColor: AppPalette.warning,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: hairline),
          IntrinsicHeight(
            child: Row(
              children: [
                cell(
                  label: 'PRIVILEGE CH.',
                  value: rootGranted ? 'UID 0' : 'ADB/API',
                  tag: rootGranted ? 'ROOT' : 'FALLBACK',
                  tagColor: rootGranted
                      ? AppPalette.success
                      : MobileTheme.brand(context),
                ),
                VerticalDivider(width: 1, thickness: 1, color: hairline),
                cell(
                  label: 'SAF SANDBOX',
                  value: '$foldersCount 项目录',
                  tag: 'SCOPED IO',
                  tagColor: MobileTheme.brand(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rootCard(_DeviceCapabilitySnapshot snapshot) {
    final probe = _rootProbe;
    final data = probe?.value;
    final rootGranted = data?['rootGranted'] == true;
    final suPresent = data?['suPresent'] == true;
    final manager = _managerLabel(data?['manager'], suPresent: suPresent);
    final error = probe?.error;
    final status = error != null
        ? '检测失败'
        : probe == null
            ? '未检查'
            : rootGranted
                ? '已授权'
                : '未授权';
    final subtitle = error != null
        ? _errorText(error)
        : probe == null
            ? '点右侧检查；Magisk/KernelSU 可能会弹出 Root 授权提示。'
            : suPresent
                ? '检测到 su；管理器：$manager'
                : '未检测到可用 su；管理器：$manager';
    final color = error != null
        ? _sem.danger
        : rootGranted
            ? _sem.success
            : _sem.warning;
    return SettingsGroupCard(
      children: [
        SettingsTile(
          icon: Icons.admin_panel_settings_outlined,
          iconColor: color,
          title: 'Root 授权',
          subtitle: subtitle,
          wrapText: DesktopTheme.maybeOf(context) == null,
          trailingWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _badge(status, color),
              const SizedBox(width: 2),
              _rootLoading
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: '检查 Root',
                      onPressed: _checkRoot,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
            ],
          ),
          showChevron: false,
        ),
        const SettingsDivider(),
        _statusTile(
          icon: Icons.verified_user_outlined,
          title: 'Root 管理器',
          status: probe == null
              ? '未检查'
              : error != null
                  ? '检测失败'
                  : manager,
          available: data == null ? null : manager != '未发现',
          error: error,
          subtitle: error != null
              ? _errorText(error)
              : probe == null
                  ? '独立显示 Magisk 或 KernelSU 检测结果'
                  : 'su 程序${suPresent ? '存在' : '未发现'}',
        ),
        const SettingsDivider(),
        _selinuxTile(snapshot),
      ],
    );
  }

  Widget _selinuxTile(_DeviceCapabilitySnapshot snapshot) {
    final probe = snapshot.systemStatus;
    final enforcing = probe.value?['selinuxEnforcing'];
    final status = probe.error != null
        ? '检测失败'
        : enforcing == true
            ? 'Enforcing'
            : enforcing == false
                ? 'Permissive'
                : '未知';
    return _statusTile(
      icon: Icons.security_rounded,
      title: 'SELinux',
      status: status,
      available: enforcing is bool ? enforcing : null,
      error: probe.error,
      subtitle:
          probe.error == null ? '读取系统当前强制访问控制状态' : _errorText(probe.error!),
    );
  }

  Widget _runtimeCard(_DeviceCapabilitySnapshot snapshot) {
    final probe = snapshot.environment;
    final environment = probe.value;
    if (environment == null) {
      return SettingsGroupCard(
        children: [
          _statusTile(
            icon: Icons.terminal_rounded,
            title: 'Linux Runtime',
            status: '检测失败',
            available: false,
            error: probe.error,
            subtitle: _errorText(probe.error!),
          ),
        ],
      );
    }

    final candidates = environment.inspectedCandidates;
    final termux = candidates
        .where((item) => item.runtime.kind == LinuxRuntimeKind.termux)
        .firstOrNull;
    final otherRuntimes = candidates
        .where((item) => item.runtime.kind != LinuxRuntimeKind.termux)
        .toList(growable: false);
    final tiles = <Widget>[
      _statusTile(
        icon: Icons.terminal_rounded,
        title: 'Termux 桥接',
        status: termux == null
            ? '未发现'
            : termux.available
                ? '可用'
                : '不可用',
        available: termux?.available ?? false,
        subtitle: termux?.runtime.detail ?? '未检测到 Termux 运行时。',
      ),
    ];
    for (final runtime in otherRuntimes) {
      tiles
        ..add(const SettingsDivider())
        ..add(
          _statusTile(
            icon: Icons.computer_rounded,
            title: runtime.runtime.label,
            status: runtime.available ? '可用' : '不可用',
            available: runtime.available,
            subtitle:
                '${runtime.runtime.detail}${runtime.runtime.kind == environment.selected.kind ? ' · 当前选择' : ''}',
          ),
        );
    }
    return SettingsGroupCard(children: tiles);
  }

  Widget _authorizedFoldersCard(_DeviceCapabilitySnapshot snapshot) {
    final probe = snapshot.authorizedFolders;
    final folders = probe.value;
    if (folders == null) {
      return SettingsGroupCard(
        children: [
          _statusTile(
            icon: Icons.folder_open_rounded,
            title: 'SAF 文件夹授权',
            status: '检测失败',
            available: false,
            error: probe.error,
            subtitle: _errorText(probe.error!),
          ),
        ],
      );
    }
    if (folders.isEmpty) {
      return SettingsGroupCard(
        children: [
          _statusTile(
            icon: Icons.folder_open_rounded,
            title: 'SAF 文件夹授权',
            status: '未授权',
            available: false,
            subtitle: '尚未授权可搜索的共享文件夹。',
          ),
        ],
      );
    }
    return SettingsGroupCard(
      children: [
        for (var index = 0; index < folders.length; index++) ...[
          if (index > 0) const SettingsDivider(),
          SettingsTile(
            icon: Icons.folder_open_rounded,
            title: folders[index]['name'] ?? '已授权文件夹',
            subtitle: folders[index]['uri'],
            showChevron: false,
          ),
        ],
      ],
    );
  }

  Map<String, dynamic> _mapOf(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : const <String, dynamic>{};

  Widget? _privilegeUnavailableCard(IconData icon, String title) {
    final probe = _privilegeProbe;
    if (probe == null) {
      return SettingsGroupCard(
        children: [
          _statusTile(
            icon: icon,
            title: title,
            status: '检测中',
            available: null,
            subtitle: '正在读取授权状态…',
          ),
        ],
      );
    }
    if (probe.error != null) {
      return SettingsGroupCard(
        children: [
          _statusTile(
            icon: icon,
            title: title,
            status: '检测失败',
            available: false,
            error: probe.error,
            subtitle: _errorText(probe.error!),
          ),
        ],
      );
    }
    return null;
  }

  /// X4：徽标 / 图标使用当前主题语义色（深色下琥珀文字对比度足够）。
  AppSemanticColors get _sem => AppTheme.semanticOf(context);

  Widget _actionButton(String label, VoidCallback onPressed) => TextButton(
        onPressed: _actionBusy ? null : onPressed,
        style: TextButton.styleFrom(
          visualDensity: DesktopTheme.maybeOf(context) == null
              ? VisualDensity.standard
              : VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size(DesktopTheme.maybeOf(context) == null ? 48 : 0,
              DesktopTheme.maybeOf(context) == null ? 48 : 36),
        ),
        child: Text(label),
      );

  /// X4：徽标在上、操作在下，避免横排挤压副标题。
  Widget _badgeWithAction(Widget badge, Widget? action) {
    if (action == null) return badge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [badge, const SizedBox(height: 2), action],
    );
  }

  String _routeName(Object? route) => switch (route) {
        'root' => 'Root',
        'shizuku' => 'Shizuku',
        'app' => '应用权限',
        _ => '无（降级）',
      };

  Widget _shizukuCard() {
    final unavailable = _privilegeUnavailableCard(Icons.adb_rounded, 'Shizuku');
    if (unavailable != null) return unavailable;
    final data = _privilegeProbe!.value!;
    final shizuku = _mapOf(data['shizuku']);
    final routes = Map<String, dynamic>.of(_mapOf(data['routes']));
    // 手动检查过 Root 时以最新结果为准（自动加载不执行 su）。
    final checkedRoot = _rootProbe?.value;
    final rootProbed =
        checkedRoot != null || _mapOf(data['root'])['probed'] == true;
    if (checkedRoot?['rootGranted'] == true) {
      routes['shell'] = 'root';
      routes['rootUid'] = 'root';
      routes['storageDataLocalTmp'] = 'root';
      routes['storage'] ??= 'root';
    }
    final installed = shizuku['installed'] == true;
    final running = shizuku['running'] == true;
    final granted = shizuku['permissionGranted'] == true;
    final rootMode = shizuku['mode'] == 'root';
    final status = !installed
        ? '未安装'
        : !running
            ? '未运行'
            : granted
                ? (rootMode ? '可用 · Root 模式' : '可用 · ADB 模式')
                : '待授权';
    final subtitle = !installed
        ? '安装 Shizuku 后，无需 Root 即可以 adb 身份执行 Wi-Fi、蓝牙、强行停止等白名单命令。'
        : !running
            ? '在 Shizuku 中通过无线调试或电脑 adb 启动服务，返回此页后自动刷新。'
            : !granted
                ? shizuku['permanentlyDenied'] == true
                    ? '已被拒绝且不再询问：请在 Shizuku 的应用管理中手动允许 NEXUS。'
                    : '点“授权”，在 Shizuku 弹窗中允许 NEXUS。'
                : rootMode
                    ? '以 uid 0 运行：需要 Root 的白名单命令也可执行。点“授予权限”可让 NEXUS 以后直接调用系统 API。'
                    : '以 adb（uid 2000）运行：可执行系统设置类命令；清理缓存、hosts、端口防火墙仍需 Root。点“授予权限”可让 NEXUS 以后直接调用系统 API。';
    final Widget action = !installed || !running
        ? _actionButton(
            '打开', () => _runPrivilegeAction('打开 Shizuku', _bridge.openShizuku))
        : !granted
            ? _actionButton(
                '授权',
                () => _runPrivilegeAction(
                    'Shizuku 授权', _bridge.requestShizukuPermission),
              )
            : _actionButton(
                '授予权限',
                () => _runPrivilegeAction(
                    '授予系统权限', _bridge.grantPermissionsViaPrivilege),
              );
    final color = granted ? _sem.success : _sem.warning;
    final rootNote = rootProbed ? '' : '（Root 未检查）';
    return SettingsGroupCard(
      children: [
        SettingsTile(
          icon: Icons.adb_rounded,
          iconColor: color,
          title: 'Shizuku',
          subtitle: subtitle,
          subtitleMaxLines: 4,
          trailingWidget: _badgeWithAction(_badge(status, color), action),
          showChevron: false,
        ),
        const SettingsDivider(),
        _statusTile(
          icon: Icons.alt_route_rounded,
          title: '当前执行通道',
          status: routes['shell'] != null ? '已就绪' : '仅降级',
          available: routes['shell'] != null,
          subtitleMaxLines: 3,
          subtitle: '系统命令：${_routeName(routes['shell'])} · '
              '需 uid 0：${_routeName(routes['rootUid'])} · '
              '共享存储：${_routeName(routes['storage'])}$rootNote',
        ),
      ],
    );
  }

  static const _permissionItems = <(String, String, String?, String, IconData)>[
    (
      'allFilesAccess',
      '所有文件访问',
      'all_files',
      '免 Root 读写 /sdcard 文件、统计目录大小、目录备份',
      Icons.folder_special_outlined,
    ),
    (
      'usageAccess',
      '使用情况访问',
      'usage',
      '读取前台应用与最近使用的应用',
      Icons.query_stats_rounded,
    ),
    (
      'notificationPolicy',
      '勿扰权限',
      'notification_policy',
      '直接开关勿扰模式',
      Icons.do_not_disturb_on_outlined,
    ),
    (
      'writeSettings',
      '修改系统设置',
      'write_settings',
      '调整亮度、自动旋转、刷新率',
      Icons.tune_rounded,
    ),
    (
      'installPackages',
      '安装未知应用',
      'install_packages',
      '从安装包备份恢复应用（系统安装器确认）',
      Icons.install_mobile_rounded,
    ),
    (
      'bluetoothConnect',
      '附近设备',
      'bluetooth',
      'Android 12 以下可直接开关蓝牙',
      Icons.bluetooth_rounded,
    ),
    (
      'vpnPrepared',
      'VPN 连接',
      'vpn',
      '本地 VPN 域名屏蔽与应用断网',
      Icons.vpn_lock_outlined,
    ),
    (
      'writeSecureSettings',
      'WRITE_SECURE_SETTINGS',
      null,
      '修改动画倍率；只能由 Root/Shizuku“授予权限”或 adb 授予',
      Icons.admin_panel_settings_outlined,
    ),
    (
      'readLogs',
      'READ_LOGS',
      null,
      '读取完整 Logcat；只能由 Root/Shizuku“授予权限”或 adb 授予',
      Icons.receipt_long_outlined,
    ),
  ];

  Widget _permissionsCard() {
    final unavailable = _privilegeUnavailableCard(Icons.key_rounded, '系统特殊权限');
    if (unavailable != null) return unavailable;
    final permissions = _mapOf(_privilegeProbe!.value!['permissions']);
    return SettingsGroupCard(
      children: [
        for (var index = 0; index < _permissionItems.length; index++) ...[
          if (index > 0) const SettingsDivider(),
          _permissionTile(_permissionItems[index], permissions),
        ],
      ],
    );
  }

  Widget _permissionTile(
    (String, String, String?, String, IconData) item,
    Map<String, dynamic> permissions,
  ) {
    final (key, title, kind, usage, icon) = item;
    final allowed = permissions[key] == true;
    final color = allowed ? _sem.success : _sem.warning;
    return SettingsTile(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: usage,
      trailingWidget: _badgeWithAction(
        _badge(allowed ? '已允许' : '未允许', color),
        !allowed && kind != null
            ? _actionButton(
                '去授权',
                () => _runPrivilegeAction(
                  title,
                  () => _bridge.openSpecialPermission(kind),
                ),
              )
            : null,
      ),
      showChevron: false,
    );
  }

  Widget _networkFilterCard() {
    final unavailable =
        _privilegeUnavailableCard(Icons.shield_outlined, '本地 VPN 过滤器');
    if (unavailable != null) return unavailable;
    final filter = _mapOf(_privilegeProbe!.value!['networkFilter']);
    final enabled = filter['enabled'] == true;
    final running = filter['running'] == true;
    final domains = (filter['domains'] as List?) ?? const [];
    final apps = (filter['apps'] as List?) ?? const [];
    final lastError = filter['lastError'];
    final status = running
        ? '运行中'
        : enabled
            ? '已启用 · 未运行'
            : '未启用';
    final color = running
        ? _sem.success
        : lastError != null
            ? _sem.danger
            : _sem.warning;
    final hasRules = domains.isNotEmpty || apps.isNotEmpty;
    final mode = switch (filter['mode']) {
      'dns' => ' · DNS 模式',
      'app_full' => ' · 应用断网模式',
      _ => '',
    };
    final limitations = (filter['limitations'] as List?) ?? const [];
    return SettingsGroupCard(
      children: [
        SettingsTile(
          icon: Icons.shield_outlined,
          iconColor: color,
          title: '本地 VPN 过滤器',
          subtitle: '屏蔽域名 ${domains.length} 个 · 断网应用 ${apps.length} 个$mode'
              '${lastError != null ? '\n最近错误：$lastError' : ''}'
              '${hasRules ? '' : '\n规则由智能体的 set_domain_block / set_app_network_block 添加（需审批）'}',
          trailingWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _badge(status, color),
              NexusSwitch(
                value: enabled,
                onChanged: _actionBusy || (!enabled && !hasRules)
                    ? null
                    : (value) => _runPrivilegeAction(
                          value ? '启用本地 VPN' : '停用本地 VPN',
                          () => _bridge.setNetworkFilterEnabled(value),
                        ),
              ),
            ],
          ),
          showChevron: false,
        ),
        if (hasRules) ...[
          const SettingsDivider(),
          SettingsTile(
            icon: Icons.list_alt_rounded,
            title: '当前规则',
            subtitle: [
              if (domains.isNotEmpty)
                '域名：${domains.take(5).join('、')}${domains.length > 5 ? ' 等 ${domains.length} 个' : ''}',
              if (apps.isNotEmpty)
                '应用：${apps.take(5).join('、')}${apps.length > 5 ? ' 等 ${apps.length} 个' : ''}',
            ].join('\n'),
            showChevron: false,
          ),
        ],
        if (limitations.isNotEmpty) ...[
          const SettingsDivider(),
          SettingsTile(
            icon: Icons.info_outline_rounded,
            title: '限制说明',
            subtitle: limitations.map((item) => '• $item').join('\n'),
            showChevron: false,
          ),
        ],
      ],
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String title,
    required String status,
    required bool? available,
    required String subtitle,
    Object? error,
    int subtitleMaxLines = 2,
    String? failureCode,
  }) {
    final color = error != null
        ? _sem.danger
        : available == true
            ? _sem.success
            : _sem.warning;
    // 失败时把失败类别一并显示，用户才能区分「这台设备没有该通道」
    // 与「有通道但权限被拒」——两者的处理方式完全不同。
    final code = error == null ? null : (failureCode ?? _errorCode(error));
    return SettingsTile(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: subtitleMaxLines,
      trailingBadge: _badge(code == null ? status : '$status · $code', color),
      showChevron: false,
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: 0.24),
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: AppTokens.fontSizeFootnote,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  String _managerLabel(Object? raw, {required bool suPresent}) {
    return switch (raw?.toString().toLowerCase()) {
      'magisk' => 'Magisk',
      'kernelsu' => 'KernelSU',
      _ => suPresent ? '未识别' : '未发现',
    };
  }

  String _errorText(Object error) {
    // 只展示人话结论；原始异常保留在 LocalErrorCopy.detail 供折叠或日志使用，
    // 避免 MissingPluginException 之类的技术文本直接出现在设置页。
    return LocalErrorCopy.of(error).summary;
  }

  /// 失败类别的短标签，取自 [LocalErrorCopy.code]，便于用户与支持人员分辨原因。
  String _errorCode(Object error) {
    return switch (LocalErrorCopy.of(error).code) {
      'channel_unavailable' => '通道缺失',
      'permission_denied' => '权限被拒',
      'platform_error' => '系统拒绝',
      'timeout' => '超时',
      'filesystem' => '存储异常',
      'format' => '数据异常',
      'network' => '网络异常',
      _ => '未知原因',
    };
  }

  /// 探针自报的失败结论；探针没有记录时退回按异常推断，保证旧调用点仍可用。
  String _probeSummary(_CapabilityProbe<Object?> probe) {
    final summary = probe.failureSummary;
    if (summary != null) return summary;
    final error = probe.error;
    return error == null ? '' : _errorText(error);
  }

  /// 探针自报的失败类别标签。
  String _probeCode(_CapabilityProbe<Object?> probe) {
    return switch (probe.failureCode) {
      'channel_unavailable' => '通道缺失',
      'permission_denied' => '权限被拒',
      'platform_error' => '系统拒绝',
      'timeout' => '超时',
      'filesystem' => '存储异常',
      'format' => '数据异常',
      'network' => '网络异常',
      null => '',
      _ => '未知原因',
    };
  }
}

class _DeviceCapabilitySnapshot {
  const _DeviceCapabilitySnapshot({
    required this.deviceInfo,
    required this.systemStatus,
    required this.authorizedFolders,
    required this.environment,
    required this.checkedAt,
  });

  final _CapabilityProbe<Map<String, dynamic>> deviceInfo;
  final _CapabilityProbe<Map<String, dynamic>> systemStatus;
  final _CapabilityProbe<List<Map<String, String>>> authorizedFolders;
  final _CapabilityProbe<EnvironmentSnapshot> environment;
  final DateTime checkedAt;
}

class _CapabilityProbe<T> {
  const _CapabilityProbe({
    this.value,
    this.error,
    this.failureCode,
    this.failureSummary,
  });

  final T? value;
  final Object? error;

  /// 失败类别，取自捕获时的 [LocalErrorCopy.code]；成功时为 null。
  final String? failureCode;

  /// 失败结论，取自捕获时的 [LocalErrorCopy.summary]；界面优先使用它。
  final String? failureSummary;
}
