import 'dart:convert';
import 'dart:io';

String? readSharedImageAsDataUri(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final lower = path.toLowerCase();
  final mime = lower.endsWith('.png')
      ? 'image/png'
      : lower.endsWith('.webp')
          ? 'image/webp'
          : lower.endsWith('.gif')
              ? 'image/gif'
              : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(file.readAsBytesSync())}';
}
