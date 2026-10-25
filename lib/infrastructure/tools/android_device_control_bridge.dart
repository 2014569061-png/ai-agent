import 'package:flutter/services.dart';

class AndroidDeviceControlBridge {
  const AndroidDeviceControlBridge();

  static const MethodChannel _channel = MethodChannel('nexus/device_control');

  Future<List<Map<String, String>>> listApps() => _stringMaps('listApps');

  Future<void> launchApp(String packageName) =>
      _channel.invokeMethod<void>('launchApp', {'packageName': packageName});

  Future<Map<String, dynamic>> rootStatus() => _invokeMap('rootStatus');

  Future<Map<String, dynamic>> deviceInfo() => _invokeMap('deviceInfo');

  Future<Map<String, dynamic>> storageInfo() => _invokeMap('storageInfo');

  Future<Map<String, dynamic>> networkInfo() => _invokeMap('networkInfo');

  Future<Map<String, dynamic>> refreshDns() => _invokeMap('refreshDns');

  Future<Map<String, dynamic>> openVpnSettings() =>
      _invokeMap('openVpnSettings');

  Future<Map<String, dynamic>> setFirewallPortRule({
    required String protocol,
    required int port,
    required bool enabled,
  }) =>
      _invokeMap(
        'setFirewallPortRule',
        {'protocol': protocol, 'port': port, 'enabled': enabled},
      );

  Future<Map<String, dynamic>> setHostsBlock({
    required String domain,
    required bool enabled,
  }) =>
      _invokeMap(
        'setHostsBlock',
        {'domain': domain, 'enabled': enabled},
      );

  Future<Map<String, dynamic>> restartService(String serviceName) =>
      _invokeMap('restartService', {'serviceName': serviceName});

  Future<List<dynamic>> runningProcesses() async =>
      await _channel.invokeListMethod<dynamic>('runningProcesses') ?? const [];

  Future<List<dynamic>> foregroundApps() async =>
      await _channel.invokeListMethod<dynamic>('foregroundApps') ?? const [];

  Future<Map<String, dynamic>> logcatTail(int lines) =>
      _invokeMap('logcatTail', {'lines': lines});

  Future<Map<String, dynamic>> crashLogs(String? packageName) => _invokeMap(
      'crashLogs', {if (packageName != null) 'packageName': packageName});

  Future<Map<String, dynamic>> appInfo(String packageName) =>
      _invokeMap('appInfo', {'packageName': packageName});

  Future<Map<String, dynamic>> systemStatus() => _invokeMap('systemStatus');

  Future<Map<String, dynamic>> trafficInfo() => _invokeMap('trafficInfo');

  Future<Map<String, dynamic>> traceroute(String host) =>
      _invokeMap('traceroute', {'host': host});

  Future<Map<String, dynamic>> systemSettings() => _invokeMap('systemSettings');

  Future<Map<String, dynamic>> setBrightness(double value) =>
      _invokeMap('setBrightness', {'value': value});

  Future<Map<String, dynamic>> setVolume(String stream, double value) =>
      _invokeMap('setVolume', {'stream': stream, 'value': value});

  Future<Map<String, dynamic>> setAutoRotate(bool enabled) =>
      _invokeMap('setAutoRotate', {'enabled': enabled});

  Future<Map<String, dynamic>> setWifi(bool enabled) =>
      _invokeMap('setWifi', {'enabled': enabled});

  Future<Map<String, dynamic>> setBluetooth(bool enabled) =>
      _invokeMap('setBluetooth', {'enabled': enabled});

  Future<Map<String, dynamic>> setAirplaneMode(bool enabled) =>
      _invokeMap('setAirplaneMode', {'enabled': enabled});

  Future<Map<String, dynamic>> setLocationEnabled(bool enabled) =>
      _invokeMap('setLocationEnabled', {'enabled': enabled});

  Future<Map<String, dynamic>> setDoNotDisturb(bool enabled) =>
      _invokeMap('setDoNotDisturb', {'enabled': enabled});

  Future<Map<String, dynamic>> setRefreshRate(double value) =>
      _invokeMap('setRefreshRate', {'value': value});

  Future<Map<String, dynamic>> setFontScale(double value) =>
      _invokeMap('setFontScale', {'value': value});

  Future<Map<String, dynamic>> setAnimationScale(double value) =>
      _invokeMap('setAnimationScale', {'value': value});

  Future<Map<String, dynamic>> openDefaultAppsSettings() =>
      _invokeMap('openDefaultAppsSettings');

  Future<Map<String, dynamic>> openDoNotDisturbSettings() =>
      _invokeMap('openDoNotDisturbSettings');

  Future<Map<String, dynamic>> openNotificationSettings(String? packageName) =>
      _invokeMap('openNotificationSettings',
          {if (packageName != null) 'packageName': packageName});

  Future<Map<String, dynamic>> directorySize(String path) =>
      _invokeMap('directorySize', {'path': path});

  Future<Map<String, dynamic>> portProbe(String host, int port) =>
      _invokeMap('portProbe', {'host': host, 'port': port});

  Future<Map<String, dynamic>> restartApp(String packageName) =>
      _invokeMap('restartApp', {'packageName': packageName});

  Future<Map<String, dynamic>> appPermissions(String packageName) =>
      _invokeMap('appPermissions', {'packageName': packageName});

  Future<List<dynamic>> recentApps() async =>
      await _channel.invokeListMethod<dynamic>('recentApps') ?? const [];

  Future<Map<String, dynamic>> setAppAlias(String alias, String packageName) =>
      _invokeMap('setAppAlias', {'alias': alias, 'packageName': packageName});

  Future<List<dynamic>> listAppAliases() async =>
      await _channel.invokeListMethod<dynamic>('listAppAliases') ?? const [];

  Future<Map<String, dynamic>> launchDeepLink(String packageName, String uri) =>
      _invokeMap('launchDeepLink', {'packageName': packageName, 'uri': uri});

  Future<Map<String, dynamic>> stopApp(String packageName) =>
      _invokeMap('stopApp', {'packageName': packageName});

  Future<Map<String, dynamic>> killProcess(int pid, String processName) =>
      _invokeMap('killProcess', {'pid': pid, 'processName': processName});

  Future<Map<String, dynamic>> clearAppCache(String packageName) =>
      _invokeMap('clearAppCache', {'packageName': packageName});

  Future<Map<String, dynamic>> readRootFile(String path) =>
      _invokeMap('readRootFile', {'path': path});

  Future<Map<String, dynamic>> inspectAppPrivateData({
    required String operation,
    required String packageName,
    required String relativePath,
  }) =>
      _invokeMap(
        'inspectAppPrivateData',
        {
          'operation': operation,
          'packageName': packageName,
          'relativePath': relativePath,
        },
      );

  Future<Map<String, dynamic>> listRootFiles(String path) =>
      _invokeMap('listRootFiles', {'path': path});

  Future<Map<String, dynamic>> writeRootFile(String path, String content) =>
      _invokeMap('writeRootFile', {'path': path, 'content': content});

  Future<Map<String, dynamic>> deleteRootFile(String path) =>
      _invokeMap('deleteRootFile', {'path': path});

  Future<Map<String, dynamic>> moveRootFile(
          String source, String destination) =>
      _invokeMap(
          'moveRootFile', {'source': source, 'destination': destination});

  Future<Map<String, dynamic>> networkProbe(String host) =>
      _invokeMap('networkProbe', {'host': host});

  Future<Map<String, dynamic>> compressRootFiles(
          List<String> sources, String destination) =>
      _invokeMap('compressRootFiles',
          {'sources': sources, 'destination': destination});

  Future<Map<String, dynamic>> extractRootArchive(
          String archive, String destination) =>
      _invokeMap(
        'extractRootArchive',
        {'archive': archive, 'destination': destination},
      );

  Future<Map<String, dynamic>> searchFilesFiltered({
    required String query,
    String? extension,
    int? modifiedAfterMs,
    int? modifiedBeforeMs,
  }) =>
      _invokeMap(
        'searchFilesFiltered',
        {
          'query': query,
          if (extension != null) 'extension': extension,
          if (modifiedAfterMs != null) 'modifiedAfterMs': modifiedAfterMs,
          if (modifiedBeforeMs != null) 'modifiedBeforeMs': modifiedBeforeMs,
        },
      );

  Future<Map<String, dynamic>> fileOperation({
    required String operation,
    required String uri,
    String? destinationUri,
    String? newName,
  }) =>
      _invokeMap(
        'fileOperation',
        {
          'operation': operation,
          'uri': uri,
          if (destinationUri != null) 'destinationUri': destinationUri,
          if (newName != null) 'newName': newName,
        },
      );

  Future<Map<String, dynamic>> fileOperationBatch({
    required String operation,
    required List<String> uris,
    String? destinationUri,
  }) =>
      _invokeMap(
        'fileOperationBatch',
        {
          'operation': operation,
          'uris': uris.map((uri) => uri.trim()).toList(growable: false),
          if (destinationUri != null) 'destinationUri': destinationUri.trim(),
        },
      );

  Future<Map<String, dynamic>> refreshSearchIndex() =>
      _invokeMap('refreshSearchIndex');

  Future<void> shareFile(String uri) =>
      _channel.invokeMethod<void>('shareFile', {'uri': uri});

  Future<Map<String, dynamic>> launchAppByName(String query) => _invokeMap(
        'launchAppByName',
        {'query': query},
      );

  Future<void> chooseFolder() => _channel.invokeMethod<void>('chooseFolder');

  Future<Map<String, dynamic>> searchFiles(
    String query,
    String requestId,
  ) =>
      _invokeMap(
        'searchFiles',
        {'query': query, 'requestId': requestId},
      );

  Future<void> openFile(String uri) =>
      _channel.invokeMethod<void>('openFile', {'uri': uri});

  Future<List<Map<String, String>>> listAuthorizedFolders() =>
      _stringMaps('listAuthorizedFolders');

  Future<List<Map<String, String>>> _stringMaps(String method) async {
    final result = await _channel.invokeListMethod<dynamic>(method);
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
  static Map<String, dynamic>? get recentPrivilegeStatus =>
      recentPrivilegeRouteSnapshot?.status;

  static AndroidPrivilegeRouteSnapshot? get recentPrivilegeRouteSnapshot {
    final snapshot = _privilegeRouteSnapshot;
    return snapshot != null && snapshot.fresh ? snapshot : null;
  }

  Future<Map<String, dynamic>> privilegeStatus({bool probeRoot = true}) async {
    final status =
        await _invokeMap('privilegeStatus', {'probeRoot': probeRoot});
    final routes = status['routes'];
    if (routes is Map) {
      final root = status['root'];
      _privilegeRouteSnapshot = AndroidPrivilegeRouteSnapshot(
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

/// 最近一次 privilegeStatus 返回的执行通道，供同步的预览/审批详情引用。
AndroidPrivilegeRouteSnapshot? _privilegeRouteSnapshot;

class AndroidPrivilegeRouteSnapshot {
  AndroidPrivilegeRouteSnapshot(
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
