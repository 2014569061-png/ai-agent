/// 运行形态。决定默认策略（有无真人在场、是否记录会话日志）。
enum RunKind { chat, background, scheduled, subagent, collaboration }

/// 一类运行的静态配置（对应 Harness 的 profile 概念，但只保留本项目需要的
/// 维度；新增维度前先确认至少两种运行形态会用到它）。
class RunProfile {
  const RunProfile._(
    this.kind, {
    required this.interactive,
    required this.recordSession,
  });

  final RunKind kind;

  /// 有真人在场，可审批、插话、暂停。
  final bool interactive;

  /// 是否写会话日志；仍需 [RunScope.sessionId] 非空才会真正记录。
  final bool recordSession;

  /// 前台聊天。
  static const chat =
      RunProfile._(RunKind.chat, interactive: true, recordSession: true);

  /// 绑定任务的后台运行（恢复执行、开发闭环）。
  static const background =
      RunProfile._(RunKind.background, interactive: false, recordSession: true);

  /// 定时任务。
  static const scheduled =
      RunProfile._(RunKind.scheduled, interactive: false, recordSession: true);

  /// 子 Agent：结果以工具结果形式进入父会话日志，自身不单独记录。
  static const subagent =
      RunProfile._(RunKind.subagent, interactive: false, recordSession: false);

  /// 多角色交叉验证中的单个角色：结论汇总进协作记录，不单独记录。
  static const collaboration = RunProfile._(RunKind.collaboration,
      interactive: false, recordSession: false);

  @override
  String toString() => 'RunProfile(${kind.name})';
}

/// 一次具体运行的标识与归属。
class RunScope {
  const RunScope({
    required this.profile,
    required this.runId,
    required this.model,
    this.sessionId,
    this.taskId,
    this.workspacePath,
  });

  final RunProfile profile;
  final String runId;
  final String model;

  /// 会话日志的归属（session_events.conversation_id）；null 表示不记录。
  final String? sessionId;
  final String? taskId;
  final String? workspacePath;

  /// 绑定任务的后台运行共用一条会话日志：同一任务的多次恢复执行依次追加。
  static String taskSessionId(String taskId) => 'task:$taskId';
}
