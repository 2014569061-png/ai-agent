import 'dart:convert';

/// 解码任务 JSON 对象：非对象或解析失败时返回空 Map。
/// 历史记录损坏时按“无字段”处理，调用方自带默认值。
Map<String, dynamic> decodeTaskJsonObject(String json) {
  try {
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : const {};
  } catch (_) {
    // 损坏的任务记录按空对象处理，由调用方使用默认值。
    return const {};
  }
}
