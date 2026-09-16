/// 审批通知正文的生成规则。
///
/// 单独成文件是为了可单测：这段文字会显示在**锁屏**上，旁人也能看到，因此
/// 「敏感工具绝不能带参数原文」是一条安全约束，不能只靠代码评审守住。
library;

import 'dart:convert';

import '../domain/models.dart';
import '../domain/sensitive_tool_policy.dart';

/// 生成审批通知正文。
///
/// - 参数敏感的工具（由 [SensitiveToolPolicy] 判定）**只显示工具名与风险等级**，
///   与持久化出口的脱敏口径一致；
/// - 其余工具的参数序列化后截断，避免长参数把通知撑成一屏。
String approvalNotificationSummary(ToolCall call, ToolRisk risk) {
  final label = '${call.name}（${riskLabel(risk)}）';
  if (SensitiveToolPolicy.isArgumentSensitive(call.name)) return label;
  if (call.arguments.isEmpty) return label;
  final String encoded;
  try {
    encoded = jsonEncode(call.arguments);
  } catch (_) {
    // 参数里有无法序列化的对象时，宁可只说工具名，也不要抛异常打断审批。
    return label;
  }
  final trimmed =
      encoded.length <= 120 ? encoded : '${encoded.substring(0, 120)}…';
  return '$label\n$trimmed';
}

String riskLabel(ToolRisk risk) => switch (risk) {
      ToolRisk.safe => '安全',
      ToolRisk.requiresConfirmation => '需确认',
      ToolRisk.dangerous => '高风险',
    };
