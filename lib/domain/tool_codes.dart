/// 工具结果错误码登记表。
///
/// 错误码是给模型的“可编程契约”，不是给人看的文案：模型据此判断该重试、
/// 该换方案、还是该先去读取确认。新增码请同时补充语义注释，避免同义码泛滥。
abstract final class ToolCodes {
  /// 成功。
  static const ok = 'OK';

  // ---- 调用合同层（参数/协议问题，一律 effect=none）----

  /// 参数不符合本轮下发的 JSON Schema，或缺少必填项。
  static const invalidArguments = 'INVALID_ARGUMENTS';

  /// 模型请求的工具不在本次运行的能力目录中（可能引用了上一轮的旧目录）。
  static const unknownTool = 'UNKNOWN_TOOL';

  /// 服务商在长度上限处截断，工具参数可能不完整，本次未执行。
  static const truncatedToolCall = 'TRUNCATED_TOOL_CALL';

  /// 停因不是工具调用却夹带了工具调用，属于协议矛盾，本次未执行。
  static const unexpectedToolCall = 'UNEXPECTED_TOOL_CALL';

  /// 工具内部未预期异常。effect 由具体工具判定，不得默认 none。
  static const toolError = 'TOOL_ERROR';
  static const malformedResponse = 'MALFORMED_RESPONSE';
  static const cancelled = 'CANCELLED';
  static const timeout = 'TIMEOUT';
  static const payloadTooLarge = 'PAYLOAD_TOO_LARGE';

  // ---- 授权与能力层 ----

  /// 用户在审批弹窗中拒绝了本次调用；模型应换方案或向用户说明。
  static const approvalRejected = 'APPROVAL_REJECTED';
  static const sensitiveApprovalRequired = 'SENSITIVE_APPROVAL_REQUIRED';

  /// 缺少 Android 权限或系统授权（通知使用权、定位、所有文件访问等）。
  static const permissionRequired = 'PERMISSION_REQUIRED';

  /// 该工具需要 Root，当前设备没有 Root 授权，本次未执行。
  static const rootRequired = 'ROOT_REQUIRED';

  /// 该工具在当前平台不可用。
  static const platformUnsupported = 'PLATFORM_UNSUPPORTED';

  /// 工具已在设置中被关闭，本次未执行。
  static const toolDisabled = 'TOOL_DISABLED';
  static const capabilityUnavailable = 'CAPABILITY_UNAVAILABLE';

  // ---- 执行环境层 ----

  /// Linux/终端环境尚未安装或未就绪。
  static const linuxNotReady = 'LINUX_NOT_READY';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const ownerMismatch = 'OWNER_MISMATCH';
  static const resultPending = 'RESULT_PENDING';

  /// 网络不可用或请求失败。
  static const networkUnavailable = 'NETWORK_UNAVAILABLE';

  /// 依赖的外部服务未配置（如缺少 API Key）。
  static const notConfigured = 'NOT_CONFIGURED';
  static const credentialInvalid = 'CREDENTIAL_INVALID';
  static const rateLimited = 'RATE_LIMITED';

  // ---- 资源层 ----

  /// 目标不存在（文件、路径、记录等）。
  static const notFound = 'NOT_FOUND';

  /// 路径越出工作区沙箱，或包含非法片段。
  static const sandboxViolation = 'SANDBOX_VIOLATION';

  /// 目标已存在，且调用未声明允许覆盖。
  static const alreadyExists = 'ALREADY_EXISTS';

  /// 载荷超出上限（读取字节数、写入大小、结果长度等）。
  static const tooLarge = 'TOO_LARGE';
  static const ioError = 'IO_ERROR';
  static const invalidFormat = 'INVALID_FORMAT';

  // ---- 状态一致性层 ----

  /// 动作已提交但结果无法确认；禁止盲目重放，应先读取确认。
  static const outcomeUnknown = 'OUTCOME_UNKNOWN';

  /// 上一轮的状态变更结果不确定，本轮冻结该能力，下一轮再试。
  static const nextTurnRequired = 'NEXT_TURN_REQUIRED';

  /// 记忆/文档的 revision 与当前内容不一致，存在并发修改。
  static const revisionConflict = 'REVISION_CONFLICT';
}
