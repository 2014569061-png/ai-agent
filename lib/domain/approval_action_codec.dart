/// 通知动作 id 的编解码。
///
/// 放在 domain 层而不是 application：它同时被 application（审批桥）与
/// infrastructure（通知服务）使用，而分层规则只允许 infrastructure → domain。
/// 放在 application 会形成 infrastructure → application 的反向依赖（已有测试守护）。
///
/// 它是纯函数，最容易单测，也最容易被改坏——格式一旦前后端不一致，症状是
/// 「点了批准却一直没反应」，日志里什么也看不到。
library;

const String approvalApproveAction = 'approve';
const String approvalDenyAction = 'deny';

/// 从通知动作 id 解析出的裁决意图。
class ApprovalActionRequest {
  const ApprovalActionRequest({required this.requestId, required this.approve});

  final String requestId;
  final bool approve;
}

/// 编码为 `approve:<requestId>` / `deny:<requestId>`。
String encodeApprovalActionId(String requestId, {required bool approve}) =>
    '${approve ? approvalApproveAction : approvalDenyAction}:$requestId';

/// 解析动作 id；无法识别时返回 null（调用方应忽略，不要猜）。
///
/// 用第一个冒号切分，因此 requestId 自身含冒号也不会解析错位。
ApprovalActionRequest? parseApprovalActionId(String? actionId) {
  if (actionId == null) return null;
  final separator = actionId.indexOf(':');
  if (separator <= 0) return null;
  final verb = actionId.substring(0, separator);
  final requestId = actionId.substring(separator + 1).trim();
  if (requestId.isEmpty) return null;
  switch (verb) {
    case approvalApproveAction:
      return ApprovalActionRequest(requestId: requestId, approve: true);
    case approvalDenyAction:
      return ApprovalActionRequest(requestId: requestId, approve: false);
    default:
      return null;
  }
}
