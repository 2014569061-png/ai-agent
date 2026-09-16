import 'package:flutter/services.dart';

class ApkInstallResult {
  const ApkInstallResult({
    required this.status,
    this.message,
  });

  final String status;
  final String? message;

  bool get started => status == 'started';
  bool get cancelled => status == 'cancelled' || status == 'canceled';
  bool get permissionRequired => status == 'permission_required';
  bool get failed => status == 'failed';
}

class ApkInstallBridge {
  const ApkInstallBridge();

  static const _channel = MethodChannel('nexus/update');

  Future<ApkInstallResult> install(String path) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('installApk', {
        'path': path,
      });
      if (raw == true) return const ApkInstallResult(status: 'started');
      if (raw is Map) {
        return ApkInstallResult(
          status: raw['status']?.toString() ?? 'failed',
          message: raw['message']?.toString(),
        );
      }
      return const ApkInstallResult(status: 'failed', message: '系统安装器未能启动');
    } on PlatformException catch (error) {
      if (error.code == 'INSTALL_CANCELLED' ||
          (error.message ?? '').toLowerCase().contains('cancel')) {
        return const ApkInstallResult(status: 'cancelled', message: '用户取消安装');
      }
      return ApkInstallResult(
        status: 'failed',
        message: error.message ?? error.code,
      );
    }
  }
}
