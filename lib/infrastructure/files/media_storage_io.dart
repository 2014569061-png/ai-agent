import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把音视频附件字节写入应用文档目录，返回可播放的本地路径；失败返回 null。
Future<String?> saveMediaFile(String name, Uint8List bytes) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final file = File(p.join(
        dir.path, 'media-${DateTime.now().millisecondsSinceEpoch}-$safeName'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
