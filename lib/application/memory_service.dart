import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/database/app_database.dart';

/// 长期记忆服务：负责记忆的增删改查与「注入提示词」文本块构建。
///
/// 设计要点：
/// - 全部本地（SQLite），延续「本地优先」隐私叙事。
/// - 注入按 `importance DESC, updatedAt DESC` 排序，并按字符预算截断，
///   避免记忆过多挤占模型上下文。
/// - 总开关存 SharedPreferences，关闭后注入块返回空串。
class MemoryService {
  static const _prefsKeyEnabled = 'memory_enabled';
  static const _defaultInjectionBudget = 800;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
  }

  /// 构建待注入到系统提示词的记忆块。总开关关闭或无可注入记忆时返回空串。
  Future<String> buildInjectionBlock(AppDatabase database,
      {int budget = _defaultInjectionBudget}) async {
    if (!await isEnabled()) return '';
    final memories = await database.enabledMemories();
    if (memories.isEmpty) return '';
    final buffer = StringBuffer('## 长期记忆（你已知晓的关于用户的事实）\n');
    var used = 0;
    for (final memory in memories) {
      final line = '- ${memory.content}\n';
      if (used + line.length > budget) break;
      buffer.write(line);
      used += line.length;
    }
    return buffer.toString();
  }

  Future<Memory> add({
    required AppDatabase database,
    required String content,
    String category = 'general',
    String? sourceConversationId,
    String sourceType = 'manual',
    int importance = 1,
  }) async {
    final now = DateTime.now();
    final memory = Memory(
      id: 'memory-${now.microsecondsSinceEpoch}',
      content: content.trim(),
      category: category,
      sourceConversationId: sourceConversationId,
      sourceType: sourceType,
      enabled: true,
      importance: importance,
      createdAt: now,
      updatedAt: now,
    );
    await database.saveMemory(memory);
    return memory;
  }

  Future<void> update(AppDatabase database, Memory memory) async {
    await database.saveMemory(memory.copyWith(updatedAt: DateTime.now()));
  }

  Future<void> delete(AppDatabase database, String id) async {
    await database.deleteMemory(id);
  }
}

final memoryServiceProvider = Provider<MemoryService>((ref) => MemoryService());
