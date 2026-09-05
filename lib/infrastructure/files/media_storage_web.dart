import 'dart:typed_data';

/// web 上无法可靠地把媒体写到可播放的本地路径，返回 null 降级为占位。
Future<String?> saveMediaFile(String name, Uint8List bytes) async => null;
