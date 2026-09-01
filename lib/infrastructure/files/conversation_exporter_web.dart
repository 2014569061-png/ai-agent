/// Web 端暂不支持写文件，返回空串表示未导出（由调用方回退为复制到剪贴板）。
Future<String> exportConversationMarkdown(String title, String content) async => '';
