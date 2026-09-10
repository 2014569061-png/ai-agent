import '../domain/tool_result.dart';

/// 仅用于持久化、导出和诊断出口的敏感工具策略。
///
/// 当前回合发送给模型的上下文保持原文；一旦进入 SQLite、备份或日志，
/// 敏感参数和结果统一替换为占位符，避免凭证、命令输出和记忆内容通过
/// 历史数据再次暴露。
///
/// ─────────────────────────────────────────────────────────────────────
/// ⚠️ 本类只负责「持久化脱敏」，与「强制人工审批」是两条**互相独立**的线，
/// 严禁互相驱动，否则会造成严重 UX 回归：
///
///   1. `UnifiedTool.sensitive`（domain/models.dart）—— 驱动**强制人工审批**。
///      它经 ToolSpec.sensitive → AgentExecutor → ApprovalPolicy.decide(sensitive:)，
///      只要为 true 就**无条件**要求用户确认。给 read_file / terminal /
///      write_file 等工具误加这个标记，会导致每次读写文件都弹审批，直接毁掉
///      Agent 体验。**本类名单里的工具不得据此改成 UnifiedTool.sensitive。**
///
///   2. `SensitiveToolPolicy`（本类）—— 驱动**持久化脱敏**，只影响写入
///      SQLite、会话/保险箱导出、run 事件与日志的内容，不影响审批，也不影响
///      当前回合回灌给模型的上下文。
///
/// 两者判定口径本就不同，请勿合并：
///   · 参数脱敏看「参数里能不能夹带凭证/第三方机密」（HTTP 头、命令行、写入内容）；
///   · 结果脱敏看「结果里能不能回带机密或他人数据」。
/// ─────────────────────────────────────────────────────────────────────
///
/// 历史坑（B-8）：本类曾硬编码一份含 `read_image`、`clipboard_*` 等**并不存在**
/// 的工具名，同时漏掉了 `http_request` / `terminal` / `write_file` 等真实高敏工具，
/// 导致它们的原始参数与结果明文落库，推翻了 README 的公开承诺。为此增加了
/// 守护测试 `test/sensitive_tool_policy_test.dart`，遍历真实工具目录校验
/// 名单不再出现「死条目」与「漏配」。
class SensitiveToolPolicy {
  const SensitiveToolPolicy._();

  /// 参数需要在持久化出口脱敏的工具（参数可能携带凭证、令牌或第三方机密）。
  static const Set<String> argumentRedactedTools = <String>{
    'http_request', // Authorization / X-Api-Key 等请求头，或含密钥的 body
    'terminal', // 命令行参数可能含 token、私有路径
    'write_file', // 写入内容可能含密钥、隐私文本
    'edit_file', // 同上（替换/追加的内容）
    'memory_write', // 记忆正文可能含隐私
    'remember', // 记忆正文可能含隐私
  };

  /// 结果需要在持久化出口脱敏的工具（结果可能回带机密或他人数据）。
  ///
  /// 注意：**`read_file` 不在此列**——那是用户自己的工作区文件，历史里回看
  /// 需要看到内容；它的参数也只是一个路径，同样不脱敏。
  static const Set<String> resultRedactedTools = <String>{
    'http_request', // 响应头/体可能含令牌
    'terminal', // 命令输出可能含 token、私有路径、环境变量
    'memory_get', // 记忆内容
    'memory_write', // 写回时的 revision/回显
    'remember', // 回显出的记忆正文
    'sub_agent', // 子 Agent 摘要可能含委派提示词与中间机密
    'generate_image', // 提示词与返回的远端图片 URL
  };

  /// MCP 远端工具的命名形态，参数与结果都按敏感处理：
  ///   · `mcp_` 前缀是当前约定；
  ///   · `${server}.${tool}` 是 v0.8.x 已持久化的旧命名，导出/日志时不能漏出
  ///     远端数据。
  static bool _isRemoteLike(String name) =>
      name.startsWith('mcp_') || name.contains('.');

  /// 参数是否需要脱敏（参数语境专用）。
  static bool isArgumentSensitive(String name) =>
      argumentRedactedTools.contains(name) || _isRemoteLike(name);

  /// 结果是否需要脱敏（结果语境专用）。
  static bool isResultSensitive(String name) =>
      resultRedactedTools.contains(name) || _isRemoteLike(name);

  /// 粗粒度判定：参数或结果任一需要脱敏即为 true。
  ///
  /// **仅**用于「只有一个开关」的粗粒度出口——审计详情、诊断日志、run 事件的
  /// `sensitive` 标记：这些出口会同时处理参数与结果，取并集更保守。
  /// 明确的参数/结果出口请分别用 [isArgumentSensitive] / [isResultSensitive]，
  /// 不要用本方法。
  static bool isSensitive(String name) =>
      isArgumentSensitive(name) || isResultSensitive(name);

  /// 参数占位脱敏（写入 SQLite / 会话导出 / 任务快照等参数出口）。
  static Map<String, dynamic> redactArguments(
      String toolName, Map<String, dynamic> arguments) {
    if (!isArgumentSensitive(toolName)) {
      return Map<String, dynamic>.from(arguments);
    }
    return const <String, dynamic>{'redacted': true};
  }

  /// 结果脱敏（写入 SQLite / 会话导出等结果出口）。保留 ok / code / effect
  /// 等契约字段，仅替换 message 与 data 载荷。
  static ToolResult redactResult(String toolName, ToolResult result) {
    if (!isResultSensitive(toolName)) return result;
    return ToolResult(
      ok: result.ok,
      code: result.code,
      message: result.ok ? '敏感工具结果已脱敏' : '$toolName 结果已脱敏',
      data: const <String, dynamic>{'redacted': true},
      effect: result.effect,
    );
  }

  /// 结果文本脱敏（run 事件 outputSummary、会话导出等结果语境）。
  static String redactResultText(String toolName, String value) =>
      isResultSensitive(toolName) ? '[敏感工具内容已脱敏]' : value;

  /// 参数文本脱敏（run 事件 inputSummary 等参数语境）。
  static String redactArgumentText(String toolName, String value) =>
      isArgumentSensitive(toolName) ? '[敏感工具参数已脱敏]' : value;

  /// 兼容 presentation 层会话复制导出（那是**结果**语境）。
  ///
  /// 等价于 [redactResultText]；保留两参签名以免破坏调用方，但**不要**在参数
  /// 语境使用它——参数语境请用 [redactArgumentText]。
  static String redactText(String toolName, String value) =>
      redactResultText(toolName, value);
}
