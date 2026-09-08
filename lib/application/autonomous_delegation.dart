import 'package:shared_preferences/shared_preferences.dart';

/// 全局开关：主 Agent 是否可自主派生子 Agent（sub_agent 调用自动放行）。
///
/// - 开启（默认）：sub_agent 调用按安全工具处理，自动放行，子 Agent 内部仍只放行
///   安全工具，形成"默认自主安全策略"。
/// - 关闭：sub_agent 调用回退到 requiresConfirmation，与既有审批模式（ask /
///   autoSafe / fullAccess）完全兼容。
///
/// 读取失败（如测试环境未初始化插件）时保守返回开启，避免阻断主流程。
class AutonomousDelegationService {
  static const _key = 'agent.autonomous_delegation';

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
