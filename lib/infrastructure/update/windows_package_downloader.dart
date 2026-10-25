import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WindowsPackageDownloadResult {
  const WindowsPackageDownloadResult.success(this.path) : error = null;
  const WindowsPackageDownloadResult.failure(this.error) : path = null;
  final String? path;
  final String? error;
  bool get success => path != null;
}

/// Downloads a portable Windows package without replacing running binaries.
/// Only verified packages become visible in the persistent updates directory.
class WindowsPackageDownloader {
  WindowsPackageDownloader(this.dio);
  final Dio dio;

  Future<WindowsPackageDownloadResult> download(String url,
      {required String? expectedSha256,
      void Function(double progress)? onProgress}) async {
    final digest = expectedSha256?.trim().toLowerCase();
    if (digest == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      return const WindowsPackageDownloadResult.failure(
          '更新包缺少 SHA-256 校验值，已停止下载');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return const WindowsPackageDownloadResult.failure('更新地址无效');
    }
    Directory? staging;
    try {
      final support = await getApplicationSupportDirectory();
      final updates = Directory(p.join(support.path, 'updates'));
      await updates.create(recursive: true);
      staging = await updates.createTemp('windows-');
      final part = File(p.join(staging.path, 'package.zip.part'));
      await dio.download(url, part.path,
          deleteOnError: true,
          options: Options(
              receiveTimeout: const Duration(minutes: 5),
              sendTimeout: const Duration(seconds: 30)),
          onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      });
      final actual = (await sha256.bind(part.openRead()).first).toString();
      if (actual != digest) {
        return const WindowsPackageDownloadResult.failure('更新文件校验失败，请重新检测更新');
      }
      final header = await part
          .openRead(0, 4)
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      if (header.length != 4 ||
          header[0] != 0x50 ||
          header[1] != 0x4b ||
          header[2] != 3 ||
          header[3] != 4) {
        return const WindowsPackageDownloadResult.failure(
            '下载的 Windows 压缩包无效，请重试');
      }
      final target =
          File(p.join(updates.path, 'nexus-agent-$digest-windows-x64.zip'));
      if (await target.exists()) {
        final existing =
            (await sha256.bind(target.openRead()).first).toString();
        if (existing != digest) {
          return const WindowsPackageDownloadResult.failure(
              '已有下载包校验失败，请移走该文件后重试');
        }
      } else {
        await part.rename(target.path);
      }
      onProgress?.call(1);
      return WindowsPackageDownloadResult.success(target.path);
    } catch (_) {
      return const WindowsPackageDownloadResult.failure('下载失败，请检查网络与磁盘空间后重试');
    } finally {
      if (staging != null) {
        try {
          // This directory was created by this request and contains only its part file.
          await staging.delete(recursive: true);
        } catch (_) {/* Cleanup must not hide the download result. */}
      }
    }
  }
}
