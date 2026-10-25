import 'package:shared_preferences/shared_preferences.dart';

/// 「设置 → 工具」页面的全局工具开关快照，从
/// SharedPreferences（settings.tool.*）读取并在此处统一消费。
/// 关闭的开关会对应地从工具注册表中剔除对应工具。
class ToolSettings {
  const ToolSettings({
    this.webBrowsing = false,
    this.workspaceFiles = true,
    this.terminal = true,
  });

  static Future<ToolSettings> load({bool webBrowsing = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getBool('settings.tool.terminal_file') ?? true;
      return ToolSettings(
        webBrowsing: webBrowsing,
        workspaceFiles:
            prefs.getBool('settings.tool.workspace_files') ?? legacy,
        terminal: prefs.getBool('settings.tool.terminal') ?? legacy,
      );
    } catch (_) {
      // Settings storage is optional; retain the existing migration defaults.
      return ToolSettings(webBrowsing: webBrowsing);
    }
  }

  /// 网页浏览（web_search）。默认关闭，避免普通聊天隐式携带联网工具。
  final bool webBrowsing;

  /// 工作区内的文件读取、创建和编辑工具。
  final bool workspaceFiles;

  /// 在已选择工作区内执行命令的工具。
  final bool terminal;
}
