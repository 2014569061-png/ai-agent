import 'dart:convert';
import 'dart:typed_data';

class DocumentExtractor {
  const DocumentExtractor();

  /// 提取可读文本。PDF 本地解析能力已移除以减小安装包体积，返回 null 由上层跳过。
  String? extractText({required String fileName, required Uint8List bytes}) {
    final extension = fileName.split('.').last.toLowerCase();
    if (const {'txt', 'md', 'csv', 'json'}.contains(extension)) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return null;
  }
}
