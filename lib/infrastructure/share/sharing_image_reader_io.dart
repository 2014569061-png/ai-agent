import 'dart:convert';
import 'dart:io';

/// 单张分享图片允许内联成 data URI 的最大原始字节数。
///
/// 分享进来的 base64 会被直接拼进对话文本并随请求发给模型。不设上限时，一张
/// 40MP 照片（几十 MB）会同时撑爆内存和请求体，而各 Provider 普遍只接受 5MB
/// 以下的单张图片。超限时退化成一句可读说明，用户仍能在对话里看到这张图存在。
const int maxSharedImageBytes = 4 * 1024 * 1024;

/// 把分享进来的图片文件转成可直接放进对话的文本。
///
/// 返回 data URI，或一句人类可读的说明（过大 / 不可读时不再内联）；返回 null
/// 表示该路径读不到，由调用方决定回退文案。
///
/// 全程异步：此前用 `readAsBytesSync` 在 UI 线程同步读整个文件再 base64，分享
/// 一张大图就会直接把掉帧写进用户可见的动画里。
Future<String?> sharedImageToPromptText(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length <= 0) return null;
    if (length > maxSharedImageBytes) {
      final megabytes = (length / (1024 * 1024)).toStringAsFixed(1);
      return '[图片过大（${megabytes}MB），已跳过内联：$path]';
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    if (bytes.length > maxSharedImageBytes) {
      return '[图片过大，已跳过内联：$path]';
    }
    return 'data:${_mimeTypeOf(path)};base64,${base64Encode(bytes)}';
  } catch (_) {
    // 分享进来的路径可能已被系统清理或没有读权限，静默降级。
    return null;
  }
}

String _mimeTypeOf(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}
