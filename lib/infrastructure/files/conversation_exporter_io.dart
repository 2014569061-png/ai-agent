import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 将会话内容导出为 Markdown 文件，返回保存的绝对路径。
Future<String> exportConversationMarkdown(String title, String content) async {
  final safeTitle = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final fileName =
      '${safeTitle.isEmpty ? 'conversation' : safeTitle}-${DateTime.now().millisecondsSinceEpoch}.md';
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(content);
  return file.path;
}
