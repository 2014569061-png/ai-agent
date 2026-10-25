import 'dart:convert';
import 'dart:math' as math;

import '../domain/models.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/tools/workspace_tools.dart';
import 'context_window.dart';

/// Reads through the existing sandbox; never dispatches arbitrary tools while
/// compacting. Excerpts are data and do not authorize editing unseen contents.
class CompactionRecovery {
  CompactionRecovery(this.tools, {this.currentPlan});
  final ToolRegistry tools;
  final String Function()? currentPlan;
  static const mark = '[压缩后恢复：当前规则、计划和文件快照；文件片段仅供参考，编辑前须 read_file]';

  Future<String> recover(List<ChatMessage> history, int maxChars) async {
    if (maxChars < 256) return '';
    final reader = tools.find('read_file');
    if (reader is! ReadFileTool) return '';
    final sandbox = reader.sandbox;
    sandbox.forgetReads();
    final sections = <String>[];
    var remaining = maxChars - mark.length - 1;
    void add(String text, int cap) {
      if (remaining < 64) return;
      final bounded =
          ContextWindow.truncateToolResult(text, math.min(remaining - 1, cap));
      sections.add(bounded);
      remaining -= bounded.length + 1;
    }

    var plan = currentPlan?.call() ?? '';
    if (plan.trim().isEmpty) {
      plan = history.reversed
              .expand((m) => m.toolCalls.reversed)
              .where((c) => c.name == 'manage_plan')
              .map((c) => jsonEncode(c.arguments))
              .firstOrNull ??
          '';
    }
    if (plan.isNotEmpty) add('当前计划：${jsonEncode(plan)}', maxChars ~/ 4);
    for (final name in [
      'AGENTS.md',
      'NEXUS.md',
      'CLAUDE.md',
      '.nexus/rules.md',
      '.cursorrules'
    ]) {
      try {
        final content = await sandbox.fs
            .readText(sandbox.resolvePath(name), maxBytes: 64 * 1024);
        add('当前规则 ${jsonEncode(name)}：${jsonEncode(content)}',
            math.max(64, maxChars ~/ 12));
      } catch (_) {
        // Missing/unreadable rules cannot prevent recovery of actual files.
      }
    }
    final paths = <String>{};
    for (final message in history.reversed) {
      for (final call in message.toolCalls.reversed) {
        if (call.name == 'read_file' && call.arguments['path'] is String) {
          paths.add(call.arguments['path'] as String);
          if (paths.length == 5) break;
        }
      }
      if (paths.length == 5) break;
    }
    var left = paths.length;
    for (final path in paths) {
      final cap = remaining ~/ left--;
      if (cap < 64) continue;
      try {
        final content = await sandbox.fs
            .readText(sandbox.resolvePath(path), maxBytes: 64 * 1024);
        add('当前文件 ${jsonEncode(path)}：${jsonEncode(content)}', cap);
      } catch (_) {
        add('文件 ${jsonEncode(path)} 未恢复（不存在、过大或无法读取），请重新检查。', cap);
      }
    }
    return sections.isEmpty ? '' : '$mark\n${sections.join('\n')}';
  }
}
