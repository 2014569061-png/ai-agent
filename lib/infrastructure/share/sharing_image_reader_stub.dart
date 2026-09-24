/// 单张分享图片允许内联成 data URI 的最大原始字节数。
const int maxSharedImageBytes = 4 * 1024 * 1024;

/// Web / 无 `dart:io` 的平台不支持分享图片读取，统一降级为未读取。
Future<String?> sharedImageToPromptText(String path) async => null;
