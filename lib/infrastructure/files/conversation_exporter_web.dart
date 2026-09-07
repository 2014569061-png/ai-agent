// Browser downloads still use the stable dart:html API on the web target;
// the conditional export keeps this implementation out of native builds.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

String _safeFileName(String title, String extension) {
  final safeTitle = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return '${safeTitle.isEmpty ? 'conversation' : safeTitle}-${DateTime.now().millisecondsSinceEpoch}.$extension';
}

Future<String> _download(
    String title, String content, String extension, String mime) async {
  final fileName = _safeFileName(title, extension);
  final blob = html.Blob([utf8.encode(content)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

Future<String> exportConversationMarkdown(String title, String content) =>
    _download(title, content, 'md', 'text/markdown;charset=utf-8');

Future<String> exportConversationJson(String title, String content) =>
    _download(title, content, 'json', 'application/json;charset=utf-8');
