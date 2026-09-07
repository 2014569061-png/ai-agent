import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks GitHub Releases, downloads an APK, and delegates installation to Android.
class UpdateService {
  static const _repoApi =
      'https://api.github.com/repos/2014569061-png/ai-agent/releases/latest';
  static const _channel = MethodChannel('nexus/update');
  static const _apkName = 'nexus_update.apk';
  static const _partName = 'nexus_update.apk.part';

  final Dio _dio = Dio();

  /// Returns whether a newer GitHub release with an APK is available.
  Future<UpdateCheckResult> checkUpdate() async {
    if (kIsWeb) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        error: 'Web 平台不支持应用内更新',
      );
    }

    try {
      final info = await PackageInfo.fromPlatform();
      final response = await _dio.get<dynamic>(
        _repoApi,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (!_isNewer(version, info.version)) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          currentVersion: info.version,
        );
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
      if (apkUrl == null || apkUrl.isEmpty) {
        debugPrint('UpdateService: release $tagName has no APK asset');
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          currentVersion: info.version,
        );
      }

      return UpdateCheckResult(
        status: UpdateCheckStatus.update,
        currentVersion: info.version,
        info: UpdateInfo(
          version: version,
          notes: (data['body'] as String?) ?? '',
          apkUrl: apkUrl,
        ),
      );
    } on DioException catch (e) {
      final msg = e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError
          ? '网络连接失败，请检查网络后重试'
          : e.response?.statusCode == 403
              ? 'GitHub 访问受限，请稍后再试'
              : '请求失败，请稍后重试';
      return UpdateCheckResult(status: UpdateCheckStatus.failed, error: msg);
    } catch (e) {
      debugPrint('UpdateService.checkUpdate failed: $e');
      return const UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        error: '检测更新失败，请稍后重试',
      );
    }
  }

  /// Downloads and starts the platform installer. The bool API is kept for
  /// callers that only need to know whether the installer was launched.
  Future<bool> downloadAndInstall(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final result = await downloadAndInstallDetailed(
      url,
      onProgress: onProgress,
    );
    return result.success;
  }

  /// Downloads to a temporary file, validates the APK header, then atomically
  /// moves it to the final path before asking Android to install it.
  Future<UpdateInstallResult> downloadAndInstallDetailed(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      return const UpdateInstallResult.failure('Web 平台不支持应用内更新');
    }
    if (url.trim().isEmpty) {
      return const UpdateInstallResult.failure('更新地址为空');
    }

    File? partFile;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final apkFile = File('${dir.path}${Platform.pathSeparator}$_apkName');
      partFile = File('${dir.path}${Platform.pathSeparator}$_partName');

      if (await partFile.exists()) {
        await partFile.delete();
      }

      await _dio.download(
        url,
        partFile.path,
        deleteOnError: true,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
          followRedirects: true,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
        onReceiveProgress: onProgress == null
            ? null
            : (received, total) {
                if (total <= 0) return;
                onProgress((received / total).clamp(0.0, 1.0));
              },
      );

      if (!await _isValidApk(partFile)) {
        return const UpdateInstallResult.failure('下载的更新文件无效，请重试');
      }

      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      await partFile.rename(apkFile.path);
      onProgress?.call(1.0);

      final raw = await _channel.invokeMethod<dynamic>(
        'installApk',
        {'path': apkFile.path},
      );
      final result = _parseInstallResult(raw);
      if (!result.success && result.message == null) {
        return const UpdateInstallResult.failure('系统安装器未能启动，请重试');
      }
      return result;
    } on DioException catch (e) {
      debugPrint('UpdateService.download failed: ${e.type} ${e.message}');
      return UpdateInstallResult.failure(_downloadErrorMessage(e));
    } on PlatformException catch (e) {
      debugPrint('UpdateService.install failed: ${e.code} ${e.message}');
      return UpdateInstallResult.failure(_platformErrorMessage(e));
    } catch (e) {
      debugPrint('UpdateService.downloadAndInstall failed: $e');
      return const UpdateInstallResult.failure('下载或安装失败，请重试');
    } finally {
      if (partFile != null) {
        try {
          if (await partFile.exists()) {
            await partFile.delete();
          }
        } catch (_) {
          // A failed cleanup must not hide the original update error.
        }
      }
    }
  }

  static Future<bool> _isValidApk(File file) async {
    if (!await file.exists()) return false;
    final handle = await file.open();
    try {
      if (await handle.length() < 4) return false;
      final header = await handle.read(4);
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4b &&
          (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07) &&
          (header[3] == 0x04 || header[3] == 0x06 || header[3] == 0x08);
    } finally {
      await handle.close();
    }
  }

  static UpdateInstallResult _parseInstallResult(dynamic raw) {
    if (raw == true) return const UpdateInstallResult.started();
    if (raw is Map) {
      final status = raw['status']?.toString();
      if (status == 'started') return const UpdateInstallResult.started();
      if (status == 'permission_required') {
        return const UpdateInstallResult.permissionRequired();
      }
      final message = raw['message']?.toString();
      return UpdateInstallResult.failure(message ?? '系统安装器未能启动，请重试');
    }
    return const UpdateInstallResult.failure('系统安装器未能启动，请重试');
  }

  static String _downloadErrorMessage(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return '下载失败，请检查网络后重试';
    }
    final status = error.response?.statusCode;
    if (status == 403) return 'GitHub 访问受限，请稍后再试';
    if (status != null) return '下载失败（HTTP $status），请重试';
    return '下载失败，请重试';
  }

  static String _platformErrorMessage(PlatformException error) {
    switch (error.code) {
      case 'UNKNOWN_SOURCES_REQUIRED':
        return '请在系统设置中允许本应用安装未知应用，然后返回并重试';
      case 'UNKNOWN_SOURCES_SETTINGS_UNAVAILABLE':
        return '无法打开“安装未知应用”设置，请在系统设置中手动允许';
      case 'NO_INSTALLER':
        return '系统没有可用的 APK 安装器';
      case 'INVALID_APK':
        return '更新文件无效，请重新下载';
      case 'INVALID_PATH':
        return '更新文件路径无效，请重试';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!
            : '系统安装器启动失败，请重试';
    }
  }

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
  const UpdateCheckResult({
    required this.status,
    this.info,
    this.error,
    this.currentVersion,
  });

  final UpdateCheckStatus status;
  final UpdateInfo? info;
  final String? error;
  final String? currentVersion;
}

class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, this.apkUrl});

  final String version;
  final String notes;
  final String? apkUrl;
}

class UpdateInstallResult {
  const UpdateInstallResult._({
    required this.success,
    this.permissionRequired = false,
    this.message,
  });

  const UpdateInstallResult.started() : this._(success: true);

  const UpdateInstallResult.permissionRequired()
      : this._(
          success: false,
          permissionRequired: true,
          message: '请在系统设置中允许本应用安装未知应用，然后返回并重试',
        );

  const UpdateInstallResult.failure(String message)
      : this._(success: false, message: message);

  final bool success;
  final bool permissionRequired;
  final String? message;
}
