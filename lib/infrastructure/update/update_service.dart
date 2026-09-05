import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内更新（Android）：GitHub Releases API 检查新版本 → 下载 APK →
/// 通过 MethodChannel 调用原生 FileProvider + ACTION_VIEW 拉起安装。
class UpdateService {
  static const _repoApi =
      'https://api.github.com/repos/2014569061-png/ai-agent/releases/latest';
  static const _channel = MethodChannel('nexus/update');
  final Dio _dio = Dio();

  /// 返回可用的更新信息；已是最新 / 网络失败 / 无 APK 资产时返回 null。
  Future<UpdateInfo?> checkUpdate() async {
    if (kIsWeb) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await _dio.get<dynamic>(_repoApi);
      final data = response.data as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (!_isNewer(version, info.version)) return null;
      String? apkUrl;
      for (final asset in (data['assets'] as List<dynamic>? ?? const [])) {
        final map = asset as Map<String, dynamic>;
        final name = (map['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = map['browser_download_url'] as String?;
          break;
        }
      }
      return UpdateInfo(
          version: version,
          notes: (data['body'] as String?) ?? '',
          apkUrl: apkUrl);
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK 到应用私有目录并拉起系统安装（仅 Android）。
  Future<bool> downloadAndInstall(String url) async {
    if (kIsWeb) return false;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}nexus_update.apk';
    await _dio.download(url, path);
    try {
      await _channel.invokeMethod<bool>('installApk', {'path': path});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 语义化版本比较：version 是否大于 current。
  static bool _isNewer(String version, String current) {
    final a = _parse(version);
    final b = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int> _parse(String version) {
    final parts = version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}

class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, this.apkUrl});
  final String version;
  final String notes;
  final String? apkUrl;
}
