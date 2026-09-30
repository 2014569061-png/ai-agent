import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../../domain/unique_id.dart';
import 'android_backup_actions.dart';
import 'tool_registry.dart';

class AndroidDeviceControlBridge {
  const AndroidDeviceControlBridge();

  static const MethodChannel _channel = MethodChannel('nexus/device_control');

  Future<List<Map<String, String>>> listApps() async {
    final result = await _channel.invokeListMethod<dynamic>('listApps');
    return [
      for (final item in result ?? const [])
        if (item is Map)
          Map<String, String>.fromEntries(item.entries.map(
            (entry) => MapEntry(entry.key.toString(), entry.value.toString()),
          )),
    ];
  }

  Future<void> launchApp(String packageName) =>
      _channel.invokeMethod<void>('launchApp', {'packageName': packageName});

  Future<Map<String, dynamic>> rootStatus() async =>
      await _channel.invokeMapMethod<String, dynamic>('rootStatus') ?? const {};

  Future<Map<String, dynamic>> deviceInfo() async =>
      await _channel.invokeMapMethod<String, dynamic>('deviceInfo') ?? const {};

  Future<Map<String, dynamic>> storageInfo() async =>
      await _channel.invokeMapMethod<String, dynamic>('storageInfo') ??
      const {};

  Future<Map<String, dynamic>> networkInfo() async =>
      await _channel.invokeMapMethod<String, dynamic>('networkInfo') ??
      const {};

  Future<Map<String, dynamic>> refreshDns() async =>
      await _channel.invokeMapMethod<String, dynamic>('refreshDns') ?? const {};

  Future<Map<String, dynamic>> openVpnSettings() async =>
      await _channel.invokeMapMethod<String, dynamic>('openVpnSettings') ??
      const {};

  Future<Map<String, dynamic>> setFirewallPortRule({
    required String protocol,
    required int port,
    required bool enabled,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'setFirewallPortRule',
        {'protocol': protocol, 'port': port, 'enabled': enabled},
      ) ??
      const {};

  Future<Map<String, dynamic>> setHostsBlock({
    required String domain,
    required bool enabled,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'setHostsBlock',
        {'domain': domain, 'enabled': enabled},
      ) ??
      const {};

  Future<Map<String, dynamic>> restartService(String serviceName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'restartService', {'serviceName': serviceName}) ??
      const {};

  Future<List<dynamic>> runningProcesses() async =>
      await _channel.invokeListMethod<dynamic>('runningProcesses') ?? const [];

  Future<List<dynamic>> foregroundApps() async =>
      await _channel.invokeListMethod<dynamic>('foregroundApps') ?? const [];

  Future<Map<String, dynamic>> logcatTail(int lines) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('logcatTail', {'lines': lines}) ??
      const {};

  Future<Map<String, dynamic>> crashLogs(String? packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'crashLogs', {if (packageName != null) 'packageName': packageName}) ??
      const {};

  Future<Map<String, dynamic>> appInfo(String packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'appInfo', {'packageName': packageName}) ??
      const {};

  Future<Map<String, dynamic>> systemStatus() async =>
      await _channel.invokeMapMethod<String, dynamic>('systemStatus') ??
      const {};

  Future<Map<String, dynamic>> trafficInfo() async =>
      await _channel.invokeMapMethod<String, dynamic>('trafficInfo') ??
      const {};

  Future<Map<String, dynamic>> traceroute(String host) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('traceroute', {'host': host}) ??
      const {};

  Future<Map<String, dynamic>> systemSettings() async =>
      await _channel.invokeMapMethod<String, dynamic>('systemSettings') ??
      const {};

  Future<Map<String, dynamic>> setBrightness(double value) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setBrightness', {'value': value}) ??
      const {};

  Future<Map<String, dynamic>> setVolume(String stream, double value) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setVolume', {'stream': stream, 'value': value}) ??
      const {};

  Future<Map<String, dynamic>> setAutoRotate(bool enabled) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setAutoRotate', {'enabled': enabled}) ??
      const {};

  Future<Map<String, dynamic>> setWifi(bool enabled) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('setWifi', {'enabled': enabled}) ??
      const {};

  Future<Map<String, dynamic>> setBluetooth(bool enabled) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setBluetooth', {'enabled': enabled}) ??
      const {};

  Future<Map<String, dynamic>> setAirplaneMode(bool enabled) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setAirplaneMode', {'enabled': enabled}) ??
      const {};

  Future<Map<String, dynamic>> setLocationEnabled(bool enabled) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setLocationEnabled', {'enabled': enabled}) ??
      const {};

  Future<Map<String, dynamic>> setDoNotDisturb(bool enabled) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setDoNotDisturb', {'enabled': enabled}) ??
      const {};

  Future<Map<String, dynamic>> setRefreshRate(double value) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setRefreshRate', {'value': value}) ??
      const {};

  Future<Map<String, dynamic>> setFontScale(double value) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('setFontScale', {'value': value}) ??
      const {};

  Future<Map<String, dynamic>> setAnimationScale(double value) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setAnimationScale', {'value': value}) ??
      const {};

  Future<Map<String, dynamic>> openDefaultAppsSettings() async =>
      await _channel
          .invokeMapMethod<String, dynamic>('openDefaultAppsSettings') ??
      const {};

  Future<Map<String, dynamic>> openDoNotDisturbSettings() async =>
      await _channel
          .invokeMapMethod<String, dynamic>('openDoNotDisturbSettings') ??
      const {};

  Future<Map<String, dynamic>> openNotificationSettings(
          String? packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'openNotificationSettings',
          {if (packageName != null) 'packageName': packageName}) ??
      const {};

  Future<Map<String, dynamic>> directorySize(String path) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('directorySize', {'path': path}) ??
      const {};

  Future<Map<String, dynamic>> portProbe(String host, int port) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'portProbe', {'host': host, 'port': port}) ??
      const {};

  Future<Map<String, dynamic>> restartApp(String packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'restartApp', {'packageName': packageName}) ??
      const {};

  Future<Map<String, dynamic>> appPermissions(String packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'appPermissions', {'packageName': packageName}) ??
      const {};

  Future<List<dynamic>> recentApps() async =>
      await _channel.invokeListMethod<dynamic>('recentApps') ?? const [];

  Future<Map<String, dynamic>> setAppAlias(
          String alias, String packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'setAppAlias', {'alias': alias, 'packageName': packageName}) ??
      const {};

  Future<List<dynamic>> listAppAliases() async =>
      await _channel.invokeListMethod<dynamic>('listAppAliases') ?? const [];

  Future<Map<String, dynamic>> launchDeepLink(
          String packageName, String uri) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'launchDeepLink', {'packageName': packageName, 'uri': uri}) ??
      const {};

  Future<Map<String, dynamic>> stopApp(String packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'stopApp', {'packageName': packageName}) ??
      const {};

  Future<Map<String, dynamic>> killProcess(int pid, String processName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'killProcess', {'pid': pid, 'processName': processName}) ??
      const {};

  Future<Map<String, dynamic>> clearAppCache(String packageName) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'clearAppCache', {'packageName': packageName}) ??
      const {};

  Future<Map<String, dynamic>> readRootFile(String path) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('readRootFile', {'path': path}) ??
      const {};

  Future<Map<String, dynamic>> inspectAppPrivateData({
    required String operation,
    required String packageName,
    required String relativePath,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'inspectAppPrivateData',
        {
          'operation': operation,
          'packageName': packageName,
          'relativePath': relativePath,
        },
      ) ??
      const {};

  Future<Map<String, dynamic>> listRootFiles(String path) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('listRootFiles', {'path': path}) ??
      const {};

  Future<Map<String, dynamic>> writeRootFile(
          String path, String content) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'writeRootFile', {'path': path, 'content': content}) ??
      const {};

  Future<Map<String, dynamic>> deleteRootFile(String path) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('deleteRootFile', {'path': path}) ??
      const {};

  Future<Map<String, dynamic>> moveRootFile(
          String source, String destination) async =>
      await _channel.invokeMapMethod<String, dynamic>(
          'moveRootFile', {'source': source, 'destination': destination}) ??
      const {};

  Future<Map<String, dynamic>> networkProbe(String host) async =>
      await _channel
          .invokeMapMethod<String, dynamic>('networkProbe', {'host': host}) ??
      const {};

  Future<Map<String, dynamic>> compressRootFiles(
          List<String> sources, String destination) async =>
      await _channel.invokeMapMethod<String, dynamic>('compressRootFiles',
          {'sources': sources, 'destination': destination}) ??
      const {};

  Future<Map<String, dynamic>> extractRootArchive(
          String archive, String destination) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'extractRootArchive',
        {'archive': archive, 'destination': destination},
      ) ??
      const {};

  Future<Map<String, dynamic>> searchFilesFiltered({
    required String query,
    String? extension,
    int? modifiedAfterMs,
    int? modifiedBeforeMs,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'searchFilesFiltered',
        {
          'query': query,
          if (extension != null) 'extension': extension,
          if (modifiedAfterMs != null) 'modifiedAfterMs': modifiedAfterMs,
          if (modifiedBeforeMs != null) 'modifiedBeforeMs': modifiedBeforeMs,
        },
      ) ??
      const {};

  Future<Map<String, dynamic>> fileOperation({
    required String operation,
    required String uri,
    String? destinationUri,
    String? newName,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'fileOperation',
        {
          'operation': operation,
          'uri': uri,
          if (destinationUri != null) 'destinationUri': destinationUri,
          if (newName != null) 'newName': newName,
        },
      ) ??
      const {};

  Future<Map<String, dynamic>> fileOperationBatch({
    required String operation,
    required List<String> uris,
    String? destinationUri,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'fileOperationBatch',
        {
          'operation': operation,
          'uris': uris.map((uri) => uri.trim()).toList(growable: false),
          if (destinationUri != null) 'destinationUri': destinationUri.trim(),
        },
      ) ??
      const {};

  Future<Map<String, dynamic>> refreshSearchIndex() async =>
      await _channel.invokeMapMethod<String, dynamic>('refreshSearchIndex') ??
      const {};

  Future<void> shareFile(String uri) =>
      _channel.invokeMethod<void>('shareFile', {'uri': uri});

  Future<Map<String, dynamic>> launchAppByName(String query) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'launchAppByName',
        {'query': query},
      ) ??
      const {};

  Future<void> chooseFolder() => _channel.invokeMethod<void>('chooseFolder');

  Future<Map<String, dynamic>> searchFiles(
    String query,
    String requestId,
  ) async =>
      await _channel.invokeMapMethod<String, dynamic>(
        'searchFiles',
        {'query': query, 'requestId': requestId},
      ) ??
      const {};

  Future<void> openFile(String uri) =>
      _channel.invokeMethod<void>('openFile', {'uri': uri});

  Future<List<Map<String, String>>> listAuthorizedFolders() async {
    final result =
        await _channel.invokeListMethod<dynamic>('listAuthorizedFolders');
    return [
      for (final item in result ?? const [])
        if (item is Map)
          Map<String, String>.fromEntries(item.entries.map(
            (entry) => MapEntry(entry.key.toString(), entry.value.toString()),
          )),
    ];
  }

  Future<Map<String, dynamic>> listAuthorizedFoldersResult() async => {
        'folders': await listAuthorizedFolders(),
      };

  Future<void> removeAuthorizedFolder(String uri) =>
      _channel.invokeMethod<void>('removeAuthorizedFolder', {'uri': uri});

  Future<void> cancelSearch(String requestId) =>
      _channel.invokeMethod<void>('cancelSearch', {'requestId': requestId});

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async =>
      await _channel.invokeMapMethod<String, dynamic>(method, arguments) ??
      const {};

  /// Root / Shizuku / 特殊权限 / 本地 VPN 的汇总状态与各类动作的实际执行通道。
  ///
  /// [probeRoot] 为 false 时只读取已缓存的 Root 结果，不执行 su（不会弹授权框）。
  ///
  /// 每次调用都会刷新执行通道快照，预览据此说明“将通过哪个通道执行”，
  /// 预览本身不访问原生层（也就不会触发 Root 授权框）。
  /// 最近 5 分钟内读取过的完整 privilegeStatus（供同步的审批详情使用）；没有则为 null。
  static Map<String, dynamic>? get recentPrivilegeStatus {
    final snapshot = _privilegeRouteSnapshot;
    return snapshot != null && snapshot.fresh ? snapshot.status : null;
  }

  Future<Map<String, dynamic>> privilegeStatus({bool probeRoot = true}) async {
    final status =
        await _invokeMap('privilegeStatus', {'probeRoot': probeRoot});
    final routes = status['routes'];
    if (routes is Map) {
      final root = status['root'];
      _privilegeRouteSnapshot = _PrivilegeRouteSnapshot(
        Map<String, dynamic>.from(routes),
        rootProbed: root is Map && root['probed'] == true,
        status: status,
      );
    }
    return status;
  }

  Future<Map<String, dynamic>> requestShizukuPermission() =>
      _invokeMap('requestShizukuPermission');

  Future<Map<String, dynamic>> openShizuku() => _invokeMap('openShizuku');

  Future<Map<String, dynamic>> grantPermissionsViaPrivilege() =>
      _invokeMap('grantPermissionsViaPrivilege');

  Future<Map<String, dynamic>> openSpecialPermission(String kind) =>
      _invokeMap('openSpecialPermission', {'kind': kind});

  Future<Map<String, dynamic>> openAppDetails(String packageName) =>
      _invokeMap('openAppDetails', {'packageName': packageName});

  Future<Map<String, dynamic>> networkFilterStatus() =>
      _invokeMap('networkFilterStatus');

  Future<Map<String, dynamic>> setNetworkFilterEnabled(bool enabled) =>
      _invokeMap('setNetworkFilterEnabled', {'enabled': enabled});

  Future<Map<String, dynamic>> setAppNetworkBlock({
    required String packageName,
    required bool enabled,
  }) =>
      _invokeMap(
        'setAppNetworkBlock',
        {'packageName': packageName, 'enabled': enabled},
      );

  Future<Map<String, dynamic>> setDomainBlock({
    required String domain,
    required bool enabled,
  }) =>
      _invokeMap('setDomainBlock', {'domain': domain, 'enabled': enabled});
}

/// 免 Root 通道：openSpecialPermission 支持的权限页。
const androidSpecialPermissionKinds = <String>{
  'all_files',
  'usage',
  'notification_policy',
  'write_settings',
  'install_packages',
  'vpn',
  'bluetooth',
};

/// 最近一次 privilegeStatus 返回的执行通道，供同步的预览/审批详情引用。
_PrivilegeRouteSnapshot? _privilegeRouteSnapshot;

class _PrivilegeRouteSnapshot {
  _PrivilegeRouteSnapshot(
    this.routes, {
    this.rootProbed = true,
    this.status = const {},
  }) : fetchedAt = DateTime.now();
  final Map<String, dynamic> routes;
  final bool rootProbed;
  final Map<String, dynamic> status;
  final DateTime fetchedAt;
  bool get fresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 5);
}

const _mutatingAndroidActions = <String>{
  'launch_app',
  'launch_app_by_name',
  'launch_deep_link',
  'choose_folder',
  'open_file',
  'stop_app',
  'kill_process',
  'restart_app',
  'clear_app_cache',
  'set_app_alias',
  'write_root_file',
  'delete_root_file',
  'move_root_file',
  'refresh_dns',
  'open_vpn_settings',
  'restart_service',
  'set_firewall_port_rule',
  'set_hosts_block',
  'compress_root_files',
  'extract_root_archive',
  'set_brightness',
  'set_volume',
  'set_auto_rotate',
  'set_wifi',
  'set_bluetooth',
  'set_airplane_mode',
  'set_location',
  'set_do_not_disturb',
  'set_refresh_rate',
  'set_font_scale',
  'set_animation_scale',
  'open_default_apps_settings',
  'open_do_not_disturb_settings',
  'open_notification_settings',
  'share_file',
  'file_operation',
  'request_shizuku_permission',
  'open_shizuku',
  'grant_privileged_permissions',
  'open_special_permission',
  'open_app_details',
  'set_network_filter',
  'set_app_network_block',
  'set_domain_block',
  ...androidBackupMutatingActions,
};

const _rootAndroidActions = <String>{
  'stop_app',
  'restart_app',
  'kill_process',
  'clear_app_cache',
  'restart_service',
  'refresh_dns',
  'set_firewall_port_rule',
  'set_hosts_block',
  'set_wifi',
  'set_bluetooth',
  'set_airplane_mode',
  'set_location',
  'set_do_not_disturb',
  'set_animation_scale',
  'directory_size',
  'read_root_file',
  'list_root_files',
  'write_root_file',
  'delete_root_file',
  'move_root_file',
  'compress_root_files',
  'extract_root_archive',
  ...androidBackupRootActions,
};

final _plannedAndroidActions = <String>{
  ..._mutatingAndroidActions,
  ..._rootAndroidActions,
};

class AndroidDeviceTool implements AgentTool, ToolApprovalGate {
  AndroidDeviceTool({
    AndroidDeviceControlBridge? bridge,
    AndroidBackupBridge? backupBridge,
  })  : _bridge = bridge ?? const AndroidDeviceControlBridge(),
        _backupBridge = backupBridge ?? const AndroidBackupBridge();

  final AndroidDeviceControlBridge _bridge;
  final AndroidBackupBridge _backupBridge;

  @override
  final manifest = const UnifiedTool(
    name: 'android_device',
    traits: ToolTraits(
      readOnly: false,
      scopes: {ToolEffectScope.device},
    ),
    description:
        '执行 Android 设备操作。变更前必须先调用 android_device_preview 获取目标、影响范围、风险和撤销信息，'
        '再将返回的 planId 与相同参数传入本工具。工具执行器会按 action 风险等级审批；Root、危险系统开关、网络规则与不可逆操作每次都需明确批准。'
        '只有批准后才签发两分钟有效的一次性执行票据。禁止直接拼接或执行任意 su 命令。'
        '无 Root 时按 Root → Shizuku → 系统 API → 打开系统设置页依次降级（共享存储文件优先用应用自身的“所有文件访问”权限）；'
        '结果里的 executedVia 标明实际通道，userActionRequired=true 表示只打开了系统页面、尚未生效，需要用户手动完成后再读取确认。'
        '不确定能做什么时先调用 privilege_status；无 Root 的域名/应用断网用 set_domain_block、set_app_network_block（本地 VPN）。',
    risk: ToolRisk.requiresConfirmation,
    // 备份/恢复的原生 Root 流程单步最长 180 秒（打包 + 校验），默认 120 秒会误报超时。
    timeout: Duration(seconds: 420),
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': [
            'list_apps',
            'root_status',
            'device_info',
            'storage_info',
            'network_info',
            'set_firewall_port_rule',
            'set_hosts_block',
            'refresh_dns',
            'open_vpn_settings',
            'running_processes',
            'foreground_apps',
            'logcat_tail',
            'crash_logs',
            'app_info',
            'system_status',
            'traffic_info',
            'traceroute',
            'system_settings',
            'set_brightness',
            'set_volume',
            'set_auto_rotate',
            'set_wifi',
            'set_bluetooth',
            'set_airplane_mode',
            'set_location',
            'set_do_not_disturb',
            'set_refresh_rate',
            'set_font_scale',
            'set_animation_scale',
            'open_default_apps_settings',
            'open_do_not_disturb_settings',
            'open_notification_settings',
            'directory_size',
            'port_probe',
            'restart_app',
            'restart_service',
            'app_permissions',
            'recent_apps',
            'set_app_alias',
            'list_app_aliases',
            'launch_deep_link',
            'stop_app',
            'kill_process',
            'clear_app_cache',
            'read_root_file',
            'list_root_files',
            'write_root_file',
            'delete_root_file',
            'move_root_file',
            'network_probe',
            'compress_root_files',
            'extract_root_archive',
            'search_files_filtered',
            'refresh_file_index',
            'file_operation',
            'share_file',
            'launch_app_by_name',
            'launch_app',
            'search_files',
            'choose_folder',
            'list_authorized_folders',
            'open_file',
            'backup_list',
            'backup_inspect',
            'backup_personal_data',
            'backup_app_data',
            'backup_directory',
            'restore_app_data',
            'restore_contacts',
            'backup_delete',
            'privilege_status',
            'request_shizuku_permission',
            'open_shizuku',
            'grant_privileged_permissions',
            'open_special_permission',
            'open_app_details',
            'network_filter_status',
            'set_network_filter',
            'set_app_network_block',
            'set_domain_block'
          ],
        },
        'query': {'type': 'string', 'description': '应用名称或文件名关键词'},
        'packageName': {'type': 'string', 'description': '启动应用时使用的包名'},
        'appName': {'type': 'string', 'description': '用户提到的应用名称或别名'},
        'uri': {'type': 'string', 'description': '打开 SAF 返回的 content URI'},
        'path': {'type': 'string', 'description': '受限目录或文件路径'},
        'source': {'type': 'string', 'description': 'Root 文件操作源路径'},
        'content': {'type': 'string', 'description': 'Root 文件写入内容，最多 64 KiB'},
        'value': {
          'type': 'number',
          'description': '亮度/音量为 0 到 1；刷新率、字体缩放、动画倍率使用各动作范围',
        },
        'stream': {
          'type': 'string',
          'enum': ['music', 'ring', 'alarm', 'notification', 'voice_call']
        },
        'enabled': {'type': 'boolean'},
        'lines': {'type': 'integer', 'description': 'Logcat 行数，最多 500'},
        'host': {'type': 'string', 'description': '网络主机名或 IP'},
        'port': {'type': 'integer', 'description': '网络端口'},
        'protocol': {
          'type': 'string',
          'enum': ['tcp', 'udp'],
          'description': '防火墙规则协议',
        },
        'domain': {
          'type': 'string',
          'description':
              'set_hosts_block（Root，改 /system/etc/hosts；无 Root 自动改用本地 VPN）或 set_domain_block（本地 VPN DNS 屏蔽）的域名',
        },
        'permissionKind': {
          'type': 'string',
          'enum': [
            'all_files',
            'usage',
            'notification_policy',
            'write_settings',
            'install_packages',
            'vpn',
            'bluetooth'
          ],
          'description': 'open_special_permission 要打开的系统授权页',
        },
        'pid': {'type': 'integer', 'description': '结束进程时核对的 PID'},
        'processName': {
          'type': 'string',
          'description': '必须与 /proc/<pid>/cmdline 首项完全匹配',
        },
        'serviceName': {
          'type': 'string',
          'enum': ['logd', 'statsd'],
          'description': '可重启服务白名单；当前仅支持 logd、statsd',
        },
        'planId': {
          'type': 'string',
          'description': '变更调用必须使用 android_device_preview 返回的匹配计划 ID',
        },
        'sources': {
          'type': 'array',
          'items': {'type': 'string'}
        },
        'destination': {'type': 'string', 'description': '目标路径'},
        'archive': {'type': 'string', 'description': '压缩包路径'},
        'extension': {'type': 'string', 'description': '文件扩展名'},
        'modifiedAfterMs': {'type': 'integer'},
        'modifiedBeforeMs': {'type': 'integer'},
        'alias': {'type': 'string', 'description': '应用别名'},
        'deepLink': {'type': 'string', 'description': '应用深链 URI'},
        'operation': {
          'type': 'string',
          'enum': ['rename', 'delete', 'copy', 'move'],
        },
        'uris': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              '批量删除、复制或移动的 content URI，最多 100 个；不能与 uri、newName 同时使用',
        },
        'destinationUri': {
          'type': 'string',
          'description': '复制或移动时使用的已授权目标目录 content URI',
        },
        'newName': {
          'type': 'string',
          'description': '重命名时使用的单个文件名，不可包含路径',
        },
        'category': {
          'type': 'string',
          'enum': ['contacts', 'sms', 'call_log'],
          'description': 'backup_personal_data 的数据类别；短信和通话记录只导出不写回',
        },
        'scope': {
          'type': 'string',
          'enum': ['config', 'full', 'apk'],
          'description':
              'backup_app_data 范围：config=配置包（shared_prefs、databases），full=完整数据（不含缓存），这两项需要 Root 或 uid 0 的 Shizuku；apk=仅安装包（含拆分 APK），无需 Root，恢复时交给系统安装器由用户确认',
        },
        'backupId': {
          'type': 'string',
          'description': 'backup_list 返回的备份 ID；恢复前务必先预览文件列表与覆盖范围',
        },
      },
      'required': ['action'],
    },
  );

  @override
  ToolRisk riskForArguments(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    if (arguments['preview'] == true && _requiresAndroidPlan(action)) {
      return ToolRisk.safe;
    }
    return _actionRisk(action, arguments);
  }

  static ToolRisk auditRiskForArguments(Map<String, dynamic> arguments) =>
      AndroidDeviceTool().riskForArguments(arguments);

  /// 审计用的“实际执行描述”：与模型意图分开保存。
  ///
  /// 只根据已校验的参数重新生成原生白名单命令/流程，不信任模型提供的任何
  /// 命令文本；写入内容被替换为长度占位符，避免把文件内容写进审计表。
  static Map<String, dynamic>? auditExecutionFor(
    Map<String, dynamic> arguments,
  ) =>
      AndroidDeviceTool()._auditExecution(arguments);

  Map<String, dynamic>? _auditExecution(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    if (action is! String) return null;
    if (!_requiresAndroidPlan(action)) {
      return {
        'mode': 'read_only_bridge',
        'bridgeMethod': action,
        'riskClass': _actionRisk(action, arguments).name,
        'reversible': true,
      };
    }
    final validationError = _validatePreviewArguments(action, arguments);
    if (validationError != null) {
      return {
        'mode': 'rejected_before_execution',
        'reason': validationError,
        'riskClass': _actionRisk(action, arguments).name,
      };
    }
    final safeArguments = _mutationArguments(arguments);
    final content = safeArguments['content'];
    if (content is String) {
      safeArguments['content'] = '<已省略 ${content.length} 个字符>';
    }
    final preview = _previewFor(action, safeArguments);
    return {
      'mode': _isRootAction(action) ? 'root_whitelist' : 'android_api',
      'privilegeRequirement': _privilegeRequirementFor(action, safeArguments),
      'executionRoute': preview['executionRoute'],
      'bridgeMethod': action,
      'command': preview['command'],
      'executionPlan': preview['executionPlan'],
      'riskClass': preview['riskClass'],
      'reversible': preview['reversible'],
      'rollback': preview['rollback'],
    }..removeWhere((key, value) => value == null);
  }

  @override
  bool requiresPreviewPlan(Map<String, dynamic> arguments) =>
      _requiresAndroidPlan(arguments['action']) && arguments['preview'] != true;

  @override
  Map<String, dynamic>? approvalDetailsFor(
    Map<String, dynamic> arguments,
  ) {
    if (!requiresPreviewPlan(arguments)) return null;
    final action = arguments['action'];
    final planId = arguments['planId'];
    if (action is! String ||
        planId is! String ||
        !_androidMutationPreviewLedger.hasPlan(
          planId,
          action,
          _mutationArguments(arguments),
        )) {
      return null;
    }
    return _previewFor(action, _mutationArguments(arguments))
      ..remove('arguments');
  }

  @override
  Map<String, dynamic> authorizeAfterApproval(
    Map<String, dynamic> arguments,
  ) {
    if (!requiresPreviewPlan(arguments)) {
      return Map<String, dynamic>.from(arguments);
    }
    final action = arguments['action'];
    final planId = arguments['planId'];
    if (action is! String || planId is! String) {
      throw const ToolApprovalAuthorizationException(
        '缺少操作计划；请先调用 android_device_preview',
      );
    }
    final ticketId = _androidMutationPreviewLedger.issueExecutionTicket(
      planId,
      action,
      _mutationArguments(arguments),
    );
    if (ticketId == null) {
      throw const ToolApprovalAuthorizationException(
        '操作计划已过期、已使用或与目标不匹配；请重新预览',
      );
    }
    return Map<String, dynamic>.from(arguments)
      ..remove('planId')
      ..remove('preview')
      ..['previewId'] = ticketId;
  }

  @override
  void rejectApproval(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    final planId = arguments['planId'];
    if (action is String && planId is String) {
      _androidMutationPreviewLedger.revokePlan(
        planId,
        action,
        _mutationArguments(arguments),
      );
    }
  }

  Future<ToolResult> preview(Map<String, dynamic> arguments) async {
    final action = arguments['action'];
    if (!_requiresAndroidPlan(action)) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '该 action 不需要预览计划',
      );
    }
    final validationError = _validatePreviewArguments(action, arguments);
    if (validationError != null) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: validationError,
      );
    }
    final planArguments = _mutationArguments(arguments);
    if (AndroidBackupActions.handles(action)) {
      // 恢复/删除前先读取归档真实内容，预览与审批详情才能列出文件、大小和覆盖范围。
      await AndroidBackupActions.loadInspection(
          _backupBridge, action, planArguments);
    }
    final planId = _androidMutationPreviewLedger.createPlan(
      action as String,
      planArguments,
    );
    return ToolResult.success(
      message: '已生成只读操作预览；执行前仍需按风险等级审批',
      data: {
        ..._previewFor(action, planArguments),
        'planId': planId,
      },
    );
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      _annotatePrivilegeOutcome(
        arguments['action'],
        await _executeAction(arguments),
      );

  /// 原生降级结果的统一解读：只打开了系统页面时不能宣称“已生效”。
  static ToolResult _annotatePrivilegeOutcome(
    Object? action,
    ToolResult result,
  ) {
    final data = result.data;
    if (!result.ok || data == null) return result;
    // 这些动作的目的本来就是打开页面/弹窗，打开即完成。
    if (action is String &&
        (action.startsWith('open_') ||
            action == 'request_shizuku_permission' ||
            action == 'choose_folder')) {
      return result;
    }
    final userAction = data['userActionRequired'] == true;
    final partial = data['partial'] == true;
    if (!userAction && !partial) return result;
    final nativeMessage = data['message']?.toString();
    final route = data['executedVia']?.toString();
    final detail = (nativeMessage == null || nativeMessage.isEmpty)
        ? result.message
        : nativeMessage;
    return ToolResult(
      ok: true,
      code: result.code,
      message: userAction
          ? '尚未直接生效，需要你在系统界面完成：$detail'
          : '部分生效${route == null ? '' : '（通道：$route）'}：$detail',
      data: data,
      effect: userAction ? ToolEffect.unknown : result.effect,
    );
  }

  Future<ToolResult> _executeAction(Map<String, dynamic> arguments) async {
    final action = arguments['action'];
    if (arguments['preview'] == true && _requiresAndroidPlan(action)) {
      return preview(arguments);
    }
    if (_requiresAndroidPlan(action)) {
      final previewId = arguments['previewId'];
      if (previewId is! String ||
          !_androidMutationPreviewLedger.consume(
            previewId,
            action as String,
            _mutationArguments(arguments),
          )) {
        return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: '缺少有效的匹配预览；请先生成预览，确认目标后再执行一次',
        );
      }
    }
    try {
      if (AndroidBackupActions.handles(action)) {
        return await AndroidBackupActions.execute(
          _backupBridge,
          action as String,
          arguments,
        );
      }
      switch (action) {
        case 'list_apps':
          final apps = await _bridge.listApps();
          return ToolResult.success(
            message: '找到 ${apps.length} 个可启动应用',
            data: {'apps': apps},
          );
        case 'privilege_status':
          final status = await _bridge.privilegeStatus();
          return ToolResult.success(
            message: '已读取 Root、Shizuku、特殊权限与本地 VPN 状态',
            data: status,
          );
        case 'network_filter_status':
          return ToolResult.success(
            message: '已读取本地 VPN 过滤器状态',
            data: await _bridge.networkFilterStatus(),
          );
        case 'request_shizuku_permission':
          final data = await _bridge.requestShizukuPermission();
          return ToolResult.success(
            message: data['granted'] == true
                ? '已获得 Shizuku 授权'
                : 'Shizuku 未授权：${data['reason'] ?? '用户拒绝或服务未运行'}',
            data: data,
            effect:
                data['granted'] == true ? ToolEffect.applied : ToolEffect.none,
          );
        case 'open_shizuku':
          return ToolResult.success(
            message: '已打开 Shizuku（未安装时打开下载页）；启动服务需在 Shizuku 内完成',
            data: await _bridge.openShizuku(),
            effect: ToolEffect.applied,
          );
        case 'grant_privileged_permissions':
          final data = await _bridge.grantPermissionsViaPrivilege();
          return ToolResult.success(
            message: '已通过特权通道授予 ${data['grantedCount'] ?? 0} 项权限',
            data: data,
            effect: ToolEffect.applied,
          );
        case 'open_special_permission':
          final kind = arguments['permissionKind'];
          if (kind is! String ||
              !androidSpecialPermissionKinds.contains(kind)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message:
                  'permissionKind 仅支持 ${androidSpecialPermissionKinds.join('、')}',
            );
          }
          final data = await _bridge.openSpecialPermission(kind);
          return ToolResult.success(
            message: data['granted'] == true
                ? '已获得 $kind 授权'
                : '已打开系统授权页；是否授权由你在系统界面决定',
            data: data,
            effect: ToolEffect.applied,
          );
        case 'open_app_details':
          final packageName = arguments['packageName'];
          if (packageName is! String || !_validPackageName(packageName)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '需要有效的 Android packageName',
            );
          }
          return ToolResult.success(
            message: '已打开应用详情页',
            data: await _bridge.openAppDetails(packageName.trim()),
            effect: ToolEffect.applied,
          );
        case 'set_network_filter':
          final enabled = arguments['enabled'];
          if (enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: 'set_network_filter 需要 enabled 布尔值',
            );
          }
          return ToolResult.success(
            message: enabled ? '已启用本地 VPN 过滤器' : '已停用本地 VPN 过滤器（规则保留）',
            data: await _bridge.setNetworkFilterEnabled(enabled),
            effect: ToolEffect.applied,
          );
        case 'set_app_network_block':
          final packageName = arguments['packageName'];
          final enabled = arguments['enabled'];
          if (packageName is! String ||
              !_validPackageName(packageName) ||
              enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '应用断网需要有效 packageName 和 enabled 布尔值',
            );
          }
          return ToolResult.success(
            message: enabled
                ? '已对 ${packageName.trim()} 断网（本地 VPN）'
                : '已恢复 ${packageName.trim()} 的网络',
            data: await _bridge.setAppNetworkBlock(
              packageName: packageName.trim(),
              enabled: enabled,
            ),
            effect: ToolEffect.applied,
          );
        case 'set_domain_block':
          final domain = arguments['domain'];
          final enabled = arguments['enabled'];
          if (domain is! String ||
              !_validHostsDomain(domain) ||
              enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '域名屏蔽需要有效域名和 enabled 布尔值',
            );
          }
          final normalizedDomain = domain.trim().toLowerCase();
          return ToolResult.success(
            message: enabled
                ? '已通过本地 VPN 屏蔽域名 $normalizedDomain'
                : '已移除域名 $normalizedDomain 的本地 VPN 屏蔽',
            data: await _bridge.setDomainBlock(
              domain: normalizedDomain,
              enabled: enabled,
            ),
            effect: ToolEffect.applied,
          );
        case 'root_status':
          return ToolResult.success(
              message: '已读取 Root 与设备能力状态', data: await _bridge.rootStatus());
        case 'device_info':
          return ToolResult.success(
              message: '已读取设备信息', data: await _bridge.deviceInfo());
        case 'storage_info':
          return ToolResult.success(
              message: '已读取存储空间信息', data: await _bridge.storageInfo());
        case 'network_info':
          return ToolResult.success(
              message: '已读取网络连接信息', data: await _bridge.networkInfo());
        case 'set_firewall_port_rule':
          final protocol = arguments['protocol'];
          final port = arguments['port'];
          final enabled = arguments['enabled'];
          if ((protocol != 'tcp' && protocol != 'udp') ||
              port is! num ||
              port != port.toInt() ||
              port < 1 ||
              port > 65535 ||
              enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '防火墙规则仅接受 tcp/udp 和 1–65535 端口',
            );
          }
          final data = await _bridge.setFirewallPortRule(
            protocol: protocol as String,
            port: port.toInt(),
            enabled: enabled,
          );
          final ipv6 =
              data['output']?.toString().contains('ipv6=applied') ?? false;
          return ToolResult.success(
            message: enabled
                ? '已请求阻止出站 ${protocol.toUpperCase()} $port 端口'
                    '${ipv6 ? '（IPv4/IPv6）' : '（IPv6 规则不可用或未生效，请核实设备支持）'}'
                : '已请求移除出站 ${protocol.toUpperCase()} $port 端口阻止规则'
                    '${ipv6 ? '（IPv4/IPv6）' : '（IPv6 规则不可用或未生效，请核实设备支持）'}',
            data: data,
            effect: ToolEffect.applied,
          );
        case 'set_hosts_block':
          final domain = arguments['domain'];
          final enabled = arguments['enabled'];
          if (domain is! String ||
              !_validHostsDomain(domain) ||
              enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: 'hosts 操作需要有效域名和 enabled 布尔值',
            );
          }
          final normalizedDomain = domain.trim().toLowerCase();
          final hostsData = await _bridge.setHostsBlock(
            domain: normalizedDomain,
            enabled: enabled,
          );
          final viaVpn = hostsData['executedVia'] == 'vpn';
          return ToolResult.success(
            message: enabled
                ? '已请求屏蔽域名 $normalizedDomain${viaVpn ? '（无 Root，已改用本地 VPN DNS 屏蔽）' : ''}'
                : '已请求移除域名 $normalizedDomain 的屏蔽规则${viaVpn ? '（本地 VPN）' : ''}',
            data: hostsData,
            effect: ToolEffect.applied,
          );
        case 'refresh_dns':
          return ToolResult.success(
            message: '已请求刷新系统 DNS 解析缓存',
            data: await _bridge.refreshDns(),
            effect: ToolEffect.applied,
          );
        case 'open_vpn_settings':
          return ToolResult.success(
            message: '已打开 Android VPN 设置；连接状态需由用户在系统页面操作',
            data: await _bridge.openVpnSettings(),
            effect: ToolEffect.applied,
          );
        case 'running_processes':
          return ToolResult.success(
            message: '已读取运行中的进程',
            data: {'processes': await _bridge.runningProcesses()},
          );
        case 'foreground_apps':
          return ToolResult.success(
            message: '已读取前台应用',
            data: {'apps': await _bridge.foregroundApps()},
          );
        case 'logcat_tail':
          final rawLines = arguments['lines'];
          final lines = rawLines is num ? rawLines.toInt().clamp(1, 500) : 120;
          return ToolResult.success(
            message: '已读取最近 Logcat',
            data: await _bridge.logcatTail(lines),
          );
        case 'crash_logs':
          final packageName = arguments['packageName'];
          if (packageName != null &&
              (packageName is! String || !_validPackageName(packageName))) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '崩溃日志过滤需要有效的 packageName',
            );
          }
          return ToolResult.success(
            message: '已读取崩溃日志',
            data: await _bridge
                .crashLogs(packageName is String ? packageName.trim() : null),
          );
        case 'app_info':
          final packageName = arguments['packageName'];
          if (packageName is! String || packageName.trim().isEmpty) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: '查询应用信息需要 packageName');
          }
          return ToolResult.success(
              message: '已读取应用信息',
              data: await _bridge.appInfo(packageName.trim()));
        case 'system_status':
          return ToolResult.success(
              message: '已读取系统状态', data: await _bridge.systemStatus());
        case 'traffic_info':
          return ToolResult.success(
              message: '已读取网络流量统计', data: await _bridge.trafficInfo());
        case 'traceroute':
          final host = arguments['host'];
          if (host is! String || !_validProbeHost(host)) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: 'Traceroute 主机参数无效');
          }
          return ToolResult.success(
            message: '已完成路由探测',
            data: await _bridge.traceroute(host.trim()),
          );
        case 'system_settings':
          return ToolResult.success(
              message: '已读取系统设置', data: await _bridge.systemSettings());
        case 'set_brightness':
          final value = arguments['value'];
          if (value is! num || value < 0 || value > 1) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: '亮度必须是 0 到 1 之间的数值');
          }
          return ToolResult.success(
            message: '已调整屏幕亮度',
            data: await _bridge.setBrightness(value.toDouble()),
            effect: ToolEffect.applied,
          );
        case 'set_volume':
          final stream = arguments['stream'];
          final value = arguments['value'];
          const streams = {
            'music',
            'ring',
            'alarm',
            'notification',
            'voice_call'
          };
          if (stream is! String ||
              !streams.contains(stream) ||
              value is! num ||
              value < 0 ||
              value > 1) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: '音量参数无效');
          }
          return ToolResult.success(
            message: '已调整系统音量',
            data: await _bridge.setVolume(stream, value.toDouble()),
            effect: ToolEffect.applied,
          );
        case 'set_auto_rotate':
          final enabled = arguments['enabled'];
          if (enabled is! bool) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: '自动旋转参数必须是布尔值');
          }
          return ToolResult.success(
            message: enabled ? '已开启自动旋转' : '已关闭自动旋转',
            data: await _bridge.setAutoRotate(enabled),
            effect: ToolEffect.applied,
          );
        case 'set_wifi':
        case 'set_bluetooth':
        case 'set_airplane_mode':
        case 'set_location':
        case 'set_do_not_disturb':
          final enabled = arguments['enabled'];
          if (enabled is! bool) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '系统开关必须提供 enabled 布尔值',
            );
          }
          final data = switch (action) {
            'set_wifi' => await _bridge.setWifi(enabled),
            'set_bluetooth' => await _bridge.setBluetooth(enabled),
            'set_airplane_mode' => await _bridge.setAirplaneMode(enabled),
            'set_location' => await _bridge.setLocationEnabled(enabled),
            'set_do_not_disturb' => await _bridge.setDoNotDisturb(enabled),
            _ => const <String, dynamic>{},
          };
          return ToolResult.success(
            message: enabled ? '已请求开启系统功能' : '已请求关闭系统功能',
            data: data,
            effect: ToolEffect.applied,
          );
        case 'set_refresh_rate':
        case 'set_font_scale':
        case 'set_animation_scale':
          final value = arguments['value'];
          final validValue = value is num &&
              switch (action) {
                'set_refresh_rate' => value >= 30 && value <= 240,
                'set_font_scale' => value >= 0.85 && value <= 1.4,
                _ => value >= 0 && value <= 10,
              };
          if (!validValue) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '系统显示设置数值超出允许范围',
            );
          }
          final number = value.toDouble();
          final data = switch (action) {
            'set_refresh_rate' => await _bridge.setRefreshRate(number),
            'set_font_scale' => await _bridge.setFontScale(number),
            _ => await _bridge.setAnimationScale(number),
          };
          return ToolResult.success(
            message: '已请求修改系统显示设置',
            data: data,
            effect: ToolEffect.applied,
          );
        case 'open_default_apps_settings':
          return ToolResult.success(
            message: '已打开默认应用设置；请在 Android 系统页面确认选择',
            data: await _bridge.openDefaultAppsSettings(),
            effect: ToolEffect.applied,
          );
        case 'open_do_not_disturb_settings':
          return ToolResult.success(
            message: '已打开勿扰模式权限设置；请在 Android 系统页面确认',
            data: await _bridge.openDoNotDisturbSettings(),
            effect: ToolEffect.applied,
          );
        case 'open_notification_settings':
          final packageName = arguments['packageName'];
          if (packageName != null &&
              (packageName is! String || !_validPackageName(packageName))) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '通知设置页面需要有效的 packageName',
            );
          }
          return ToolResult.success(
            message: '已打开通知设置；最终开关由用户在 Android 系统页面确认',
            data: await _bridge.openNotificationSettings(
              packageName is String ? packageName.trim() : null,
            ),
            effect: ToolEffect.applied,
          );
        case 'directory_size':
          final path = arguments['path'];
          if (path is! String || !_validRootFilePath(path)) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: '目录大小查询路径不在白名单内');
          }
          return ToolResult.success(
              message: '已读取目录大小',
              data: await _bridge.directorySize(path.trim()));
        case 'port_probe':
          final host = arguments['host'];
          final rawPort = arguments['port'];
          final port = rawPort is num ? rawPort.toInt() : 0;
          if (host is! String ||
              !_validProbeHost(host) ||
              port < 1 ||
              port > 65535) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments, message: '网络端口参数无效');
          }
          return ToolResult.success(
              message: '已完成端口探测',
              data: await _bridge.portProbe(host.trim(), port));
        case 'restart_app':
          final packageName = arguments['packageName'];
          if (packageName is! String || !_validPackageName(packageName)) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: '重启应用需要有效的 packageName');
          }
          return ToolResult.success(
            message: '已请求重启应用 $packageName',
            data: await _bridge.restartApp(packageName.trim()),
            effect: ToolEffect.applied,
          );
        case 'restart_service':
          final serviceName = arguments['serviceName'];
          if (serviceName is! String ||
              !_restartableServices.contains(serviceName.trim())) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '服务名不在可重启白名单中',
            );
          }
          return ToolResult.success(
            message: '已请求重启 Android 服务 ${serviceName.trim()}',
            data: await _bridge.restartService(serviceName.trim()),
            effect: ToolEffect.applied,
          );
        case 'app_permissions':
          final packageName = arguments['packageName'];
          if (packageName is! String || !_validPackageName(packageName)) {
            return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: '查询应用权限需要有效的 packageName');
          }
          return ToolResult.success(
              message: '已读取应用权限',
              data: await _bridge.appPermissions(packageName.trim()));
        case 'recent_apps':
          return ToolResult.success(
              message: '已读取最近使用应用', data: {'apps': await _bridge.recentApps()});
        case 'set_app_alias':
          final alias = arguments['alias'];
          final packageName = arguments['packageName'];
          if (alias is! String ||
              alias.trim().isEmpty ||
              alias.trim().length > 40 ||
              packageName is! String ||
              !_validPackageName(packageName)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '别名和 packageName 参数无效',
            );
          }
          return ToolResult.success(
            message: '已保存应用别名',
            data: await _bridge.setAppAlias(alias.trim(), packageName.trim()),
          );
        case 'list_app_aliases':
          return ToolResult.success(
            message: '已读取应用别名',
            data: {'aliases': await _bridge.listAppAliases()},
          );
        case 'launch_deep_link':
          final packageName = arguments['packageName'];
          final uri = arguments['deepLink'] ?? arguments['uri'];
          if (packageName is! String ||
              !_validPackageName(packageName) ||
              uri is! String ||
              !_validDeepLink(uri)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '深链启动参数无效',
            );
          }
          return ToolResult.success(
            message: '已请求打开应用深链',
            data: await _bridge.launchDeepLink(packageName.trim(), uri.trim()),
            effect: ToolEffect.applied,
          );
        case 'stop_app':
          final packageName = arguments['packageName'];
          if (packageName is! String || !_validPackageName(packageName)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '停止应用需要有效的 Android packageName',
            );
          }
          final result = await _bridge.stopApp(packageName.trim());
          return ToolResult.success(
            message: '已请求停止应用 $packageName',
            data: result,
            effect: ToolEffect.applied,
          );
        case 'kill_process':
          final pid = arguments['pid'];
          final processName = arguments['processName'];
          if (pid is! num ||
              pid <= 1 ||
              pid != pid.toInt() ||
              processName is! String ||
              !_validProcessName(processName)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '结束进程需要有效 PID 和进程名',
            );
          }
          return ToolResult.success(
            message: '已向指定进程发送终止信号',
            data: await _bridge.killProcess(pid.toInt(), processName.trim()),
            effect: ToolEffect.applied,
          );
        case 'clear_app_cache':
          final packageName = arguments['packageName'];
          if (packageName is! String || !_validPackageName(packageName)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '清理缓存需要有效的 Android packageName',
            );
          }
          final result = await _bridge.clearAppCache(packageName.trim());
          return ToolResult.success(
            message: '已请求清理应用缓存 $packageName',
            data: result,
            effect: ToolEffect.applied,
          );
        case 'read_root_file':
          final path = arguments['path'];
          if (path is! String || !_validRootFilePath(path)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message:
                  'Root 文件读取只允许 /sdcard、/storage/emulated/0 或 /data/local/tmp 下的绝对路径',
            );
          }
          return ToolResult.success(
            message: '已读取受限 Root 文件',
            data: await _bridge.readRootFile(path.trim()),
          );
        case 'list_root_files':
          final path = arguments['path'];
          if (path is! String || !_validRootFilePath(path)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message:
                  'Root 文件列举只允许 /sdcard、/storage/emulated/0 或 /data/local/tmp 下的绝对路径',
            );
          }
          return ToolResult.success(
            message: '已列举受限 Root 目录',
            data: await _bridge.listRootFiles(path.trim()),
          );
        case 'write_root_file':
          final path = arguments['path'];
          final content = arguments['content'];
          if (path is! String ||
              !_validRootFilePath(path) ||
              content is! String ||
              content.length > 65536) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: 'Root 写入只允许白名单路径，文本不得超过 64 KiB',
            );
          }
          return ToolResult.success(
            message: '已写入受限 Root 文件',
            data: await _bridge.writeRootFile(path.trim(), content),
            effect: ToolEffect.applied,
          );
        case 'delete_root_file':
          final path = arguments['path'];
          if (path is! String ||
              !_validRootFilePath(path) ||
              _isRootDirectory(path)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '只能删除白名单目录下的文件，不能删除目录本身',
            );
          }
          return ToolResult.success(
            message: '已删除受限 Root 文件',
            data: await _bridge.deleteRootFile(path.trim()),
            effect: ToolEffect.applied,
          );
        case 'move_root_file':
          final source = arguments['source'];
          final destination = arguments['destination'];
          if (source is! String ||
              destination is! String ||
              !_validRootFilePath(source) ||
              !_validRootFilePath(destination) ||
              _isRootDirectory(source) ||
              _isRootDirectory(destination)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: 'Root 移动只允许白名单目录下的文件路径',
            );
          }
          return ToolResult.success(
            message: '已移动受限 Root 文件',
            data: await _bridge.moveRootFile(source.trim(), destination.trim()),
            effect: ToolEffect.applied,
          );
        case 'network_probe':
          final host = arguments['host'];
          if (host is! String || !_validProbeHost(host)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '网络探测需要合法的域名或 IP',
            );
          }
          return ToolResult.success(
            message: '已完成网络连通性探测',
            data: await _bridge.networkProbe(host.trim()),
          );
        case 'compress_root_files':
          final rawSources = arguments['sources'];
          final destination = arguments['destination'];
          final sources = rawSources is List
              ? rawSources.whereType<String>().map((e) => e.trim()).toList()
              : const <String>[];
          if (sources.isEmpty ||
              sources.length > 50 ||
              destination is! String ||
              !_validRootFilePath(destination) ||
              _isRootDirectory(destination) ||
              sources.any((path) => !_validRootFilePath(path))) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '压缩仅允许白名单目录内最多 50 个源路径',
            );
          }
          return ToolResult.success(
            message: '已压缩受限 Root 文件',
            data: await _bridge.compressRootFiles(sources, destination.trim()),
            effect: ToolEffect.applied,
          );
        case 'extract_root_archive':
          final archive = arguments['archive'];
          final destination = arguments['destination'];
          if (archive is! String ||
              destination is! String ||
              !_validRootFilePath(archive) ||
              !_validRootFilePath(destination) ||
              _isRootDirectory(archive) ||
              _isRootDirectory(destination)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '解压仅允许白名单目录内的压缩包和目标目录',
            );
          }
          return ToolResult.success(
            message: '已解压受限 Root 压缩包',
            data: await _bridge.extractRootArchive(
              archive.trim(),
              destination.trim(),
            ),
            effect: ToolEffect.applied,
          );
        case 'search_files_filtered':
          final query = arguments['query'];
          final extension = arguments['extension'];
          final after = arguments['modifiedAfterMs'];
          final before = arguments['modifiedBeforeMs'];
          if (query is! String ||
              query.trim().isEmpty ||
              (extension != null &&
                  (extension is! String || !_validExtension(extension))) ||
              (after != null && after is! num) ||
              (before != null && before is! num)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '文件筛选参数无效',
            );
          }
          return ToolResult.success(
            message: '已完成带条件的本地文件搜索',
            data: await _bridge.searchFilesFiltered(
              query: query.trim(),
              extension: extension is String ? extension.trim() : null,
              modifiedAfterMs: after is num ? after.toInt() : null,
              modifiedBeforeMs: before is num ? before.toInt() : null,
            ),
          );
        case 'file_operation':
          final batchUris = arguments['uris'];
          if (batchUris is List) {
            final operation = arguments['operation'];
            final destinationUri = arguments['destinationUri'];
            if (!_validFileOperation(
              operation,
              arguments['uri'],
              destinationUri,
              arguments['newName'],
              batchUris,
            )) {
              return ToolResult.failure(
                code: ToolCodes.invalidArguments,
                message: '批量文件操作只支持有效 URI 列表以及删除、复制或移动',
              );
            }
            final result = await _bridge.fileOperationBatch(
              operation: operation as String,
              uris: batchUris.cast<String>(),
              destinationUri: destinationUri is String ? destinationUri : null,
            );
            final failedCount = result['failedCount'] is num
                ? (result['failedCount'] as num).toInt()
                : 0;
            final appliedCount = result['appliedCount'] is num
                ? (result['appliedCount'] as num).toInt()
                : 0;
            if (failedCount > 0 && appliedCount == 0) {
              return ToolResult.failure(
                code: ToolCodes.toolError,
                message: '批量操作未完成：${result['results'] ?? result}',
              );
            }
            return ToolResult.success(
              message: failedCount == 0
                  ? '批量操作已完成，共处理 ${batchUris.length} 个文件'
                  : '批量操作部分完成：成功 $appliedCount 个，失败 $failedCount 个；请核对逐项结果',
              data: result,
              effect: appliedCount > 0 ? ToolEffect.applied : ToolEffect.none,
            );
          }
          final operation = arguments['operation'];
          final uri = arguments['uri'];
          final destinationUri = arguments['destinationUri'];
          final newName = arguments['newName'];
          if (!_validFileOperation(operation, uri, destinationUri, newName)) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '文件操作参数无效；只能重命名、删除或在同一授权目录中复制/移动',
            );
          }
          return ToolResult.success(
            message: '已执行 SAF 文件操作',
            data: await _bridge.fileOperation(
              operation: operation as String,
              uri: uri as String,
              destinationUri: destinationUri is String ? destinationUri : null,
              newName: newName is String ? newName : null,
            ),
            effect: ToolEffect.applied,
          );
        case 'refresh_file_index':
          return ToolResult.success(
            message: '已刷新授权目录的本地文件索引',
            data: await _bridge.refreshSearchIndex(),
          );
        case 'share_file':
          final uri = arguments['uri'];
          if (uri is! String || !uri.startsWith('content://')) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '只能分享系统文件选择器返回的 content URI',
            );
          }
          await _bridge.shareFile(uri);
          return ToolResult.success(
            message: '已打开系统分享面板',
            effect: ToolEffect.applied,
          );
        case 'launch_app':
          final packageName = arguments['packageName'];
          if (packageName is! String || packageName.trim().isEmpty) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '启动应用需要有效的 packageName',
            );
          }
          await _bridge.launchApp(packageName.trim());
          return ToolResult.success(
            message: '已启动应用 $packageName',
            data: {'packageName': packageName},
            effect: ToolEffect.applied,
          );
        case 'launch_app_by_name':
          final appName = arguments['appName'] ?? arguments['query'];
          if (appName is! String || appName.trim().isEmpty) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '按名称启动应用需要非空 appName',
            );
          }
          final launch = await _bridge.launchAppByName(appName.trim());
          if (launch['status'] == 'ambiguous') {
            final candidates = (launch['candidates'] as List?) ?? const [];
            return ToolResult.success(
              message: '找到多个可能的应用，需要用户选择',
              data: {'status': 'ambiguous', 'candidates': candidates},
            );
          }
          if (launch['status'] != 'started') {
            return ToolResult.failure(
              code: ToolCodes.notFound,
              message: '没有找到可以启动的匹配应用',
            );
          }
          return ToolResult.success(
            message: '已启动应用 ${launch['label'] ?? appName}',
            data: launch,
            effect: ToolEffect.applied,
          );
        case 'choose_folder':
          await _bridge.chooseFolder();
          return ToolResult.success(message: '文件夹授权完成，可搜索该目录及其子目录');
        case 'list_authorized_folders':
          return ToolResult.success(
            message: '已列出用户授权的文件夹',
            data: await _bridge.listAuthorizedFoldersResult(),
          );
        case 'search_files':
          final query = arguments['query'];
          if (query is! String || query.trim().isEmpty) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '文件搜索需要非空 query',
            );
          }
          final requestId = UniqueId.generate('device_search');
          late final Map<String, dynamic> result;
          try {
            result = await _bridge
                .searchFiles(query.trim(), requestId)
                .timeout(const Duration(seconds: 30));
          } on TimeoutException {
            await _bridge.cancelSearch(requestId);
            return ToolResult.failure(
              code: ToolCodes.timeout,
              message: '本地搜索超过 30 秒，已取消',
            );
          }
          if (result['needsFolderPermission'] == true) {
            return ToolResult.success(
              message: '首次搜索前需要选择一个文件夹授权',
              data: {'needsFolderPermission': true, 'files': const []},
            );
          }
          final files = (result['files'] as List?) ?? const [];
          return ToolResult.success(
            message: result['cancelled'] == true
                ? '搜索已取消，找到 ${files.length} 个匹配文件'
                : '找到 ${files.length} 个匹配文件',
            data: {
              'files': files,
              'truncated': result['truncated'] == true,
              'cancelled': result['cancelled'] == true,
              'indexUsed': result['indexUsed'] == true,
              'indexRefreshedRoots': result['indexRefreshedRoots'] ?? 0,
              'indexedDocuments': result['indexedDocuments'] ?? 0,
              'indexComplete': result['indexComplete'] == true,
              'indexUpdatedAtMs': result['indexUpdatedAtMs'] ?? 0,
              'incompleteRoots': result['incompleteRoots'] ?? const [],
            },
          );
        case 'open_file':
          final uri = arguments['uri'];
          if (uri is! String || !uri.startsWith('content://')) {
            return ToolResult.failure(
              code: ToolCodes.invalidArguments,
              message: '只能打开系统文件选择器返回的 content URI',
            );
          }
          await _bridge.openFile(uri);
          return ToolResult.success(
            message: '已请求系统打开所选文件',
            effect: ToolEffect.applied,
          );
        default:
          return ToolResult.failure(
            code: ToolCodes.invalidArguments,
            message: '不支持的手机操作: $action',
          );
      }
    } on PlatformException catch (error) {
      final code = switch (error.code) {
        'NOT_FOUND' => ToolCodes.notFound,
        'CANCELLED' => ToolCodes.cancelled,
        'PERMISSION_REQUIRED' => ToolCodes.permissionRequired,
        'PERMISSION_DENIED' => ToolCodes.permissionRequired,
        'SELINUX_DENIED' => ToolCodes.permissionRequired,
        'ROOT_UNAVAILABLE' || 'ROOT_DENIED' => ToolCodes.rootRequired,
        'TIMEOUT' => ToolCodes.timeout,
        'UNSUPPORTED_OPERATION' => ToolCodes.capabilityUnavailable,
        'NO_LAUNCH_INTENT' => ToolCodes.capabilityUnavailable,
        'UNAVAILABLE' => ToolCodes.capabilityUnavailable,
        _ => AndroidBackupActions.codeForPlatformError(error.code),
      };
      final details = error.details;
      return ToolResult.failure(
        code: code,
        message: error.message ?? 'Android 操作失败 (${error.code})',
        data: {
          'nativeCode': error.code,
          if (details is Map)
            for (final entry in details.entries)
              entry.key.toString(): entry.value,
        },
      );
    } on MissingPluginException {
      return ToolResult.failure(
        code: ToolCodes.platformUnsupported,
        message: '手机本地控制仅支持 Android 原生应用',
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: 'Android 操作失败: $error',
      );
    }
  }

  bool _validPackageName(String value) => RegExp(
        r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$',
      ).hasMatch(value.trim());

  bool _isMutatingAction(Object? action) =>
      _mutatingAndroidActions.contains(action);

  bool _requiresAndroidPlan(Object? action) =>
      _mutatingAndroidActions.contains(action) ||
      _rootAndroidActions.contains(action);

  String? _validatePreviewArguments(
    Object? action,
    Map<String, dynamic> arguments,
  ) {
    final packageName = arguments['packageName'];
    final path = arguments['path'];
    if (AndroidBackupActions.handles(action)) {
      return AndroidBackupActions.validate(action, arguments);
    }
    switch (action) {
      case 'launch_app':
      case 'stop_app':
      case 'restart_app':
      case 'clear_app_cache':
      case 'app_permissions':
      case 'open_app_details':
        if (packageName is! String || !_validPackageName(packageName)) {
          return '需要有效的 Android packageName';
        }
      case 'set_app_network_block':
        if (packageName is! String ||
            !_validPackageName(packageName) ||
            arguments['enabled'] is! bool) {
          return '应用断网需要有效 packageName 和 enabled 布尔值';
        }
      case 'set_domain_block':
        final domain = arguments['domain'];
        if (domain is! String ||
            !_validHostsDomain(domain) ||
            arguments['enabled'] is! bool) {
          return '域名屏蔽需要有效域名和 enabled 布尔值';
        }
      case 'set_network_filter':
        if (arguments['enabled'] is! bool) {
          return 'set_network_filter 需要 enabled 布尔值';
        }
      case 'open_special_permission':
        if (!androidSpecialPermissionKinds
            .contains(arguments['permissionKind'])) {
          return 'permissionKind 仅支持 ${androidSpecialPermissionKinds.join('、')}';
        }
      case 'kill_process':
        final pid = arguments['pid'];
        final processName = arguments['processName'];
        if (pid is! num ||
            pid <= 1 ||
            pid != pid.toInt() ||
            processName is! String ||
            !_validProcessName(processName)) {
          return '结束进程需要有效 PID 和进程名';
        }
      case 'restart_service':
        final serviceName = arguments['serviceName'];
        if (serviceName is! String ||
            !_restartableServices.contains(serviceName.trim())) {
          return '服务名不在可重启白名单中（logd、statsd）';
        }
      case 'set_firewall_port_rule':
        final protocol = arguments['protocol'];
        final port = arguments['port'];
        if ((protocol != 'tcp' && protocol != 'udp') ||
            port is! num ||
            port != port.toInt() ||
            port < 1 ||
            port > 65535 ||
            arguments['enabled'] is! bool) {
          return '防火墙规则仅接受 tcp/udp 和 1–65535 端口';
        }
      case 'set_hosts_block':
        final domain = arguments['domain'];
        if (domain is! String ||
            !_validHostsDomain(domain) ||
            arguments['enabled'] is! bool) {
          return 'hosts 操作需要有效域名和 enabled 布尔值';
        }
      case 'launch_app_by_name':
        final name = arguments['appName'] ?? arguments['query'];
        if (name is! String || name.trim().isEmpty) return '应用名称不能为空';
      case 'launch_deep_link':
        final uri = arguments['deepLink'] ?? arguments['uri'];
        if (packageName is! String ||
            !_validPackageName(packageName) ||
            uri is! String ||
            !_validDeepLink(uri)) {
          return '深链启动参数无效';
        }
      case 'set_app_alias':
        final alias = arguments['alias'];
        if (alias is! String ||
            alias.trim().isEmpty ||
            alias.trim().length > 40 ||
            packageName is! String ||
            !_validPackageName(packageName)) {
          return '别名和 packageName 参数无效';
        }
      case 'write_root_file':
        final content = arguments['content'];
        if (path is! String ||
            !_validRootFilePath(path) ||
            content is! String ||
            content.length > 65536) {
          return 'Root 写入仅允许白名单路径，内容上限为 64 KiB';
        }
      case 'delete_root_file':
        if (path is! String ||
            !_validRootFilePath(path) ||
            _isRootDirectory(path)) {
          return '只能删除白名单目录下的文件';
        }
      case 'move_root_file':
        final source = arguments['source'];
        final destination = arguments['destination'];
        if (source is! String ||
            destination is! String ||
            !_validRootFilePath(source) ||
            !_validRootFilePath(destination) ||
            _isRootDirectory(source) ||
            _isRootDirectory(destination)) {
          return 'Root 移动只允许白名单目录下的文件路径';
        }
      case 'compress_root_files':
        final rawSources = arguments['sources'];
        final destination = arguments['destination'];
        if (rawSources is! List ||
            rawSources.isEmpty ||
            rawSources.length > 50 ||
            rawSources
                .any((item) => item is! String || !_validRootFilePath(item)) ||
            destination is! String ||
            !_validRootFilePath(destination) ||
            _isRootDirectory(destination)) {
          return '压缩仅允许白名单目录内最多 50 个源路径';
        }
      case 'extract_root_archive':
        final archive = arguments['archive'];
        final destination = arguments['destination'];
        if (archive is! String ||
            destination is! String ||
            !_validRootFilePath(archive) ||
            !_validRootFilePath(destination) ||
            _isRootDirectory(archive) ||
            _isRootDirectory(destination)) {
          return '解压路径必须位于白名单目录内';
        }
      case 'directory_size':
      case 'read_root_file':
      case 'list_root_files':
        if (path is! String || !_validRootFilePath(path)) {
          return 'Root 只读查询路径必须是白名单内的绝对路径';
        }
      case 'set_brightness':
        final value = arguments['value'];
        if (value is! num || value < 0 || value > 1) {
          return '亮度必须在 0 到 1 之间';
        }
      case 'set_volume':
        final stream = arguments['stream'];
        final value = arguments['value'];
        if (stream is! String ||
            !{'music', 'ring', 'alarm', 'notification', 'voice_call'}
                .contains(stream) ||
            value is! num ||
            value < 0 ||
            value > 1) {
          return '音量参数无效';
        }
      case 'set_auto_rotate':
        if (arguments['enabled'] is! bool) return '自动旋转参数必须是布尔值';
      case 'set_wifi':
      case 'set_bluetooth':
      case 'set_airplane_mode':
      case 'set_location':
      case 'set_do_not_disturb':
        if (arguments['enabled'] is! bool) return '系统开关需要提供 enabled 布尔值';
      case 'set_refresh_rate':
        final value = arguments['value'];
        if (value is! num || value < 30 || value > 240) {
          return '刷新率必须在 30 到 240 Hz 范围内';
        }
      case 'set_font_scale':
        final value = arguments['value'];
        if (value is! num || value < 0.85 || value > 1.4) {
          return '字体缩放必须在 0.85 到 1.4 之间';
        }
      case 'set_animation_scale':
        final value = arguments['value'];
        if (value is! num || value < 0 || value > 10) {
          return '动画倍率必须在 0 到 10 之间';
        }
      case 'open_notification_settings':
        if (packageName != null &&
            (packageName is! String || !_validPackageName(packageName))) {
          return '通知设置页面需要有效的 packageName';
        }
      case 'open_file':
      case 'share_file':
        final uri = arguments['uri'];
        if (uri is! String || !uri.startsWith('content://')) {
          return '只能操作系统文件选择器返回的 content URI';
        }
      case 'file_operation':
        if (!_validFileOperation(
          arguments['operation'],
          arguments['uri'],
          arguments['destinationUri'],
          arguments['newName'],
          arguments['uris'],
        )) {
          return '文件操作参数无效；检查 operation、文件 URI、目标目录或新文件名';
        }
    }
    return null;
  }

  Map<String, dynamic> _previewFor(
    Object? action,
    Map<String, dynamic> arguments,
  ) {
    final route = _executionRouteFor(action, arguments);
    if (AndroidBackupActions.handles(action)) {
      return AndroidBackupActions.previewFor(
        action as String,
        arguments,
        riskClass: _actionRisk(action, arguments).name,
      )..addAll({if (route != null) 'executionRoute': route});
    }
    final impact = switch (action) {
      'directory_size' => '通过 Root 递归统计指定目录大小；不读取文件内容或修改数据',
      'read_root_file' => '通过 Root 读取指定文件，最多返回 64 KiB；文件内容可能包含敏感信息',
      'list_root_files' => '通过 Root 列举指定目录，输出最多 32 KiB；文件名和元数据可能敏感',
      'clear_app_cache' => '删除指定应用的 cache 和 code_cache 内容；不删除账号、设置或数据库',
      'kill_process' => '向指定 PID 发送 SIGTERM；未保存的数据可能丢失，系统核心进程会被拒绝',
      'restart_service' =>
        '请求 init 重启白名单服务 ${arguments['serviceName']}；服务可能暂时不可用，设备 ROM 可能拒绝该请求',
      'set_firewall_port_rule' =>
        '${arguments['enabled'] == true ? '阻止' : '移除阻止规则'}出站 ${arguments['protocol']?.toString().toUpperCase()} ${arguments['port']} 端口；可能影响依赖该端口的应用或网络连接',
      'set_hosts_block' =>
        '${arguments['enabled'] == true ? '屏蔽' : '解除屏蔽'}域名 ${arguments['domain']}；会影响此设备上所有应用对该域名的解析',
      'refresh_dns' => '清除系统默认网络的 DNS 解析缓存；不会修改 DNS 服务器配置',
      'open_vpn_settings' => '打开 Android VPN 设置页；由用户在系统页面启用、停用或配置 VPN',
      'set_airplane_mode' => '飞行模式会中断蜂窝、Wi-Fi 和蓝牙连接，可能切断远程控制',
      'set_wifi' => '修改 Wi-Fi 状态，可能切断远程控制',
      'set_bluetooth' => '修改蓝牙连接状态，可能中断已连接设备',
      'set_location' => '修改系统定位服务状态',
      'set_do_not_disturb' => '修改系统勿扰状态，可能静默通知和来电',
      'set_refresh_rate' => '将屏幕刷新率设为请求值；设备必须支持该模式',
      'set_font_scale' => '修改全局字体缩放比例',
      'set_animation_scale' => '同时修改窗口、转场和动画倍率',
      'open_default_apps_settings' ||
      'open_do_not_disturb_settings' ||
      'open_notification_settings' =>
        '打开 Android 系统设置页面；最终选择仍由用户在系统界面完成',
      'file_operation' => _fileOperationImpact(arguments),
      'delete_root_file' => '删除目标文件，通常不可撤销',
      'write_root_file' => '覆盖目标文件内容，无法保证撤销',
      'move_root_file' => '移动或重命名目标文件，可能覆盖已有目标',
      'set_brightness' ||
      'set_volume' ||
      'set_auto_rotate' =>
        '修改当前设备设置，可再次调整恢复',
      'share_file' => '打开系统分享面板，可能把文件交给其他应用',
      'request_shizuku_permission' =>
        '弹出 Shizuku 授权对话框；授权后 NEXUS 可用 adb 身份执行白名单命令',
      'open_shizuku' => '打开 Shizuku 应用；未安装时打开下载页',
      'grant_privileged_permissions' =>
        '通过 Root/Shizuku 为 NEXUS 自身授予 WRITE_SECURE_SETTINGS、勿扰、使用情况访问、READ_LOGS 等权限，之后无需特权也能直接调用系统 API',
      'open_special_permission' =>
        '打开 ${arguments['permissionKind']} 的系统授权页；是否授权由你决定',
      'open_app_details' => '打开该应用的系统详情页',
      'set_network_filter' => arguments['enabled'] == true
          ? '启动本地 VPN 过滤器；首次需要你允许 VPN 连接，并会断开其它 VPN'
          : '停止本地 VPN 过滤器；已保存的规则保留，重新启用即恢复',
      'set_app_network_block' => arguments['enabled'] == true
          ? '通过本地 VPN 阻断 ${arguments['packageName']} 的网络；首次需要你允许 VPN 连接，并会断开其它 VPN'
          : '移除 ${arguments['packageName']} 的断网规则',
      'set_domain_block' => arguments['enabled'] == true
          ? '通过本地 VPN 对 ${arguments['domain']} 返回 NXDOMAIN，影响所有应用；自带 DoH 的应用可能绕过'
          : '移除 ${arguments['domain']} 的本地 VPN 屏蔽',
      _ => '会启动应用、打开页面或改变设备文件状态',
    };
    return {
      'preview': true,
      'action': action,
      'arguments': Map<String, dynamic>.from(arguments)..remove('preview'),
      'target': _previewTarget(action, arguments),
      'scope': _previewScope(action, arguments),
      'impact': impact,
      'riskClass': _actionRisk(action, arguments).name,
      'command': _rootCommandFor(action, arguments),
      'executionPlan': _executionPlanFor(action, arguments),
      'reversible': !_isIrreversibleAction(action, arguments),
      'rollback': _rollbackFor(action, arguments),
      'requiresConfirmation': true,
      'mustWaitForUser': true,
      'executionRoute': route,
    }..removeWhere((key, value) => value == null);
  }

  /// 各动作需要的最低特权。null 表示只走普通系统 API / 应用自身权限。
  static String? _privilegeRequirementFor(
    Object? action,
    Map<String, dynamic> arguments,
  ) =>
      switch (action) {
        'set_wifi' ||
        'set_bluetooth' ||
        'set_airplane_mode' ||
        'set_location' ||
        'set_do_not_disturb' ||
        'set_animation_scale' ||
        'stop_app' ||
        'restart_app' ||
        'grant_privileged_permissions' =>
          'shell',
        'kill_process' ||
        'restart_service' ||
        'refresh_dns' ||
        'set_firewall_port_rule' ||
        'set_hosts_block' ||
        'clear_app_cache' =>
          'root_uid',
        'backup_app_data' => arguments['scope'] == 'apk' ? null : 'root_uid',
        'restore_app_data' =>
          arguments['backupId']?.toString().trim().startsWith('apk-') == true
              ? null
              : 'root_uid',
        'directory_size' ||
        'read_root_file' ||
        'list_root_files' ||
        'write_root_file' ||
        'delete_root_file' ||
        'move_root_file' ||
        'compress_root_files' ||
        'extract_root_archive' ||
        'backup_directory' =>
          'storage',
        _ => null,
      };

  /// 没有可用特权通道时，原生层的降级方式（null = 没有降级，执行会失败）。
  static String? _privilegeFallbackFor(Object? action) => switch (action) {
        'set_wifi' => 'Android 9 及以下直接调用 WifiManager；更高版本打开 Wi-Fi 面板由你手动切换',
        'set_bluetooth' => '有“附近设备”权限时调用系统蓝牙 API；否则打开蓝牙设置页',
        'set_airplane_mode' => '打开飞行模式设置页，由你手动切换',
        'set_location' => '打开定位设置页，由你手动切换',
        'set_do_not_disturb' => '已授予勿扰权限时直接用系统 API；否则打开勿扰授权页',
        'set_animation_scale' => '已授予 WRITE_SECURE_SETTINGS 时直接写入；否则打开开发者选项页',
        'stop_app' || 'restart_app' => '结束该应用的后台进程并打开应用详情页，需要你点“强行停止”（部分生效）',
        'clear_app_cache' =>
          'Android 14+ 且 Shizuku 可用时用 pm clear --cache-only；否则打开应用详情页由你清除缓存',
        'set_hosts_block' => '改用本地 VPN 的 DNS 屏蔽（首次需要你允许 VPN 连接）',
        'refresh_dns' => '无法免 Root 刷新；可切换一次飞行模式或 Wi-Fi 达到同样效果',
        'set_firewall_port_rule' =>
          '端口级规则需要 Root；可改用 set_app_network_block 对应用整体断网',
        'directory_size' ||
        'read_root_file' ||
        'list_root_files' ||
        'write_root_file' ||
        'delete_root_file' ||
        'move_root_file' ||
        'compress_root_files' ||
        'extract_root_archive' ||
        'backup_directory' =>
          '/sdcard 路径可在授予“所有文件访问”后以应用身份执行（open_special_permission permissionKind=all_files）',
        'backup_app_data' => '无 Root 可改用 scope=apk 只备份安装包',
        _ => null,
      };

  static String _routeLabel(Object? route) => switch (route) {
        'root' => 'Root（su）',
        'shizuku' => 'Shizuku（adb/uid 2000 或 uid 0）',
        'app' => '应用自身权限（所有文件访问）',
        _ => '$route',
      };

  Map<String, dynamic>? _executionRouteFor(
    Object? action,
    Map<String, dynamic> arguments,
  ) {
    final requirement = _privilegeRequirementFor(action, arguments);
    if (requirement == null) return null;
    final fallback = _privilegeFallbackFor(action);
    final snapshot = _privilegeRouteSnapshot;
    if (snapshot == null || !snapshot.fresh) {
      return {
        'requirement': requirement,
        'route': 'unknown',
        'label':
            '执行时按 Root → Shizuku → 系统 API → 系统设置页依次探测；可先调用 privilege_status 查看当前可用通道',
        if (fallback != null) 'fallback': fallback,
      };
    }
    final path = (arguments['path'] ?? arguments['source'])?.toString() ?? '';
    final key = switch (requirement) {
      'shell' => 'shell',
      'root_uid' => 'rootUid',
      _ => path.trim().startsWith('/data/local/tmp')
          ? 'storageDataLocalTmp'
          : 'storage',
    };
    final route = snapshot.routes[key];
    return {
      'requirement': requirement,
      'route': route ?? 'fallback',
      'label': route != null
          ? '将通过 ${_routeLabel(route)} 执行'
          : fallback != null
              ? '当前没有可用的特权通道：$fallback'
              : '当前没有可用的特权通道，执行会失败；需要 Root${requirement == 'root_uid' ? '（或以 Root 启动的 Shizuku）' : ' 或 Shizuku'}',
      if (route == null && fallback != null) 'fallback': fallback,
      if (!snapshot.rootProbed && route != 'root')
        'note': 'Root 尚未检查；实际执行时仍会优先尝试 Root',
      'statusAgeSeconds':
          DateTime.now().difference(snapshot.fetchedAt).inSeconds,
    };
  }

  bool _isIrreversibleAction(
    Object? action,
    Map<String, dynamic> arguments,
  ) =>
      action == 'file_operation'
          ? arguments['operation'] == 'delete'
          : {
              'clear_app_cache',
              'kill_process',
              'delete_root_file',
              'write_root_file',
              'compress_root_files',
              'extract_root_archive',
              ...androidBackupIrreversibleActions,
            }.contains(action);

  bool _isDangerousAction(
    Object? action,
    Map<String, dynamic> arguments,
  ) =>
      _isIrreversibleAction(action, arguments) ||
      const {
        'set_wifi',
        'set_bluetooth',
        'set_airplane_mode',
        'set_location',
        'set_do_not_disturb',
        'restart_service',
        'set_firewall_port_rule',
        'set_hosts_block',
        'set_network_filter',
        'set_app_network_block',
        'set_domain_block',
        'grant_privileged_permissions',
      }.contains(action);

  ToolRisk _actionRisk(
    Object? action,
    Map<String, dynamic> arguments,
  ) {
    // 只复制安装包：不需要 Root，也不读取应用私有数据。
    if (action == 'backup_app_data' && arguments['scope'] == 'apk') {
      return ToolRisk.requiresConfirmation;
    }
    if (_isRootAction(action) || _isDangerousAction(action, arguments)) {
      return ToolRisk.dangerous;
    }
    if (_isMutatingAction(action) ||
        const {'crash_logs', 'logcat_tail'}.contains(action)) {
      return ToolRisk.requiresConfirmation;
    }
    return ToolRisk.safe;
  }

  bool _isRootAction(Object? action) => _rootAndroidActions.contains(action);

  String _fileOperationImpact(Map<String, dynamic> arguments) {
    final operation = arguments['operation'];
    final uris = arguments['uris'];
    final count = uris is List ? uris.length : 1;
    final isBatch = uris is List;
    return switch (operation) {
      'rename' => '在授权目录内重命名单个文件',
      'delete' =>
        isBatch ? '永久删除授权目录中的 $count 个目标文件；删除后不能通过 SAF 撤销' : '永久删除授权目录中的目标文件',
      'copy' =>
        isBatch ? '复制 $count 个文件到同一授权存储提供方中的目标目录' : '复制单个文件到同一授权存储提供方中的目标目录',
      'move' =>
        isBatch ? '移动 $count 个文件到同一授权存储提供方中的目标目录' : '移动单个文件到同一授权存储提供方中的目标目录',
      _ => '修改授权目录中的文件',
    };
  }

  String _fileOperationTarget(Map<String, dynamic> arguments) {
    final operation = arguments['operation'];
    final uris = arguments['uris'];
    final destination = arguments['destinationUri'];
    if (uris is! List) {
      return '$operation：${arguments['uri']}'
          '${destination is String ? ' → $destination' : ''}'
          '${arguments['newName'] is String ? ' → ${arguments['newName']}' : ''}';
    }
    final shown =
        uris.take(10).map((uri) => uri is String ? uri.trim() : uri).join(', ');
    final remainder = uris.length > 10 ? '，另有 ${uris.length - 10} 个' : '';
    return '$operation ${uris.length} 个文件：$shown$remainder'
        '${destination is String ? ' → $destination' : ''}';
  }

  String _previewTarget(Object? action, Map<String, dynamic> arguments) {
    return switch (action) {
      'launch_app_by_name' =>
        '应用：${arguments['appName'] ?? arguments['query']}（尚未解析实际包名）',
      'launch_app' ||
      'stop_app' ||
      'restart_app' ||
      'clear_app_cache' ||
      'app_permissions' =>
        '应用包名：${arguments['packageName']}',
      'restart_service' => 'Android 服务：${arguments['serviceName']}',
      'set_firewall_port_rule' =>
        '${arguments['enabled'] == true ? '阻止' : '解除阻止'}出站 ${arguments['protocol']?.toString().toUpperCase()} ${arguments['port']} 端口',
      'set_hosts_block' =>
        '${arguments['enabled'] == true ? '屏蔽' : '解除屏蔽'}域名：${arguments['domain']?.toString().trim().toLowerCase()}',
      'refresh_dns' => '系统默认网络 DNS 缓存',
      'open_vpn_settings' => 'Android VPN 设置',
      'kill_process' =>
        '进程：${arguments['processName']}；PID：${arguments['pid']}；包名：${arguments['packageName'] ?? '未提供'}（来源：ActivityManager 进程列表）',
      'set_wifi' => 'Wi-Fi：${arguments['enabled'] == true ? '开启' : '关闭'}',
      'set_bluetooth' => '蓝牙：${arguments['enabled'] == true ? '开启' : '关闭'}',
      'set_airplane_mode' =>
        '飞行模式：${arguments['enabled'] == true ? '开启' : '关闭'}',
      'set_location' => '定位：${arguments['enabled'] == true ? '开启' : '关闭'}',
      'set_do_not_disturb' =>
        '勿扰模式：${arguments['enabled'] == true ? '开启' : '关闭'}',
      'set_refresh_rate' => '刷新率：${arguments['value']} Hz',
      'set_font_scale' => '字体缩放：${arguments['value']}',
      'set_animation_scale' => '动画倍率：${arguments['value']}',
      'open_default_apps_settings' => 'Android 默认应用设置',
      'open_do_not_disturb_settings' => 'Android 勿扰模式权限设置',
      'open_notification_settings' =>
        'Android 通知设置${arguments['packageName'] is String ? '：${arguments['packageName']}' : ''}',
      'file_operation' => _fileOperationTarget(arguments),
      'launch_deep_link' =>
        '应用：${arguments['packageName']}；URI：${arguments['deepLink'] ?? arguments['uri']}',
      'move_root_file' =>
        '${arguments['source']} → ${arguments['destination']}',
      'compress_root_files' =>
        '${(arguments['sources'] as List).join(', ')} → ${arguments['destination']}',
      'extract_root_archive' =>
        '${arguments['archive']} → ${arguments['destination']}',
      'set_app_alias' => '${arguments['alias']} → ${arguments['packageName']}',
      'open_app_details' ||
      'set_app_network_block' =>
        '应用包名：${arguments['packageName']}${action == 'set_app_network_block' ? '；${arguments['enabled'] == true ? '断网' : '恢复网络'}' : ''}',
      'set_domain_block' =>
        '${arguments['enabled'] == true ? '屏蔽' : '解除屏蔽'}域名：${arguments['domain']?.toString().trim().toLowerCase()}（本地 VPN）',
      'set_network_filter' =>
        '本地 VPN 过滤器：${arguments['enabled'] == true ? '启用' : '停用'}',
      'request_shizuku_permission' || 'open_shizuku' => 'Shizuku',
      'grant_privileged_permissions' => 'NEXUS 自身的系统权限',
      'open_special_permission' => '系统授权页：${arguments['permissionKind']}',
      _ =>
        (arguments['path'] ?? arguments['uri'] ?? arguments['stream'] ?? '设备设置')
            .toString(),
    };
  }

  String _previewScope(Object? action, Map<String, dynamic> arguments) {
    return switch (action) {
      'directory_size' => '仅递归统计此白名单目录及其子项的磁盘占用，不返回文件内容',
      'read_root_file' => '仅读取此白名单文件，最多返回 64 KiB',
      'list_root_files' => '仅列举此白名单目录，最多返回 32 KiB',
      'compress_root_files' =>
        '最多 ${(arguments['sources'] as List).length} 个源路径，仅限各源文件/目录和指定归档目标',
      'extract_root_archive' => '只解压指定归档到目标目录；归档内文件数和总大小需以设备实际内容为准',
      'write_root_file' => '仅覆盖指定文件，写入上限 64 KiB',
      'delete_root_file' || 'move_root_file' => '仅操作列出的单个文件路径',
      'clear_app_cache' => '仅清理指定应用私有目录中的 cache 与 code_cache 子项',
      'kill_process' => '仅向预览中的 PID 发送 SIGTERM；执行前会再次核对进程名',
      'stop_app' || 'restart_app' => '仅作用于指定 packageName 的应用',
      'set_brightness' => '只修改此设备的屏幕亮度设置',
      'set_volume' => '只修改此设备的 ${arguments['stream']} 音量通道',
      'set_auto_rotate' => '只修改此设备的自动旋转设置',
      'set_wifi' => '只切换 Wi-Fi 状态；关闭可能使远程设备控制断开',
      'set_bluetooth' => '只切换蓝牙状态',
      'set_airplane_mode' => '只切换飞行模式；可能中断蜂窝、Wi-Fi 和蓝牙连接',
      'set_location' => '只切换系统定位服务',
      'set_do_not_disturb' => '只切换勿扰模式',
      'restart_service' => '只请求重启预览中列出的白名单服务',
      'set_firewall_port_rule' =>
        '只管理此应用标记的单条出站端口规则；重启设备后规则会丢失，IPv6 支持取决于系统 ip6tables',
      'set_hosts_block' =>
        '只管理 /system/etc/hosts 中带本应用标记的这一条域名规则；如果文件不存在、为符号链接或分区只读，则拒绝修改',
      'refresh_dns' => '只刷新默认网络 DNS 缓存，不修改 DNS 服务器配置',
      'open_vpn_settings' => '只打开 Android VPN 设置页；VPN 连接状态由用户在系统页面操作',
      'set_refresh_rate' => '只修改此设备刷新率；执行前需确认该值受屏幕支持',
      'set_font_scale' => '只修改系统字体缩放值',
      'set_animation_scale' => '同时将窗口、转场和动画倍率设为指定值',
      'open_default_apps_settings' ||
      'open_do_not_disturb_settings' ||
      'open_notification_settings' ||
      'open_vpn_settings' =>
        '只打开对应系统设置页，最终选择由用户在 Android 页面完成',
      'share_file' || 'open_file' => '只向系统传递指定的已授权 content URI',
      'file_operation' => arguments['uris'] is List
          ? '先逐项核验所列 URI 和用户持久写入授权，再按顺序操作最多 100 个文件；提供方执行中仍可能拒绝个别项目，逐项结果会返回'
          : '仅在用户持久授权的 SAF 目录和同一 DocumentsProvider 内操作；实际 URI 授权由 Android 再次核验',
      'choose_folder' => '授权范围由用户在 Android 系统文件夹选择器中决定',
      'set_app_network_block' ||
      'set_domain_block' ||
      'set_network_filter' =>
        '只修改本应用的本地 VPN 规则（最多 500 个域名、100 个应用）；不修改系统文件，停用过滤器即全部失效',
      'grant_privileged_permissions' => '只为 NEXUS 自身授权，固定权限清单，不影响其它应用',
      _ => '仅针对预览中列出的目标',
    };
  }

  String? _rootCommandFor(Object? action, Map<String, dynamic> arguments) {
    String quote(Object? value) =>
        "'${value.toString().replaceAll("'", "'\\''")}'";
    final path = arguments['path'];
    final source = arguments['source'];
    return switch (action) {
      'directory_size' => 'su -c "du -sk -- ${quote(path)}"',
      'read_root_file' => 'su -c "cat -- ${quote(path)}"',
      'list_root_files' => 'su -c "ls -la -- ${quote(path)}"',
      'stop_app' => 'su -c "am force-stop ${arguments['packageName']}"',
      'restart_service' =>
        'su -c "setprop ctl.restart ${arguments['serviceName']}"',
      'set_firewall_port_rule' => null,
      'set_hosts_block' => null,
      'refresh_dns' => 'su -c "ndc resolver flushdefaultif"',
      'set_wifi' =>
        'su -c "svc wifi ${arguments['enabled'] == true ? 'enable' : 'disable'}"',
      'set_bluetooth' =>
        'su -c "cmd bluetooth_manager ${arguments['enabled'] == true ? 'enable' : 'disable'}"',
      'set_airplane_mode' =>
        'su -c "cmd connectivity airplane-mode ${arguments['enabled'] == true ? 'enable' : 'disable'}"',
      'set_location' =>
        'su -c "cmd location set-location-enabled ${arguments['enabled'] == true ? 'true' : 'false'} --user current"',
      'set_do_not_disturb' =>
        'su -c "cmd notification set_dnd ${arguments['enabled'] == true ? 'on' : 'off'}"',
      'write_root_file' =>
        "su -c \"printf '%s' ${quote(arguments['content'])} > ${quote(path)}\"",
      'delete_root_file' => 'su -c "rm -f -- ${quote(path)}"',
      'move_root_file' =>
        'su -c "mv -n -- ${quote(source)} ${quote(arguments['destination'])}"',
      'compress_root_files' =>
        'su -c "tar -czf ${quote(arguments['destination'])} -- ${(arguments['sources'] as List).map(quote).join(' ')}"',
      'extract_root_archive' =>
        'su -c "mkdir -p ${quote(arguments['destination'])} && tar -xzf ${quote(arguments['archive'])} -C ${quote(arguments['destination'])}"',
      _ => null,
    };
  }

  String _executionPlanFor(
    Object? action,
    Map<String, dynamic> arguments,
  ) =>
      switch (action) {
        'directory_size' =>
          'Root helper runs du -sk -- on the validated target; Android terminates the command after 5 seconds.',
        'read_root_file' =>
          'Root helper runs cat -- on the validated target and returns at most 64 KiB; Android terminates the command after 5 seconds.',
        'list_root_files' =>
          'Root helper runs ls -la -- on the validated target and returns at most 32 KiB; Android terminates the command after 5 seconds.',
        'restart_app' =>
          'Android flow: get the app launch intent, run su am force-stop ${arguments['packageName']}, then launch the app.',
        'restart_service' =>
          'Root helper runs setprop ctl.restart ${arguments['serviceName']}; only logd and statsd are accepted.',
        'set_firewall_port_rule' =>
          'Root helper changes only the app-owned iptables rule for the selected TCP/UDP destination port; it also attempts the matching IPv6 rule when ip6tables is available.',
        'set_hosts_block' =>
          'Root helper changes only the marked entry for the validated domain in /system/etc/hosts; it refuses symlinks, unrelated existing mappings, and read-only filesystems.',
        'refresh_dns' =>
          'Root helper runs ndc resolver flushdefaultif; unsupported Android builds return an explicit command error.',
        'clear_app_cache' =>
          'Root helper canonicalizes /data/user/0/${arguments['packageName']}, rejects symlinked cache directories, then removes only children of cache and code_cache.',
        'kill_process' =>
          'Root helper re-reads /proc/${arguments['pid']}/cmdline and compares it with ${arguments['processName']} immediately before SIGTERM.',
        'set_brightness' =>
          'Android Settings API: write the screen brightness value after the app has WRITE_SETTINGS access.',
        'set_volume' =>
          'Android AudioManager API: set the ${arguments['stream']} stream volume.',
        'set_auto_rotate' =>
          'Android Settings API: update accelerometer_rotation.',
        'set_refresh_rate' =>
          'Android display settings API: update the requested refresh-rate limits; the device may clamp or reject unsupported modes.',
        'set_font_scale' =>
          'Android Settings API: update the system font scale.',
        'set_animation_scale' =>
          'Root helper: update the window, transition, and animator duration scale settings.',
        'open_default_apps_settings' ||
        'open_do_not_disturb_settings' ||
        'open_notification_settings' ||
        'open_vpn_settings' =>
          'Launch the matching Android Settings activity; the user completes the setting change there.',
        'file_operation' => arguments['uris'] is List
            ? 'Android pre-validates every selected URI and write grant, then applies the DocumentsContract operation sequentially; provider failures are returned per file.'
            : 'Android DocumentsContract operation within the user-authorized SAF provider.',
        'choose_folder' =>
          'Launch Android ACTION_OPEN_DOCUMENT_TREE; user selects and grants the folder.',
        'set_network_filter' ||
        'set_app_network_block' ||
        'set_domain_block' =>
          'Store the rule in app preferences, request VpnService consent if not yet granted, then (re)start the local VPN: DNS mode answers NXDOMAIN for blocked domains/apps; app-only mode routes just the blocked apps into the VPN and drops their packets.',
        'grant_privileged_permissions' =>
          'Privileged helper (Root or Shizuku) runs pm grant / appops set for NEXUS itself with a fixed permission list.',
        'request_shizuku_permission' =>
          'Shizuku.requestPermission; the Shizuku dialog decides.',
        _ =>
          'Invoke the matching Android device-control MethodChannel handler.',
      };

  String? _rollbackFor(
    Object? action,
    Map<String, dynamic> arguments,
  ) =>
      action == 'file_operation'
          ? switch (arguments['operation']) {
              'delete' => '删除后无法通过 SAF 撤销；需要从备份恢复',
              'rename' => '可将文件改回原名',
              'move' => '可将文件移回原目录，前提是原目录仍可写',
              'copy' => '可删除新生成的副本',
              _ => null,
            }
          : switch (action) {
              'clear_app_cache' => '缓存可由应用重新生成；原有缓存内容不能恢复，应用数据会保留',
              'kill_process' => '进程结束后无法恢复其内存状态；可尝试重新启动应用',
              'delete_root_file' => '若无备份则无法恢复',
              'write_root_file' => '覆盖前未备份的内容无法恢复',
              'compress_root_files' => '可删除生成的归档文件',
              'extract_root_archive' => '需手动删除解压出的文件',
              'move_root_file' => '可反向移动回原路径，前提是原路径未被占用',
              'set_brightness' ||
              'set_volume' ||
              'set_auto_rotate' =>
                '可再次设置原数值恢复',
              'set_wifi' ||
              'set_bluetooth' ||
              'set_airplane_mode' ||
              'set_location' ||
              'set_do_not_disturb' =>
                '可再次调用并传入相反状态恢复',
              'set_refresh_rate' ||
              'set_font_scale' ||
              'set_animation_scale' =>
                '可再次设置此前的系统数值恢复',
              'open_default_apps_settings' ||
              'open_do_not_disturb_settings' ||
              'open_notification_settings' ||
              'open_vpn_settings' =>
                '关闭 Android 设置页面即可返回应用',
              'restart_service' => 'init 会尝试重新拉起服务；如果未恢复，需要检查服务状态',
              'set_firewall_port_rule' => '可使用相同协议和端口再次调用，并反转 enabled 状态',
              'set_hosts_block' => '可用相同域名再次调用并反转 enabled 状态；只会移除本应用标记行',
              'refresh_dns' => 'DNS 缓存会在下一次查询时重新生成',
              'set_network_filter' ||
              'set_app_network_block' ||
              'set_domain_block' =>
                '可再次调用并反转 enabled 恢复；停用过滤器会立即解除全部规则的效果',
              'grant_privileged_permissions' =>
                '可在系统设置中撤销，或通过 adb pm revoke 撤销对应权限',
              _ => null,
            };

  bool _validFileOperation(
    Object? operation,
    Object? uri,
    Object? destinationUri,
    Object? newName, [
    Object? uris,
  ]) {
    bool validContentUri(Object? value) {
      if (value is! String) return false;
      final parsed = Uri.tryParse(value.trim());
      return parsed != null &&
          parsed.scheme == 'content' &&
          parsed.hasAuthority;
    }

    if (uris != null) {
      if (uris is! List ||
          uris.isEmpty ||
          uris.length > 100 ||
          uri != null ||
          newName != null ||
          !const {'delete', 'copy', 'move'}.contains(operation) ||
          uris.any((value) => !validContentUri(value))) {
        return false;
      }
      final uniqueUris = uris.map((value) => (value as String).trim()).toSet();
      if (uniqueUris.length != uris.length) return false;
      return operation == 'delete'
          ? destinationUri == null
          : validContentUri(destinationUri);
    }

    if (!const {'rename', 'delete', 'copy', 'move'}.contains(operation) ||
        !validContentUri(uri)) {
      return false;
    }
    return switch (operation) {
      'rename' => newName is String &&
          newName.trim().isNotEmpty &&
          newName.trim().length <= 255 &&
          !newName.contains(RegExp(r'[/\\\x00-\x1f\x7f]')) &&
          newName.trim() != '.' &&
          newName.trim() != '..',
      'delete' => destinationUri == null && newName == null,
      'copy' || 'move' => validContentUri(destinationUri) && newName == null,
      _ => false,
    };
  }

  bool _validRootFilePath(String value) {
    final path = value.trim().replaceAll('\\', '/');
    if (path.isEmpty || path.contains('\u0000') || !path.startsWith('/')) {
      return false;
    }
    final normalized = path.replaceAll(RegExp(r'/+'), '/');
    if (normalized.contains('/../') ||
        normalized.endsWith('/..') ||
        normalized.contains('/./') ||
        normalized.endsWith('/.')) {
      return false;
    }
    return normalized == '/sdcard' ||
        normalized.startsWith('/sdcard/') ||
        normalized == '/storage/emulated/0' ||
        normalized.startsWith('/storage/emulated/0/') ||
        normalized == '/data/local/tmp' ||
        normalized.startsWith('/data/local/tmp/');
  }

  bool _isRootDirectory(String value) {
    final path =
        value.trim().replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
    return path == '/sdcard' ||
        path == '/storage/emulated/0' ||
        path == '/data/local/tmp';
  }

  bool _validProbeHost(String value) {
    final host = value.trim();
    if (host.isEmpty ||
        host.length > 253 ||
        host.contains(RegExp(r'''[\s'"`;|&<>$()]'''))) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9.:-]*$').hasMatch(host);
  }

  bool _validHostsDomain(String value) {
    final domain = value.trim().toLowerCase();
    if (domain.length > 253 || !domain.contains('.') || domain.endsWith('.')) {
      return false;
    }
    return domain.split('.').every(
          (label) =>
              label.length <= 63 &&
              RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        );
  }

  bool _validProcessName(String value) =>
      value.length <= 255 &&
      RegExp(r'^[A-Za-z0-9_./:-]+$').hasMatch(value.trim()) &&
      !{
        'init',
        'system_server',
        'zygote',
        'zygote64',
        'surfaceflinger',
        'servicemanager',
        'hwservicemanager',
      }.contains(value.trim());

  bool _validExtension(String value) {
    final extension = value.trim().toLowerCase();
    return RegExp(r'^\.?[a-z0-9]{1,10}$').hasMatch(extension);
  }

  bool _validDeepLink(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme.isNotEmpty &&
        uri.scheme != 'file' &&
        uri.scheme != 'content' &&
        value.length <= 2048 &&
        !value.contains(RegExp(r'''[\u0000\r\n]'''));
  }

  Map<String, dynamic> _mutationArguments(Map<String, dynamic> arguments) =>
      Map<String, dynamic>.from(arguments)
        ..remove('preview')
        ..remove('previewId')
        ..remove('planId');
}

class _AndroidMutationPreviewPlan {
  const _AndroidMutationPreviewPlan({
    required this.action,
    required this.argumentsJson,
    required this.expiresAt,
  });

  final String action;
  final String argumentsJson;
  final DateTime expiresAt;
}

class _AndroidMutationExecutionTicket {
  const _AndroidMutationExecutionTicket({
    required this.action,
    required this.argumentsJson,
    required this.expiresAt,
  });

  final String action;
  final String argumentsJson;
  final DateTime expiresAt;
}

class _AndroidMutationPreviewLedger {
  final Map<String, _AndroidMutationPreviewPlan> _plans = {};
  final Map<String, _AndroidMutationExecutionTicket> _tickets = {};

  String createPlan(String action, Map<String, dynamic> arguments) {
    _removeExpired();
    while (_plans.length >= 40) {
      _plans.remove(_plans.keys.first);
    }
    final id = UniqueId.generate('android_plan');
    _plans[id] = _AndroidMutationPreviewPlan(
      action: action,
      argumentsJson: _canonicalJson(arguments),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    return id;
  }

  bool hasPlan(
    String id,
    String action,
    Map<String, dynamic> arguments,
  ) {
    _removeExpired();
    final plan = _plans[id];
    return plan != null &&
        plan.action == action &&
        plan.argumentsJson == _canonicalJson(arguments) &&
        plan.expiresAt.isAfter(DateTime.now());
  }

  String? issueExecutionTicket(
    String planId,
    String action,
    Map<String, dynamic> arguments,
  ) {
    if (!hasPlan(planId, action, arguments)) return null;
    _plans.remove(planId);
    while (_tickets.length >= 40) {
      _tickets.remove(_tickets.keys.first);
    }
    final id = UniqueId.generate('android_execution');
    _tickets[id] = _AndroidMutationExecutionTicket(
      action: action,
      argumentsJson: _canonicalJson(arguments),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    return id;
  }

  bool consume(
    String id,
    String action,
    Map<String, dynamic> arguments,
  ) {
    _removeExpired();
    final ticket = _tickets.remove(id);
    return ticket != null &&
        ticket.action == action &&
        ticket.argumentsJson == _canonicalJson(arguments) &&
        ticket.expiresAt.isAfter(DateTime.now());
  }

  void revokePlan(
    String id,
    String action,
    Map<String, dynamic> arguments,
  ) {
    if (hasPlan(id, action, arguments)) _plans.remove(id);
  }

  void _removeExpired() {
    final now = DateTime.now();
    _plans.removeWhere((_, plan) => !plan.expiresAt.isAfter(now));
    _tickets.removeWhere((_, ticket) => !ticket.expiresAt.isAfter(now));
  }
}

String _canonicalJson(Object? value) {
  Object? canonicalize(Object? item) {
    if (item is Map) {
      final entries = item.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): canonicalize(entry.value),
      };
    }
    if (item is List) return item.map(canonicalize).toList(growable: false);
    return item;
  }

  return jsonEncode(canonicalize(value));
}

class AndroidDevicePreviewTool implements AgentTool {
  AndroidDevicePreviewTool({AndroidDeviceTool? deviceTool})
      : _deviceTool = deviceTool ?? AndroidDeviceTool();

  final AndroidDeviceTool _deviceTool;

  @override
  late final manifest = _androidDevicePreviewManifest();

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) =>
      _deviceTool.preview(arguments);
}

UnifiedTool _androidDevicePreviewManifest() {
  final schema = deepCopyJsonMap(AndroidDeviceTool().manifest.parametersSchema);
  final properties = Map<String, dynamic>.from(schema['properties'] as Map)
    ..remove('preview')
    ..remove('previewId')
    ..remove('planId');
  final actions = _plannedAndroidActions.toList()..sort();
  final action = Map<String, dynamic>.from(properties['action'] as Map)
    ..['enum'] = actions;
  properties['action'] = action;
  schema['properties'] = properties;
  return UnifiedTool(
    name: 'android_device_preview',
    // 只生成预览，不访问手机。
    traits: ToolTraits.pure,
    description: '只读预览一项 Android 设备变更，不执行操作，也不签发执行票据。'
        '向用户展示预览后，再把 planId 和完全相同的目标交给 android_device；'
        '执行器会先完成对应风险等级的用户审批，批准后才签发一次性票据。',
    parametersSchema: schema,
    risk: ToolRisk.safe,
  );
}

final _androidMutationPreviewLedger = _AndroidMutationPreviewLedger();
const _restartableServices = {'logd', 'statsd'};

class AndroidAppPrivateDataTool implements AgentTool, ToolApprovalGate {
  AndroidAppPrivateDataTool({AndroidDeviceControlBridge? bridge})
      : _bridge = bridge ?? const AndroidDeviceControlBridge();

  final AndroidDeviceControlBridge _bridge;

  @override
  ToolRisk riskForArguments(Map<String, dynamic> arguments) =>
      ToolRisk.dangerous;

  @override
  bool requiresPreviewPlan(Map<String, dynamic> arguments) => true;

  @override
  Map<String, dynamic>? approvalDetailsFor(
    Map<String, dynamic> arguments,
  ) {
    final action = arguments['action'];
    final packageName = arguments['packageName'];
    final path = arguments['path'] ?? '';
    final planId = arguments['planId'];
    if ((action != 'list' && action != 'read') ||
        packageName is! String ||
        !_validPrivateAppPackage(packageName) ||
        path is! String ||
        !_validPrivateAppPath(path) ||
        (action == 'read' && (path.isEmpty || !_validPrivateTextFile(path))) ||
        planId is! String ||
        !_privateAppDataPreviewLedger.hasPlan(
          planId,
          action as String,
          packageName.trim(),
          path,
        )) {
      return null;
    }

    final normalizedPackage = packageName.trim();
    final normalizedAction = action;
    return {
      'action': normalizedAction,
      'target':
          '/data/user/0/$normalizedPackage${path.isEmpty ? '' : '/$path'}',
      'command': _privateAppDataCommand(
        normalizedAction,
        normalizedPackage,
        path,
      ),
      'scope': action == 'list'
          ? '仅读取该应用目录的直接子项，最多返回 100 项'
          : '仅读取此 UTF-8 文本文件，最多返回 64 KiB',
      'impact': '私有目录可能包含账号凭证、令牌、个人信息或应用数据',
      'riskClass': ToolRisk.dangerous.name,
      'requiresConfirmation': true,
      'mustWaitForUser': true,
      'reversible': true,
      'modifiesData': false,
    };
  }

  @override
  Map<String, dynamic> authorizeAfterApproval(
    Map<String, dynamic> arguments,
  ) {
    final action = arguments['action'];
    final packageName = arguments['packageName'];
    final path = arguments['path'] ?? '';
    final planId = arguments['planId'];
    if ((action != 'list' && action != 'read') ||
        packageName is! String ||
        !_validPrivateAppPackage(packageName) ||
        path is! String ||
        !_validPrivateAppPath(path) ||
        (action == 'read' && (path.isEmpty || !_validPrivateTextFile(path))) ||
        planId is! String) {
      throw const ToolApprovalAuthorizationException(
        '私有数据计划无效；请重新生成预览',
      );
    }

    final ticketId = _privateAppDataPreviewLedger.issueExecutionTicket(
      planId,
      action,
      packageName.trim(),
      path,
    );
    if (ticketId == null) {
      throw const ToolApprovalAuthorizationException(
        '私有数据计划已过期、已使用或与目标不匹配；请重新预览',
      );
    }
    return Map<String, dynamic>.from(arguments)
      ..remove('planId')
      ..['previewId'] = ticketId;
  }

  @override
  void rejectApproval(Map<String, dynamic> arguments) {
    final action = arguments['action'];
    final packageName = arguments['packageName'];
    final path = arguments['path'] ?? '';
    final planId = arguments['planId'];
    if ((action == 'list' || action == 'read') &&
        packageName is String &&
        path is String &&
        planId is String) {
      _privateAppDataPreviewLedger.revokePlan(
        planId,
        action as String,
        packageName.trim(),
        path,
      );
    }
  }

  @override
  final manifest = const UnifiedTool(
    name: 'android_app_private_data',
    traits: ToolTraits(
      readOnly: true,
      scopes: {ToolEffectScope.device},
    ),
    description: '通过 Root 只读查看指定 Android 应用（Android 用户 0）的私有数据目录。'
        '只允许列举单个目录或读取受支持的 UTF-8 文本文件，单文件最多 64 KiB；'
        '不会写入、删除或修改应用数据。此能力属于危险级，每次实际读取都必须由用户确认。'
        '执行前必须使用 android_app_private_data_preview 生成匹配的预览。',
    risk: ToolRisk.dangerous,
    timeout: Duration(seconds: 35),
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['list', 'read'],
          'description': '列出当前目录，或读取受支持的 UTF-8 文本文件',
        },
        'packageName': {
          'type': 'string',
          'description': 'Android 应用包名，例如 com.example.app',
        },
        'path': {
          'type': 'string',
          'description': '相对于该应用私有数据根目录的路径；list 可为空',
        },
        'planId': {
          'type': 'string',
          'description': '必须先由 android_app_private_data_preview 生成；仅在用户批准后授权执行',
        },
      },
      'required': ['action', 'packageName', 'planId'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final action = arguments['action'];
    final packageName = arguments['packageName'];
    final path = arguments['path'] ?? '';
    if ((action != 'list' && action != 'read') ||
        packageName is! String ||
        !_validPrivateAppPackage(packageName) ||
        path is! String ||
        !_validPrivateAppPath(path) ||
        (action == 'read' && (path.isEmpty || !_validPrivateTextFile(path)))) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '应用私有数据操作参数无效；read 仅支持白名单文本扩展名和相对路径',
      );
    }

    final normalizedPackage = packageName.trim();
    final previewId = arguments['previewId'];
    if (previewId is! String ||
        !_privateAppDataPreviewLedger.consume(
          previewId,
          action as String,
          normalizedPackage,
          path,
        )) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '请先生成与本次应用、路径和操作完全匹配的预览，再发起访问',
      );
    }

    try {
      final data = await _bridge.inspectAppPrivateData(
        operation: action,
        packageName: normalizedPackage,
        relativePath: path,
      );
      return ToolResult.success(
        message: action == 'list' ? '已只读列举指定应用私有目录' : '已只读读取指定应用文本文件',
        data: data,
      );
    } on PlatformException catch (error) {
      final code = switch (error.code) {
        'INVALID_ARGS' => ToolCodes.invalidArguments,
        'ROOT_REQUIRED' => ToolCodes.permissionRequired,
        'TIMEOUT' => ToolCodes.timeout,
        'APP_PRIVATE_DATA_FAILED' => ToolCodes.toolError,
        _ => ToolCodes.toolError,
      };
      return ToolResult.failure(
        code: code,
        message: error.message ?? '应用私有数据读取失败 (${error.code})',
      );
    } on MissingPluginException {
      return ToolResult.failure(
        code: ToolCodes.platformUnsupported,
        message: '应用私有数据访问仅支持 Android 原生应用',
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '应用私有数据读取失败：$error',
      );
    }
  }
}

class AndroidAppPrivateDataPreviewTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
    name: 'android_app_private_data_preview',
    traits: ToolTraits.pure,
    description: '生成 Android 应用私有数据只读访问预览；只校验并描述目标，不访问手机。'
        '实际访问必须调用 android_app_private_data，并通过独立的危险级用户确认。',
    risk: ToolRisk.safe,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['list', 'read'],
        },
        'packageName': {'type': 'string'},
        'path': {
          'type': 'string',
          'description': '相对于 /data/user/0/<package> 的路径；list 可为空',
        },
      },
      'required': ['action', 'packageName'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final action = arguments['action'];
    final packageName = arguments['packageName'];
    final path = arguments['path'] ?? '';
    if ((action != 'list' && action != 'read') ||
        packageName is! String ||
        !_validPrivateAppPackage(packageName) ||
        path is! String ||
        !_validPrivateAppPath(path) ||
        (action == 'read' && (path.isEmpty || !_validPrivateTextFile(path)))) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '应用私有数据预览参数无效；read 仅支持白名单文本扩展名和相对路径',
      );
    }

    final normalizedPackage = packageName.trim();
    final planId = _privateAppDataPreviewLedger.createPlan(
      action,
      normalizedPackage,
      path,
    );
    final target =
        '/data/user/0/$normalizedPackage${path.isEmpty ? '' : '/$path'}';
    return ToolResult.success(
      message: '已生成预览；确认访问前请核对目标路径与隐私影响',
      data: {
        'planId': planId,
        'action': action,
        'target': target,
        'command': _privateAppDataCommand(
          action,
          normalizedPackage,
          path,
        ),
        'scope': action == 'list'
            ? '仅读取该应用目录的直接子项，最多返回 100 项'
            : '仅读取此 UTF-8 文本文件，最多返回 64 KiB',
        'impact': '私有目录可能包含账号凭证、令牌、个人信息或应用数据',
        'riskClass': 'dangerous',
        'requiresConfirmation': true,
        'mustWaitForUser': true,
        'reversible': true,
        'modifiesData': false,
      },
    );
  }
}

String _privateAppDataCommand(String action, String packageName, String path) {
  String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  final dollar = r'$';
  final appRoot = '/data/user/0/$packageName';
  final targetExpression = path.isEmpty
      ? '"${dollar}app_root"'
      : '"${dollar}app_root"/${quote(path)}';
  final actionCommand = switch (action) {
    'list' => '[ "${dollar}target" ] && [ -d "${dollar}target" ] || exit 26\n'
        'ls -lan -- "${dollar}target" | head -n 101',
    'read' => '[ -f "${dollar}target" ] || exit 27\n'
        'head -c 65537 "${dollar}target"',
    _ => throw ArgumentError.value(action, 'action'),
  };
  final payload = '''
data_root=$dollar(readlink -f -- ${quote('/data/user/0')}) || exit 20
app_root=$dollar(readlink -f -- ${quote(appRoot)}) || exit 21
expected_app_root="${dollar}data_root/$packageName"
[ "${dollar}app_root" = "${dollar}expected_app_root" ] || exit 22
[ -d "${dollar}app_root" ] || exit 23
target=$dollar(readlink -f -- $targetExpression) || exit 24
case "${dollar}target" in "${dollar}app_root" | "${dollar}app_root"/*) ;; *) exit 25 ;; esac
$actionCommand
'''
      .trim();
  return 'ProcessBuilder("su", "-c", command):\n$payload';
}

class _PrivateAppDataPreviewPlan {
  const _PrivateAppDataPreviewPlan({
    required this.action,
    required this.packageName,
    required this.path,
    required this.expiresAt,
  });

  final String action;
  final String packageName;
  final String path;
  final DateTime expiresAt;

  bool matches(String action, String packageName, String path) =>
      this.action == action &&
      this.packageName == packageName &&
      this.path == path &&
      expiresAt.isAfter(DateTime.now());
}

class _PrivateAppDataExecutionTicket {
  const _PrivateAppDataExecutionTicket({
    required this.action,
    required this.packageName,
    required this.path,
    required this.expiresAt,
  });

  final String action;
  final String packageName;
  final String path;
  final DateTime expiresAt;

  bool matches(String action, String packageName, String path) =>
      this.action == action &&
      this.packageName == packageName &&
      this.path == path &&
      expiresAt.isAfter(DateTime.now());
}

class _PrivateAppDataPreviewLedger {
  final Map<String, _PrivateAppDataPreviewPlan> _plans = {};
  final Map<String, _PrivateAppDataExecutionTicket> _tickets = {};

  String createPlan(String action, String packageName, String path) {
    _removeExpired();
    while (_plans.length >= 20) {
      _plans.remove(_plans.keys.first);
    }
    final id = UniqueId.generate('app_private_plan');
    _plans[id] = _PrivateAppDataPreviewPlan(
      action: action,
      packageName: packageName,
      path: path,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    return id;
  }

  bool hasPlan(String id, String action, String packageName, String path) {
    _removeExpired();
    final plan = _plans[id];
    return plan?.matches(action, packageName, path) ?? false;
  }

  String? issueExecutionTicket(
    String planId,
    String action,
    String packageName,
    String path,
  ) {
    if (!hasPlan(planId, action, packageName, path)) return null;
    _plans.remove(planId);
    _removeExpired();
    while (_tickets.length >= 20) {
      _tickets.remove(_tickets.keys.first);
    }
    final id = UniqueId.generate('app_private_execution');
    _tickets[id] = _PrivateAppDataExecutionTicket(
      action: action,
      packageName: packageName,
      path: path,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    return id;
  }

  bool consume(String id, String action, String packageName, String path) {
    _removeExpired();
    final ticket = _tickets.remove(id);
    return ticket?.matches(action, packageName, path) ?? false;
  }

  void revokePlan(String id, String action, String packageName, String path) {
    if (hasPlan(id, action, packageName, path)) _plans.remove(id);
  }

  void _removeExpired() {
    final now = DateTime.now();
    _plans.removeWhere((_, plan) => !plan.expiresAt.isAfter(now));
    _tickets.removeWhere((_, ticket) => !ticket.expiresAt.isAfter(now));
  }
}

final _privateAppDataPreviewLedger = _PrivateAppDataPreviewLedger();

bool _validPrivateAppPackage(String value) => RegExp(
      r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$',
    ).hasMatch(value.trim());

bool _validPrivateAppPath(String value) {
  if (value.length > 512 ||
      value.contains(RegExp(r'[\x00-\x1f\x7f\\]')) ||
      value.startsWith('/') ||
      value.endsWith('/')) {
    return value.isEmpty;
  }
  if (value.isEmpty) return true;
  return value.split('/').every(
      (segment) => segment.isNotEmpty && segment != '.' && segment != '..');
}

bool _validPrivateTextFile(String path) => const {
      'conf',
      'csv',
      'ini',
      'json',
      'log',
      'md',
      'properties',
      'txt',
      'xml',
      'yaml',
      'yml'
    }.contains(path.split('.').last.toLowerCase());
