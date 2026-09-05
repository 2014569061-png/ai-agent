import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';

/// 全局「始终允许」工具信任清单。
///
/// 持久化只保存 `allowAlways` 级（restart 后仍生效）；`allowSession` 级
/// 仅存内存，随本次 App 会话结束即失效。`allowOnce` 不在此存储。
/// 危险（dangerous）工具永不入清单，由调用方在 [isTrusted] 处硬性拦截。
class ToolTrustStore {
  static const _prefsKey = 'tool.trusted';

  /// 持久化的「始终允许」清单：toolName -> true。
  Map<String, bool> _always = {};

  /// 本会话内「允许」清单：toolName -> true。
  final Set<String> _session = {};

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 本地加载（启动时由 provider 初值触发一次），返回当前始终允许清单。
  Future<void> init() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        _always = {};
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _always = Map<String, bool>.fromEntries(
            decoded.entries.map((e) => MapEntry(e.key, e.value == true)));
      }
    } catch (_) {
      _always = {};
    }
  }

  /// 该工具当前是否被信任（命中即自动放行）。
  /// dangerous 级一律不信任；safe 级无需审批，直接返回 true 以短路。
  bool isTrusted(String name, ToolRisk risk) {
    if (risk == ToolRisk.safe) return true;
    if (risk == ToolRisk.dangerous) return false;
    return _always[name] == true || _session.contains(name);
  }

  Future<void> _persist() async {
    try {
      final prefs = await _prefs;
      await prefs.setString(
          _prefsKey, jsonEncode(Map<String, bool>.from(_always)));
    } catch (_) {
      // 持久化失败不阻断本次会话内的生效。
    }
  }

  /// 记录「始终允许」（不可用于 dangerous）。
  Future<void> allowAlways(String name) async {
    _always[name] = true;
    await _persist();
  }

  /// 只移除持久化的「始终允许」（会话级随 restarts 自动失效，无需显式移除）。
  Future<void> removeAlways(String name) async {
    _always.remove(name);
    await _persist();
  }

  /// 记录「本会话允许」。
  void allowSession(String name) => _session.add(name);

  /// 当前持久化的「始终允许」清单（用于设置页展示与收回）。
  List<String> get alwaysAllowed =>
      _always.entries.where((e) => e.value).map((e) => e.key).toList();
}
