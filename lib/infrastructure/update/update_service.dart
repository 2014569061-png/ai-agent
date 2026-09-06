import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内更新(Android):GitHub Releases API 检查新版本 → 下载 APK →
/// 通过 MethodChannel 调用原生 FileProvider + ACTION_VIEW 拉起安装。
class UpdateService {
  static const _repoApi =
      'https://api.github.com/repos/2014569061-png/ai-agent/releases/latest';
  static const _channel = MethodChannel('nexus/update');
  final Dio _dio = Dio();

  /// G1 检查更新:区分三种结果(有更新 / 已最新 / 检测失败)。
  Future<UpdateCheckResult> checkUpdate() async {
    if (kIsWeb) {
      return const UpdateCheckResult(
          status: UpdateCheckStatus.failed, error: 'Web 平台不支持');
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await _dio.get<dynamic>(_repoApi,
          options: Options(
            headers: {'Accept': 'application/vnd.github+json'},
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
          ));
      final data = response.data as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (!_isNewer(version, info.version)) {
        return UpdateCheckResult(
            status: UpdateCheckStatus.upToDate, currentVersion: info.version);
      }
      String? apkUrl;
      for (final asset in (data['assets'] as List<dynamic>? ?? const [])) {
        final map = asset as Map<String, dynamic>;
        final name = (map['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = map['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) {
        // 发版漏传 APK:按已最新处理,但留日志便于排查。
        debugPrint('UpdateService: Release $tagName 未附带 APK 资产');
        return UpdateCheckResult(
            status: UpdateCheckStatus.upToDate, currentVersion: info.version);
      }
      return UpdateCheckResult(
          status: UpdateCheckStatus.update,
          currentVersion: info.version,
          info: UpdateInfo(
              version: version,
              notes: (data['body'] as String?) ?? '',
              apkUrl: apkUrl));
    } on DioException catch (e) {
      final msg = e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError
          ? '网络连接失败,请检查网络后重试'
          : e.response?.statusCode == 403
              ? 'GitHub 访问受限,请稍后再试'
              : '请求失败:${e.message}';
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed, error: msg);
    } catch (e) {
      return UpdateCheckResult(
          status: UpdateCheckStatus.failed, error: '检测失败:$e');
    }
  }

  /// 下载 APK(带进度回调 0~1)到应用私有目录并拉起系统安装(仅 Android)。
  Future<bool> downloadAndInstall(String url,
      {void Function(double progress)? onProgress}) async {
    if (kIsWeb) return false;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}nexus_update.apk';
    await _dio.download(url, path,
        onReceiveProgress: onProgress == null
            ? null
            : (received, total) {
                if (total > 0) onProgress(received / total);
              });
    try {
      await _channel.invokeMethod<bool>('installApk', {'path': path});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 语义化版本比较:version 是否大于 current。
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

enum UpdateCheckStatus { update, upToDate, failed }

class UpdateCheckResult {
  const UpdateCheckResult(
      {required this.status, this.info, this.error, this.currentVersion});

  final UpdateCheckStatus status;
  final UpdateInfo? info; // status == update 时非空
  final String? error; // status == failed 时的原因
  final String? currentVersion; // upToDate 时用于提示
}

class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, this.apkUrl});
  final String version;
  final String notes;
  final String? apkUrl;
}
