import 'dart:convert';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentExtractor {
  const DocumentExtractor();

  String? extractText({required String fileName, required Uint8List bytes}) {
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'pdf') {
      // 损坏 / 加密 / 非 PDF 内容都会让 PdfDocument 构造抛异常，
      // 必须整体兜底，避免异常冒泡到发送链路导致 UI 卡死。
      try {
        final document = PdfDocument(inputBytes: bytes);
        try {
          return PdfTextExtractor(document).extractText();
        } finally {
          document.dispose();
        }
      } catch (_) {
        return null;
      }
    }
    if (const {'txt', 'md', 'csv', 'json'}.contains(extension)) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return null;
  }
}
