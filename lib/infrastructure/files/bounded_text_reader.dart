import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class TextFileTooLarge implements Exception {
  const TextFileTooLarge(this.maxBytes);
  final int maxBytes;
  @override
  String toString() => '文件超过 $maxBytes 字节，请通过终端按需读取片段';
}

/// Bounds the actual read as well as the initial stat, including files that grow
/// between those operations. Binary/NUL and malformed UTF-8 are not text.
abstract final class BoundedTextReader {
  static const maxReadBytes = 2 * 1024 * 1024;
  static const maxSearchBytes = 1024 * 1024;
  static const binaryExtensions = {
    '.apk',
    '.aab',
    '.zip',
    '.gz',
    '.tar',
    '.7z',
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.ico',
    '.pdf',
    '.mp4',
    '.mp3',
    '.wav',
    '.so',
    '.dll',
    '.exe',
    '.bin',
    '.db',
    '.sqlite',
    '.woff',
    '.woff2',
    '.ttf',
  };

  static Future<String> read(File file, {int maxBytes = maxReadBytes}) async {
    if (await file.length() > maxBytes) throw TextFileTooLarge(maxBytes);
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maxBytes + 1)) {
      buffer.add(chunk);
      if (buffer.length > maxBytes) throw TextFileTooLarge(maxBytes);
    }
    final bytes = buffer.takeBytes();
    if (bytes.contains(0)) throw const FormatException('二进制文件不能作为文本读取');
    return utf8.decode(bytes);
  }
}
