/// F20 可操作结果卡的领域定义。
///
/// 设计要点：结果卡只描述「可以对哪个真实资源做什么」，不携带可执行命令。
/// 动作类型必须在 [ResultActionRegistry] 中注册，服务与界面都只接受已注册
/// 类型；模型即使生成了一个带伪造按钮的卡片，也无法让客户端执行任意动作。
library;

/// Persisted approval authority, distinct from a caller-provided DTO. Production
/// SQL execution verifies this at confirmation and again at dispatch.
abstract interface class ResultActionApprovalVerifier {
  Future<bool> verify(
      {required ResultActionRecord action,
      required ResultCard card,
      required String approvalId,
      required DateTime expiresAt,
      bool forExecution = false});
}

/// 六类结构化结果卡。
///
/// 枚举的 wireName 是持久化与协议用的稳定字符串，避免依赖枚举下标。
enum ResultCardKind {
  reminder('reminder', '提醒'),
  calendar('calendar', '日程'),
  file('file', '文件'),
  route('route', '路线'),
  workflowTrial('workflow_trial', '工作流试运行'),
  codeDiff('code_diff', '代码差异');

  const ResultCardKind(this.wireName, this.label);

  /// 持久化/协议中的稳定标识。
  final String wireName;

  /// 中文展示名。
  final String label;

  /// 未知类型返回 null；调用方必须把它当成「不可渲染/不可操作」而不是猜一个默认值。
  static ResultCardKind? fromWire(String value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// 卡片所指资源在最近一次刷新时的状态。
///
/// 卡片本身不做自动推断：状态必须由重新读取资源的服务写入。
enum ResultCardStatus {
  active('active', '可用'),
  expired('expired', '已过期'),
  changed('changed', '已变化'),
  unavailable('unavailable', '不可用'),
  unknown('unknown', '状态未知');

  const ResultCardStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static ResultCardStatus? fromWire(String value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    return null;
  }
}

/// 动作风险等级。等级与「是否需要确认」都由注册表声明，不接受调用方临时传参，
/// 否则模型或界面可以把自己包装成低风险动作绕过审批。
enum ResultActionRisk {
  low('low', '低风险'),
  medium('medium', '中风险'),
  high('high', '高风险');

  const ResultActionRisk(this.wireName, this.label);

  final String wireName;
  final String label;

  static ResultActionRisk? fromWire(String value) {
    for (final risk in values) {
      if (risk.wireName == value) return risk;
    }
    return null;
  }
}

/// 动作执行状态机：
/// prepared -> pendingConfirm -> running -> succeeded/failed/stale/conflict。
///
/// prepared 只表示「校验通过」，dangerous 动作会进入 pendingConfirm；
/// 只有 running 之后才可能产生副作用，因此幂等键在 running 之前建立。
enum ResultActionStatus {
  prepared('prepared', '已准备'),
  pendingConfirm('pending_confirm', '待确认'),
  running('running', '执行中'),
  succeeded('succeeded', '已成功'),
  failed('failed', '已失败'),
  stale('stale', '资源已失效'),
  conflict('conflict', '资源已变化');

  const ResultActionStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  /// 终态不再重新执行，重复点击直接返回既有结果。
  bool get isTerminal =>
      this == succeeded || this == failed || this == stale || this == conflict;

  static ResultActionStatus? fromWire(String value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    return null;
  }
}

/// 动作失败原因。界面据此显示冲突/刷新/无权限等不同提示，而不是统一报「失败」。
enum ResultActionErrorCode {
  unsupported('unsupported', '动作类型未注册'),
  unauthorized('unauthorized', '权限不足或审批过期'),
  stale('stale', '资源已失效'),
  conflict('conflict', '资源已被修改'),
  unknown('unknown', '执行失败');

  const ResultActionErrorCode(this.wireName, this.message);

  final String wireName;

  /// 面向用户的中文原因，界面可直接展示。
  final String message;

  static ResultActionErrorCode? fromWire(String value) {
    for (final code in values) {
      if (code.wireName == value) return code;
    }
    return null;
  }
}

/// 一条已注册动作的静态声明。
///
/// [actionType] 是稳定协议键，[executorKey] 交给真实执行适配器分发；
/// 两者分开是为了让同一动作类型在不同平台有不同的执行实现。
class ResultActionSpec {
  const ResultActionSpec({
    required this.actionType,
    required this.kind,
    required this.label,
    required this.risk,
    required this.requiresConfirmation,
    required this.executorKey,
    required this.successMessage,
    this.description = '',
    this.failureMessage = '操作未完成，请稍后重试',
  });

  /// 协议中的动作类型，例如 reminder.cancel。
  final String actionType;

  /// 该动作所属的卡片类型。
  final ResultCardKind kind;

  /// 按钮文案（中文）。
  final String label;

  /// 动作说明，用于详情页解释会发生的副作用。
  final String description;

  final ResultActionRisk risk;

  /// 是否必须经过确认（统一审批）才能执行。
  ///
  /// 由声明决定而不是 `risk == high` 推断：例如「系统分享」是中风险但仍需确认，
  /// 而某些低风险打开动作不需要确认。
  final bool requiresConfirmation;

  /// 真实执行器的分发键。
  final String executorKey;

  final String successMessage;
  final String failureMessage;

  /// 高风险动作在界面上需要额外的警示样式。
  bool get isDangerous => risk == ResultActionRisk.high;
}

/// 已注册动作白名单。
///
/// const map 保证运行时不可被模型/界面改写；未知 actionType 查不到即拒绝。
abstract final class ResultActionRegistry {
  static const Map<String, ResultActionSpec> all = {
    'reminder.reschedule': ResultActionSpec(
      actionType: 'reminder.reschedule',
      kind: ResultCardKind.reminder,
      label: '改期提醒',
      description: '把提醒改到新的时间；需要重新读取提醒本身的版本。',
      risk: ResultActionRisk.medium,
      requiresConfirmation: true,
      executorKey: 'reminder.reschedule',
      successMessage: '提醒已改期',
    ),
    'reminder.cancel': ResultActionSpec(
      actionType: 'reminder.cancel',
      kind: ResultCardKind.reminder,
      label: '取消提醒',
      description: '取消后提醒不再触发；该动作不可自动撤销。',
      risk: ResultActionRisk.high,
      requiresConfirmation: true,
      executorKey: 'reminder.cancel',
      successMessage: '提醒已取消',
    ),
    'calendar.adjust': ResultActionSpec(
      actionType: 'calendar.adjust',
      kind: ResultCardKind.calendar,
      label: '调整日程',
      description: '调整日程起止时间，需要重新读取日历事件版本。',
      risk: ResultActionRisk.medium,
      requiresConfirmation: true,
      executorKey: 'calendar.adjust',
      successMessage: '日程已调整',
    ),
    'file.preview': ResultActionSpec(
      actionType: 'file.preview',
      kind: ResultCardKind.file,
      label: '预览文件',
      description: '只读预览，不修改文件内容。',
      risk: ResultActionRisk.low,
      requiresConfirmation: false,
      executorKey: 'file.preview',
      successMessage: '文件预览已打开',
    ),
    'file.share': ResultActionSpec(
      actionType: 'file.share',
      kind: ResultCardKind.file,
      label: '分享文件',
      description: '把文件交给系统分享；接收方是否保存不由本机保证。',
      risk: ResultActionRisk.medium,
      requiresConfirmation: true,
      executorKey: 'file.share',
      successMessage: '已交给系统分享',
    ),
    'route.open': ResultActionSpec(
      actionType: 'route.open',
      kind: ResultCardKind.route,
      label: '打开路线',
      description: '在系统地图中打开路线，不写入任何业务数据。',
      risk: ResultActionRisk.low,
      requiresConfirmation: false,
      executorKey: 'route.open',
      successMessage: '已请求打开路线',
    ),
    'workflow.trial_run': ResultActionSpec(
      actionType: 'workflow.trial_run',
      kind: ResultCardKind.workflowTrial,
      label: '试运行工作流',
      description: '按试运行模式执行一次，不发布正式版本。',
      risk: ResultActionRisk.medium,
      requiresConfirmation: true,
      executorKey: 'workflow.trial_run',
      successMessage: '工作流试运行已完成',
    ),
    'diff.review': ResultActionSpec(
      actionType: 'diff.review',
      kind: ResultCardKind.codeDiff,
      label: '查看差异',
      description: '只读查看代码差异，不写入工作区。',
      risk: ResultActionRisk.low,
      requiresConfirmation: false,
      executorKey: 'diff.review',
      successMessage: '已打开差异预览',
    ),
    'diff.restore': ResultActionSpec(
      actionType: 'diff.restore',
      kind: ResultCardKind.codeDiff,
      label: '恢复文件',
      description: '把文件恢复到该版本；会覆盖当前工作区内容。',
      risk: ResultActionRisk.high,
      requiresConfirmation: true,
      executorKey: 'diff.restore',
      successMessage: '文件已恢复',
    ),
  };

  /// 查不到返回 null，调用方必须按 unsupported 处理。
  static ResultActionSpec? find(String actionType) => all[actionType];

  /// 某类卡片可用的动作；界面不要自己拼按钮。
  static List<ResultActionSpec> forKind(ResultCardKind kind) => [
        for (final spec in all.values)
          if (spec.kind == kind) spec
      ];

  /// 已注册动作类型清单（只读视图）。
  static Iterable<String> get actionTypes => all.keys;

  /// 是否注册了指定动作类型。
  static bool supports(String actionType) => all.containsKey(actionType);
}

/// 结构化结果卡。
///
/// [snapshot] 只是展示用的历史快照，不能作为执行依据；执行前必须按
/// resourceType/resourceId 重新读取资源并通过 [resourceVersion] 比对。
class ResultCard {
  const ResultCard({
    required this.id,
    required this.kind,
    required this.resourceType,
    required this.resourceId,
    required this.resourceVersion,
    required this.title,
    required this.summary,
    this.snapshot = const <String, dynamic>{},
    this.status = ResultCardStatus.active,
    this.revision = 1,
    this.taskId = '',
    this.turnId = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ResultCardKind kind;

  /// 真实资源类型，例如 reminder / calendar_event / artifact / route / workflow / workspace_file。
  final String resourceType;

  /// 真实资源 ID。
  final String resourceId;

  /// 生成卡片时读取到的资源版本；执行前必须与最新版本比对。
  final int resourceVersion;

  final String title;
  final String summary;

  /// 展示快照，允许为空；不得包含命令或可执行脚本。
  final Map<String, dynamic> snapshot;

  final ResultCardStatus status;

  /// 卡片自身的修订号，用于检测「列表页看到的卡片」和「数据库里的卡片」不一致。
  final int revision;

  /// 关联任务，用于「返回任务」入口；为空表示该卡片没有任务归属。
  final String taskId;

  /// 关联会话轮次，便于回到具体对话。
  final String turnId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isResourceExpired => status == ResultCardStatus.expired;
  bool get isResourceChanged => status == ResultCardStatus.changed;
  bool get isResourceUnavailable => status == ResultCardStatus.unavailable;

  /// 是否引用了完整、可定位的真实资源。
  bool get referencesRealResource =>
      resourceType.trim().isNotEmpty &&
      resourceId.trim().isNotEmpty &&
      resourceVersion > 0;

  /// 渲染/执行前必须满足的元数据。返回空列表表示可安全渲染。
  List<String> validationIssues() {
    final issues = <String>[];
    if (id.trim().isEmpty) issues.add('缺少卡片 ID');
    if (resourceType.trim().isEmpty) issues.add('缺少资源类型');
    if (resourceId.trim().isEmpty) issues.add('缺少资源 ID');
    if (resourceVersion <= 0) issues.add('资源版本不合法');
    if (title.trim().isEmpty) issues.add('缺少标题');
    if (summary.trim().isEmpty) issues.add('缺少摘要');
    if (revision <= 0) issues.add('卡片修订号不合法');
    if (taskId.trim().isEmpty) issues.add('缺少关联任务');
    return issues;
  }

  /// 只用于刷新卡片状态：资源版本与真实资源 ID 不允许被客户端改写。
  ResultCard copyWith({
    ResultCardStatus? status,
    int? revision,
    Map<String, dynamic>? snapshot,
    DateTime? updatedAt,
  }) =>
      ResultCard(
        id: id,
        kind: kind,
        resourceType: resourceType,
        resourceId: resourceId,
        resourceVersion: resourceVersion,
        title: title,
        summary: summary,
        snapshot: snapshot ?? this.snapshot,
        status: status ?? this.status,
        revision: revision ?? this.revision,
        taskId: taskId,
        turnId: turnId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireName,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'resourceVersion': resourceVersion,
        'title': title,
        'summary': summary,
        'snapshot': snapshot,
        'status': status.wireName,
        'revision': revision,
        'taskId': taskId,
        'turnId': turnId,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  /// 反序列化时对未知类型/状态直接抛错：宁可显示「数据损坏」，
  /// 也不猜测一个可操作状态去执行。
  factory ResultCard.fromJson(Map<String, dynamic> json) {
    final kind = ResultCardKind.fromWire(_string(json['kind']));
    if (kind == null) {
      throw ArgumentError('未知结果卡类型：${json['kind']}');
    }
    final status = ResultCardStatus.fromWire(_string(json['status'])) ??
        ResultCardStatus.unknown;
    final snapshot = json['snapshot'];
    return ResultCard(
      id: _string(json['id']),
      kind: kind,
      resourceType: _string(json['resourceType']),
      resourceId: _string(json['resourceId']),
      resourceVersion: _int(json['resourceVersion']),
      title: _string(json['title']),
      summary: _string(json['summary']),
      snapshot: snapshot is Map
          ? Map<String, dynamic>.from(snapshot)
          : const <String, dynamic>{},
      status: status,
      revision: _int(json['revision'], fallback: 1),
      taskId: _string(json['taskId']),
      turnId: _string(json['turnId']),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static int _int(Object? value, {int fallback = 0}) =>
      value is num ? value.toInt() : fallback;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// 一次动作执行的历史记录（含幂等键与审批信息）。
class ResultActionRecord {
  const ResultActionRecord({
    required this.id,
    required this.cardId,
    required this.cardRevision,
    required this.actionType,
    required this.status,
    required this.idempotencyKey,
    required this.risk,
    this.approvalId,
    this.approvalExpiresAt,
    this.errorCode,
    this.message = '',
    this.result = const <String, dynamic>{},
    this.attempts = 0,
    this.revision = 1,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String cardId;

  /// 准备动作时卡片看到的修订号；执行时若数据库中的卡片修订号更大，
  /// 说明期间被其他设备/页面更新过，必须走冲突路径。
  final int cardRevision;

  final String actionType;
  final ResultActionStatus status;

  /// 幂等键：同一个键最多产生一次真实执行。
  final String idempotencyKey;

  final ResultActionRisk risk;

  /// 统一审批通过后的审批 ID，为空表示尚未确认。
  final String? approvalId;

  /// 审批有效期；执行时必须仍在有效期内。
  final DateTime? approvalExpiresAt;

  final ResultActionErrorCode? errorCode;

  /// 面向用户的中文反馈。
  final String message;

  /// 执行器返回的结构化结果（JSON-safe）。
  final Map<String, dynamic> result;

  /// 真实调用执行器的次数；与界面点击次数解耦，专门用于证明幂等。
  final int attempts;

  /// 记录修订号，每次状态变化 +1。
  final int revision;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isTerminal => status.isTerminal;

  /// 历史上是否真正调用过执行器。
  bool get everExecuted => attempts > 0;

  bool isApprovalExpiredAt(DateTime now) =>
      approvalExpiresAt != null && !approvalExpiresAt!.isAfter(now);

  ResultActionRecord copyWith({
    ResultActionStatus? status,
    ResultActionErrorCode? errorCode,
    String? message,
    String? approvalId,
    DateTime? approvalExpiresAt,
    Map<String, dynamic>? result,
    int? attempts,
    int? revision,
    DateTime? updatedAt,
  }) =>
      ResultActionRecord(
        id: id,
        cardId: cardId,
        cardRevision: cardRevision,
        actionType: actionType,
        status: status ?? this.status,
        idempotencyKey: idempotencyKey,
        risk: risk,
        approvalId: approvalId ?? this.approvalId,
        approvalExpiresAt: approvalExpiresAt ?? this.approvalExpiresAt,
        // 成功路径不需要清除错误码：记录一旦失败就进入终态，不会再次成功。
        errorCode: errorCode ?? this.errorCode,
        message: message ?? this.message,
        result: result ?? this.result,
        attempts: attempts ?? this.attempts,
        revision: revision ?? this.revision,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cardId': cardId,
        'cardRevision': cardRevision,
        'actionType': actionType,
        'status': status.wireName,
        'idempotencyKey': idempotencyKey,
        'risk': risk.wireName,
        'approvalId': approvalId,
        'approvalExpiresAt': approvalExpiresAt?.toUtc().toIso8601String(),
        'errorCode': errorCode?.wireName,
        'message': message,
        'result': result,
        'attempts': attempts,
        'revision': revision,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  factory ResultActionRecord.fromJson(Map<String, dynamic> json) {
    final actionType = ResultCard._string(json['actionType']);
    final status =
        ResultActionStatus.fromWire(ResultCard._string(json['status']));
    final risk = ResultActionRisk.fromWire(ResultCard._string(json['risk']));
    if (status == null || risk == null) {
      throw ArgumentError('结果卡动作记录损坏：$actionType');
    }
    final result = json['result'];
    return ResultActionRecord(
      id: ResultCard._string(json['id']),
      cardId: ResultCard._string(json['cardId']),
      cardRevision: ResultCard._int(json['cardRevision']),
      actionType: actionType,
      status: status,
      idempotencyKey: ResultCard._string(json['idempotencyKey']),
      risk: risk,
      approvalId:
          json['approvalId'] is String ? json['approvalId'] as String : null,
      approvalExpiresAt: ResultCard._date(json['approvalExpiresAt']),
      errorCode:
          ResultActionErrorCode.fromWire(ResultCard._string(json['errorCode'])),
      message: ResultCard._string(json['message']),
      result: result is Map
          ? Map<String, dynamic>.from(result)
          : const <String, dynamic>{},
      attempts: ResultCard._int(json['attempts']),
      revision: ResultCard._int(json['revision'], fallback: 1),
      createdAt: ResultCard._date(json['createdAt']),
      updatedAt: ResultCard._date(json['updatedAt']),
    );
  }
}

/// 统一审批结果。
///
/// 它只证明「某个审批已对某卡片某动作放行」，执行前仍要检查过期时间与卡片状态。
class ResultActionApproval {
  const ResultActionApproval({
    required this.approvalId,
    required this.cardId,
    required this.actionType,
    required this.grantedAt,
    required this.expiresAt,
  });

  final String approvalId;
  final String cardId;
  final String actionType;
  final DateTime grantedAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  /// 审批是否覆盖指定卡片的指定动作。
  bool covers({required String cardId, required String actionType}) =>
      approvalId.trim().isNotEmpty &&
      this.cardId == cardId &&
      this.actionType == actionType;
}

/// 重新读取到的资源快照。
///
/// [exists] 为 false 或 [status] 为 unavailable/expired/changed 时，
/// 服务必须拒绝执行，而不是依赖卡片里的旧状态。
class ResultResourceSnapshot {
  const ResultResourceSnapshot({
    required this.resourceType,
    required this.resourceId,
    required this.version,
    this.exists = true,
    this.status = ResultCardStatus.active,
    this.expiresAt,
  });

  final String resourceType;
  final String resourceId;
  final int version;
  final bool exists;
  final ResultCardStatus status;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);
}
