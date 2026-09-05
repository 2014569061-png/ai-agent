import 'dart:typed_data';

import '../database/app_database.dart';

/// web 上不支持文件系统级隐私保险箱，导出/导入均降级为不可用。
Future<String?> exportVaultFile(AppDatabase db, String password) async => null;

Future<String> importVaultBytes(
    AppDatabase db, Uint8List bytes, String password) async {
  throw UnsupportedError('浏览器暂不支持隐私保险箱');
}
