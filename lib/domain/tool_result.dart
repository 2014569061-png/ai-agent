import 'dart:convert';

import 'tool_codes.dart';

/// 工具调用对世界产生的实际影响。
///
/// [unknown] 是一等公民，不是兜底值：移动端进程随时可能被回收，命令超时、
/// 通道异常、写盘中途失败时，往往**无法证明操作没有发生**。把“不知道”如实
/// 上报，模型才会先去读取确认，而不是盲目重试造成二次破坏（重复删除、
/// 重复提交、重复下单）。
enum ToolEffect {
  /// 确定没有产生副作用：参数校验失败、目标不存在、权限拒绝等。
  none,

  /// 确定已经生效，且通常可给出证据（写入字节数、退出码、新大小等）。
  applied,

  /// 无法判定是否生效。message 必须明确写出“可能已执行，请先读取确认”。
  unknown,
}

/// 统一的工具结果信封。
///
/// 回灌给模型的永远是结构化 JSON（[encode]），而不是自然语言句子：模型需要
/// 能可靠区分“可重试 / 该换方案 / 到底执行了没有”。给人看的短摘要走 [display]，
/// 两者分离后 UI 与审计不必再去正则猜测成败。
class ToolResult {
  const ToolResult({
    required this.ok,
    required this.code,
    required this.message,
    this.data,
    this.effect = ToolEffect.none,
  });

  /// 纯文本载荷的成功结果：文本进 `data.text`，[message] 取其首行摘要。
  ///
  /// 这是从“工具直接返回字符串”迁移过来的主路径，保持载荷对模型完整可见。
  factory ToolResult.text(
    String text, {
    ToolEffect effect = ToolEffect.none,
    Map<String, dynamic>? extra,
  }) {
    final firstLine = text.split('\n').first.trim();
    final summary = firstLine.length > summaryChars
        ? '${firstLine.substring(0, summaryChars)}…'
        : firstLine;
    return ToolResult(
      ok: true,
      code: ToolCodes.ok,
      message: summary.isEmpty ? '完成' : summary,
      data: {
        'text': text,
        'chars': text.length,
        if (extra != null) ...extra,
      },
      effect: effect,
    );
  }

  /// 结构化载荷的成功结果。[message] 应是简短的人类可读说明。
  factory ToolResult.success({
    String message = '完成',
    Map<String, dynamic>? data,
    ToolEffect effect = ToolEffect.none,
  }) =>
      ToolResult(
        ok: true,
        code: ToolCodes.ok,
        message: message,
        data: data,
        effect: effect,
      );

  /// 失败结果。[effect] 必须如实反映“这次到底动没动”；
  /// 判不了就用 [ToolEffect.unknown]，不要谎报 none。
  factory ToolResult.failure({
    required String code,
    required String message,
    Map<String, dynamic>? data,
    ToolEffect effect = ToolEffect.none,
  }) =>
      ToolResult(
        ok: false,
        code: code,
        message: message,
        data: data,
        effect: effect,
      );

  /// [display] 摘要的单行长度上限。
  static const summaryChars = 80;

  final bool ok;
  final String code;
  final String message;
  final Map<String, dynamic>? data;
  final ToolEffect effect;

  /// 副作用是否已确定生效——审计与“可否撤销”判断的依据。
  bool get hasSideEffect => effect != ToolEffect.none;

  /// 结果是否需要人工确认后才能继续（副作用未知）。
  bool get needsVerification => effect == ToolEffect.unknown;

  /// 回灌给模型的 JSON 文本。始终可解析，字段顺序稳定。
  String encode() => jsonEncode({
        'ok': ok,
        'code': code,
        'message': message,
        if (effect != ToolEffect.none) 'effect': effect.name,
        if (data != null) 'data': data,
      });

  /// 给用户与审计看的短摘要，不含完整载荷。
  String get display => ok ? message : '$code: $message';

  @override
  String toString() => 'ToolResult(${encode()})';
}
