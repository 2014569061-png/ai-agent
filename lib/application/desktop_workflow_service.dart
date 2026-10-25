import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopWorkflow {
  const DesktopWorkflow(
      {required this.id, required this.name, required this.prompt});
  final String id, name, prompt;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'prompt': prompt};
  factory DesktopWorkflow.fromJson(Map<String, dynamic> map) {
    final id = map['id'], name = map['name'], prompt = map['prompt'];
    if (id is! String ||
        name is! String ||
        prompt is! String ||
        name.trim().isEmpty ||
        prompt.trim().isEmpty ||
        prompt.length > 32000) {
      throw const FormatException('工作流需要有效的名称和任务指令');
    }
    return DesktopWorkflow(id: id, name: name.trim(), prompt: prompt.trim());
  }
  static const builtins = [
    DesktopWorkflow(
        id: 'builtin-fix',
        name: '修复报错',
        prompt:
            '请先复现当前项目的报错，定位原因，提出最小修改方案。经计划确认后修改，运行相关检查，并列出修改文件、验证命令、退出码、剩余问题和恢复方式。不要把未执行的检查标记为通过。'),
    DesktopWorkflow(
        id: 'builtin-feature',
        name: '实现功能并测试',
        prompt:
            '请先分析项目约定与相关代码，为我描述的功能制定实施与验收计划。确认后完成实现、运行有意义的检查，提供改动摘要、实际测试证据、产物位置及未完成项。'),
    DesktopWorkflow(
        id: 'builtin-review',
        name: '审查当前改动',
        prompt:
            '请只读审查当前 Git 改动，按严重程度列出可复现的问题、文件位置、触发条件和建议修复方式。报告实际检查依据与覆盖范围，不自动修改或提交文件。'),
  ];
}

class DesktopWorkflowService {
  static const _key = 'desktop.workflows.v1';
  Future<List<DesktopWorkflow>> custom() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((item) =>
            DesktopWorkflow.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> save(List<DesktopWorkflow> workflows) async {
    if (workflows.length > 100) throw StateError('最多保存 100 个自定义工作流');
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(workflows.map((w) => w.toJson()).toList()));
  }

  String export(List<DesktopWorkflow> workflows) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'workflows': workflows.map((w) => w.toJson()).toList()
      });
  List<DesktopWorkflow> parse(String raw) {
    if (raw.length > 1024 * 1024) throw const FormatException('工作流文件过大');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['version'] != 1 || map['workflows'] is! List) {
      throw const FormatException('不支持的工作流格式');
    }
    final items = map['workflows'] as List;
    if (items.length > 100) throw const FormatException('工作流数量过多');
    return items
        .map((item) =>
            DesktopWorkflow.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}
