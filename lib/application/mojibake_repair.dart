import 'dart:convert';

/// Repairs the UTF-8-as-Latin-1 mojibake strings written by early builds.
///
/// 早期版本把 UTF-8 字节序列误按 Latin-1 解码写入数据库，导致中文变成
/// `閫氱敤鍔╂墜` 这类乱码。修复分两层：
/// 1. 已知对照表的子串替换（兜底，覆盖无法安全全串逆转的情形）；
/// 2. 全串的「Latin-1 码元 → UTF-8 字节 → 解码」通用逆转。
abstract final class MojibakeRepair {
  static const _known = <String, String>{
    '閫氱敤鍔╂墜': '通用助手',
    '鏂颁細': '新会话',
    '鑱婂ぉ椤电殑瀹屾暣涓嶅彲鍙樼姸鎬': '聊天页的完整不可变状态',
    '浼氳瘽': '会话',
    '璇锋眰': '请求',
    '鎴愬姛': '成功',
    '澶辫触': '失败',
  };

  static String repair(String value) {
    if (value.isEmpty) return value;
    var repaired = value;
    for (final entry in _known.entries) {
      repaired = repaired.replaceAll(entry.key, entry.value);
    }
    // 若仍含乱码字节形态则尝试通用逆转码；成功则整体还原。
    final reversed = _reverseTranscode(repaired);
    return reversed ?? repaired;
  }

  /// 把「UTF-8 字节被当作 Latin-1 解码」的乱码串还原为原始文本。
  /// 仅在全部字符都是 0x00..0xFF、且能合法解码为规范 UTF-8、且结果不同时返回，
  /// 否则返回 null（避免误伤正常文本）。
  static String? _reverseTranscode(String value) {
    final bytes = <int>[];
    for (final rune in value.runes) {
      if (rune > 0xFF) return null; // 含合法 BMP 字符，不是整串乱码
      bytes.add(rune);
    }
    if (bytes.isEmpty) return null;
    try {
      final decoded = utf8.decode(bytes);
      if (decoded == value) return null; // 本来就是 UTF-8，无需修复
      return decoded;
    } on FormatException {
      return null; // 非规范 UTF-8，不强行修复
    }
  }

  static bool changed(String value) => repair(value) != value;
}
