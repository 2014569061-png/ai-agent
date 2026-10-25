import '../application/result_action_service.dart';
import '../domain/result_card.dart';
import '../infrastructure/database/result_action_store.dart';
import '../presentation/chat/widgets/result_card_view.dart';

/// 结果卡与动作服务的离线检查。
///
/// 全部使用内存 fake（仓储/资源读取器/权限检查器/执行器），不写真实数据库、
/// 不访问网络、不调用模型、不产生系统 Intent 等副作用；合同报告据此断言
/// `fixtureOnly=true`、`modelCalls=0`、`persistentDataMutations=0`。
Future<List<Map<String, dynamic>>> runResultCardChecks() async {
  final cases = <Map<String, dynamic>>[];

  Future<void> check(String name, Future<bool> Function() run) async {
    try {
      cases.add({'name': name, 'passed': await run()});
    } catch (error) {
      cases.add({
        'name': name,
        'passed': false,
        'error': error.runtimeType.toString(),
      });
    }
  }

  await check('未知动作类型在准备阶段被拒绝（unsupported）', () async {
    final card = _card();
    final h = _Harness(card);
    final run = await h.service.prepare(card, 'model.freeform_command');
    final saved = await h.repository.listActions(card.id);
    return run.error == ResultActionErrorCode.unsupported &&
        run.action == null &&
        saved.isEmpty &&
        h.executor.calls == 0;
  });

  await check('模型伪造的命令按钮无法进入执行器', () async {
    const forged = [
      'shell.exec',
      'reminder.delete_all',
      'calendar.overwrite',
      '../../../etc/passwd',
    ];
    final noneRegistered =
        forged.every((type) => !ResultActionRegistry.supports(type));
    final h = _Harness(_card());
    final run = await h.service.prepare(h.card, forged.first);
    final saved = await h.repository.listActions(h.card.id);
    return noneRegistered &&
        run.error == ResultActionErrorCode.unsupported &&
        h.executor.calls == 0 &&
        saved.isEmpty;
  });

  await check('资源被删除后执行返回 stale 并保留失效终态', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'file.preview');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    h.resources.deleted = true;
    final run = await h.service.execute(actionId);
    return prepared.action?.status == ResultActionStatus.prepared &&
        run.error == ResultActionErrorCode.stale &&
        run.action?.status == ResultActionStatus.stale &&
        !run.executed &&
        h.executor.calls == 0;
  });

  await check('资源版本不一致时返回 conflict 且不落动作记录', () async {
    final card = _card(kind: ResultCardKind.file, resourceVersion: 1);
    final h = _Harness(card, resourceVersion: 2);
    final run = await h.service.prepare(card, 'file.preview');
    final saved = await h.repository.listActions(card.id);
    return run.error == ResultActionErrorCode.conflict &&
        run.feedback.contains('v1') &&
        run.feedback.contains('v2') &&
        saved.isEmpty;
  });

  await check('快速重复点击共享同一个执行，执行器只被调用一次', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'file.preview');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    final results = await Future.wait([
      h.service.execute(actionId),
      h.service.execute(actionId),
      h.service.execute(actionId),
    ]);
    final stored = await h.repository.findAction(actionId);
    return h.executor.calls == 1 &&
        results.where((run) => run.succeeded).isNotEmpty &&
        results.every((run) => run.action?.id == actionId) &&
        stored?.status == ResultActionStatus.succeeded;
  });

  await check('权限撤销后返回 unauthorized 且不调用执行器', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'file.preview');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    h.permissions.allowed = false;
    final run = await h.service.execute(actionId);
    return run.error == ResultActionErrorCode.unauthorized &&
        run.action?.status == ResultActionStatus.failed &&
        !run.succeeded &&
        h.executor.calls == 0;
  });

  await check('危险动作未确认时不得执行', () async {
    final card = _card(kind: ResultCardKind.reminder);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'reminder.cancel');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    final run = await h.service.execute(actionId);
    return prepared.pendingConfirmation &&
        run.status == ResultActionStatus.pendingConfirm &&
        run.error == null &&
        run.feedback.contains('需要确认') &&
        h.executor.calls == 0;
  });

  await check('过期审批被拒绝并落失败终态', () async {
    final card = _card(kind: ResultCardKind.reminder);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'reminder.cancel');
    final action = prepared.action;
    if (action == null) return false;
    final expired = ResultActionApproval(
      approvalId: 'approval-expired',
      cardId: card.id,
      actionType: action.actionType,
      grantedAt: h.now.subtract(const Duration(minutes: 10)),
      expiresAt: h.now.subtract(const Duration(minutes: 5)),
    );
    final confirmed = await h.service.confirm(action.id, expired);
    final executed = await h.service.execute(action.id);
    return confirmed.error == ResultActionErrorCode.unauthorized &&
        confirmed.action?.status == ResultActionStatus.failed &&
        executed.status == ResultActionStatus.failed &&
        !executed.succeeded &&
        h.executor.calls == 0;
  });

  await check('prepared→pending_confirm→succeeded 全链路', () async {
    final card = _card(kind: ResultCardKind.reminder);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'reminder.reschedule');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    if (!prepared.pendingConfirmation) return false;
    final approval = _approvalFor(h, prepared.action!);
    final confirmed = await h.service.confirm(actionId, approval);
    final executed = await h.service.execute(actionId);
    return confirmed.action?.status == ResultActionStatus.pendingConfirm &&
        confirmed.action?.approvalId == approval.approvalId &&
        executed.succeeded &&
        executed.executed &&
        executed.action?.attempts == 1 &&
        executed.action?.cardId == card.id &&
        h.executor.calls == 1;
  });

  await check('执行器失败时保留失败状态且不伪造成功', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    h.executor.shouldFail = true;
    final prepared = await h.service.prepare(card, 'file.preview');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    final run = await h.service.execute(actionId);
    final stored = await h.repository.findAction(actionId);
    return !run.succeeded &&
        run.status == ResultActionStatus.failed &&
        run.error == ResultActionErrorCode.unknown &&
        stored?.status == ResultActionStatus.failed &&
        stored?.errorCode == ResultActionErrorCode.unknown &&
        h.executor.calls == 1;
  });

  await check('执行器抛错被转换为失败而不是成功', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    h.executor.shouldThrow = true;
    final prepared = await h.service.prepare(card, 'file.preview');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    final run = await h.service.execute(actionId);
    final stored = await h.repository.findAction(actionId);
    return !run.succeeded &&
        run.status == ResultActionStatus.failed &&
        run.feedback.contains('未产生成功结果') &&
        stored?.status == ResultActionStatus.failed &&
        h.executor.calls == 1;
  });

  await check('六类卡片元数据齐全且组件可构造', () async {
    if (ResultCardKind.values.length != 6) return false;
    for (final kind in ResultCardKind.values) {
      final card = _card(id: 'card-${kind.wireName}', kind: kind);
      if (card.validationIssues().isNotEmpty) return false;
      final specs = ResultActionRegistry.forKind(kind);
      if (specs.isEmpty) return false;
      if (specs.any((spec) => spec.kind != kind)) return false;
      final view = ResultCardView(card: card, actions: specs);
      if (view.card.id != card.id) return false;
      if (view.actions?.length != specs.length) return false;
    }
    // 高风险动作必须由注册表声明「需要确认」，不能靠调用方临时传参。
    final dangerous =
        ResultActionRegistry.all.values.where((spec) => spec.isDangerous);
    return dangerous.isNotEmpty &&
        dangerous.every((spec) => spec.requiresConfirmation);
  });

  await check('准备后跨设备更新触发 conflict 并要求刷新', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'file.preview');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    // 模拟另一台设备同步后卡片被更新：修订号变化、状态变为 changed。
    h.repository.cards[card.id] =
        card.copyWith(revision: 2, status: ResultCardStatus.changed);
    final run = await h.service.execute(actionId);
    return run.error == ResultActionErrorCode.conflict &&
        run.action?.status == ResultActionStatus.conflict &&
        run.feedback.contains('其他设备') &&
        h.executor.calls == 0;
  });

  await check('刷新检测到跨设备资源变化并提升卡片修订号', () async {
    final card = _card(kind: ResultCardKind.file, resourceVersion: 1);
    final h = _Harness(card);
    h.resources.version = 2;
    final refreshed = await h.service.refresh(card.id);
    return refreshed != null &&
        refreshed.status == ResultCardStatus.changed &&
        refreshed.revision == card.revision + 1 &&
        refreshed.resourceVersion == card.resourceVersion;
  });

  await check('重试幂等：成功后再次准备/执行返回既有结果', () async {
    final card = _card(kind: ResultCardKind.file);
    final h = _Harness(card);
    final first = await h.service.prepare(card, 'file.preview');
    final firstId = first.action?.id;
    if (firstId == null) return false;
    final executed = await h.service.execute(firstId);
    final retried = await h.service.prepare(card, 'file.preview');
    final replayed = await h.service.execute(firstId);
    final actions = await h.repository.listActions(card.id);
    return executed.succeeded &&
        retried.action?.id == firstId &&
        retried.action?.status == ResultActionStatus.succeeded &&
        replayed.succeeded &&
        !replayed.executed &&
        actions.length == 1 &&
        h.executor.calls == 1;
  });

  await check('卡片引用真实 resourceId 与版本，缺资源引用时拒绝执行', () async {
    final card = _card(
      kind: ResultCardKind.workflowTrial,
      resourceType: 'workflow',
      resourceId: 'workflow-42',
      resourceVersion: 7,
    );
    final h = _Harness(card);
    final prepared = await h.service.prepare(card, 'workflow.trial_run');
    final action = prepared.action;
    final weak = _card(
      kind: ResultCardKind.workflowTrial,
      resourceId: '',
      resourceVersion: 0,
    );
    final weakRun = await h.service.prepare(weak, 'workflow.trial_run');
    return card.referencesRealResource &&
        weak.validationIssues().isNotEmpty &&
        prepared.pendingConfirmation &&
        action != null &&
        action.cardRevision == card.revision &&
        action.idempotencyKey.contains(card.id) &&
        action.idempotencyKey.contains('v7') &&
        weakRun.error == ResultActionErrorCode.stale;
  });

  await check('没有执行器时记录失败而不伪造成功', () async {
    final card = _card(kind: ResultCardKind.route);
    final h = _Harness(card, withExecutor: false);
    final prepared = await h.service.prepare(card, 'route.open');
    final actionId = prepared.action?.id;
    if (actionId == null) return false;
    final run = await h.service.execute(actionId);
    return prepared.action?.status == ResultActionStatus.prepared &&
        run.error == ResultActionErrorCode.unknown &&
        run.action?.status == ResultActionStatus.failed &&
        !run.succeeded &&
        run.feedback.contains('不会伪造成功');
  });

  return cases;
}

/// 测试用结果卡。默认引用一个真实形态的资源，避免用演示数据绕过校验。
ResultCard _card({
  String id = 'card-1',
  ResultCardKind kind = ResultCardKind.reminder,
  String? resourceType,
  String resourceId = 'resource-1',
  int resourceVersion = 1,
  int revision = 1,
  ResultCardStatus status = ResultCardStatus.active,
  String taskId = 'task-1',
  String title = '测试结果卡',
  String summary = '用于离线校验的结果卡',
}) =>
    ResultCard(
      id: id,
      kind: kind,
      resourceType: resourceType ?? _resourceTypeOf(kind),
      resourceId: resourceId,
      resourceVersion: resourceVersion,
      title: title,
      summary: summary,
      status: status,
      revision: revision,
      taskId: taskId,
      createdAt: DateTime.utc(2026, 10, 18),
      updatedAt: DateTime.utc(2026, 10, 18),
    );

String _resourceTypeOf(ResultCardKind kind) => switch (kind) {
      ResultCardKind.reminder => 'reminder',
      ResultCardKind.calendar => 'calendar_event',
      ResultCardKind.file => 'artifact',
      ResultCardKind.route => 'route',
      ResultCardKind.workflowTrial => 'workflow',
      ResultCardKind.codeDiff => 'workspace_file',
    };

ResultActionApproval _approvalFor(
        _Harness harness, ResultActionRecord action) =>
    ResultActionApproval(
      approvalId: 'approval-${action.id}',
      cardId: action.cardId,
      actionType: action.actionType,
      grantedAt: harness.now,
      expiresAt: harness.now.add(ResultActionService.approvalValidity),
    );

/// 一次检查用的完整装配：内存仓储 + 假资源/权限/执行器 + 固定时钟。
///
/// 固定时钟让审批过期与资源过期这类时间语义可重复，不依赖真实时间。
class _Harness {
  _Harness(
    this.card, {
    int? resourceVersion,
    this.withExecutor = true,
  })  : repository = _FixtureRepository([card]),
        resources = _FixtureResources(
          resourceType: card.resourceType,
          resourceId: card.resourceId,
          version: resourceVersion ?? card.resourceVersion,
        );

  final ResultCard card;
  final bool withExecutor;
  final _FixtureRepository repository;
  final _FixtureResources resources;
  final _FixturePermissions permissions = _FixturePermissions();
  final _FixtureExecutor executor = _FixtureExecutor();

  /// 时间基准固定，避免检查在跨时区/跨天时抖动。
  DateTime now = DateTime.utc(2026, 10, 18, 12);

  late final ResultActionService service = ResultActionService(
    repository: repository,
    resources: resources,
    permissions: permissions,
    executor: withExecutor ? executor : null,
    now: () => now,
  );
}

class _FixtureRepository implements ResultActionRepository {
  _FixtureRepository(Iterable<ResultCard> seed) {
    for (final card in seed) {
      cards[card.id] = card;
    }
  }

  final cards = <String, ResultCard>{};
  final actions = <String, ResultActionRecord>{};

  @override
  Future<ResultCard?> findCard(String cardId) async => cards[cardId];

  @override
  Future<List<ResultCard>> listCards({
    ResultCardKind? kind,
    int limit = 50,
  }) async =>
      [
        for (final card in cards.values)
          if (kind == null || card.kind == kind) card,
      ].take(limit).toList(growable: false);

  @override
  Future<void> saveCard(ResultCard card) async {
    cards[card.id] = card;
  }

  @override
  Future<ResultActionRecord?> findAction(String actionId) async =>
      actions[actionId];

  @override
  Future<ResultActionRecord?> findActionByIdempotencyKey(String key) async {
    for (final action in actions.values) {
      if (action.idempotencyKey == key) return action;
    }
    return null;
  }

  @override
  Future<List<ResultActionRecord>> listActions(String cardId) async => [
        for (final action in actions.values)
          if (action.cardId == cardId) action,
      ];

  @override
  Future<void> saveAction(ResultActionRecord action) async {
    actions[action.id] = action;
  }
}

class _FixtureResources implements ResultResourceReader {
  _FixtureResources({
    required this.resourceType,
    required this.resourceId,
    this.version = 1,
  });

  final String resourceType;
  final String resourceId;
  int version;
  bool deleted = false;

  @override
  Future<ResultResourceSnapshot?> read({
    required String resourceType,
    required String resourceId,
  }) async {
    if (deleted) return null;
    return ResultResourceSnapshot(
      resourceType: this.resourceType,
      resourceId: this.resourceId,
      version: version,
    );
  }
}

class _FixturePermissions implements ResultPermissionChecker {
  bool allowed = true;

  @override
  Future<bool> canPerform(ResultActionSpec spec, ResultCard card) async =>
      allowed;
}

class _FixtureExecutor implements ResultActionExecutor {
  int calls = 0;
  bool shouldFail = false;
  bool shouldThrow = false;
  final requests = <ResultActionExecutionRequest>[];

  @override
  Future<ResultActionExecutionResult> execute(
    ResultActionExecutionRequest request,
  ) async {
    calls++;
    requests.add(request);
    // 让并发点击有机会重叠，以验证服务层共享同一 Future 的能力。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (shouldThrow) throw StateError('fixture executor failure');
    if (shouldFail) {
      return const ResultActionExecutionResult.failed(message: 'fixture 执行失败');
    }
    return const ResultActionExecutionResult.succeeded(message: 'fixture 执行成功');
  }
}
