import '../domain/result_card.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/result_action_store.dart';
import '../infrastructure/database/result_action_approval_store.dart';

/// 重新读取真实资源的端口。
///
/// 卡片页只能拿到资源当前版本/存在性，不能信任卡片生成时的快照。
abstract interface class ResultResourceReader {
  Future<ResultResourceSnapshot?> read({
    required String resourceType,
    required String resourceId,
  });
}

/// 权限检查端口。执行前必须重新询问，不能缓存卡片生成时的权限结论。
abstract interface class ResultPermissionChecker {
  Future<bool> canPerform(ResultActionSpec spec, ResultCard card);
}

/// 交给真实执行器的请求。
///
/// 这里只给 actionType/executorKey/card，不携带模型生成的任意命令；
/// 执行器按已注册的 executorKey 分发，未注册类型根本到不了这里。
class ResultActionExecutionRequest {
  const ResultActionExecutionRequest({
    required this.idempotencyKey,
    required this.executorKey,
    required this.actionType,
    required this.card,
    this.canContinue,
  });

  final String idempotencyKey;
  final String executorKey;
  final String actionType;
  final ResultCard card;
  final Future<bool> Function()? canContinue;
}

/// 执行器结果。只有 ok 为 true 才会被记为成功。
class ResultActionExecutionResult {
  const ResultActionExecutionResult.succeeded({
    this.message = '',
    this.result = const <String, dynamic>{},
  }) : ok = true;

  const ResultActionExecutionResult.failed({
    required this.message,
    this.result = const <String, dynamic>{},
  }) : ok = false;

  final bool ok;
  final String message;
  final Map<String, dynamic> result;
}

/// 真实副作用执行端口。
///
/// 应用层不直接写 Intent、不直接调平台能力；实现由设备/任务适配器注入，
/// 这样 debug 合同检查可以断言执行次数而不产生真实副作用。
abstract interface class ResultActionExecutor {
  Future<ResultActionExecutionResult> execute(
      ResultActionExecutionRequest request);
}

/// 一次 prepare/confirm/execute 的返回。
///
/// [executed] 表示本次调用是否真的调用了执行器；重复点击返回既有结果时为 false，
/// 这是「幂等」的可观察证据。
class ResultActionRun {
  const ResultActionRun({
    this.card,
    this.action,
    this.error,
    this.executed = false,
    this.feedback = '',
  });

  final ResultCard? card;
  final ResultActionRecord? action;
  final ResultActionErrorCode? error;
  final bool executed;
  final String feedback;

  ResultActionStatus get status =>
      action?.status ?? ResultActionStatus.prepared;

  bool get succeeded => status == ResultActionStatus.succeeded;

  bool get pendingConfirmation =>
      status == ResultActionStatus.pendingConfirm &&
      (action?.approvalId ?? '').trim().isEmpty;

  bool get hasError => error != null;
}

/// 结果卡动作服务。
///
/// 职责边界：校验（注册类型/资源版本/权限/审批）与幂等调度在这里，
/// 真实副作用只在注入的 [ResultActionExecutor] 里发生。
class ResultActionService {
  ResultActionService({
    required this.repository,
    required this.resources,
    required this.permissions,
    this.executor,
    ResultActionApprovalVerifier? approvalVerifier,
    DateTime Function()? now,
  })  : approvalVerifier = approvalVerifier ??
            (repository is ConditionalResultActionRepository
                ? ResultActionApprovalStore(repository.db)
                : null),
        _now = now ?? DateTime.now;

  final ResultActionRepository repository;
  final ResultResourceReader resources;
  final ResultPermissionChecker permissions;
  final ResultActionExecutor? executor;
  final ResultActionApprovalVerifier? approvalVerifier;
  final DateTime Function() _now;

  /// 正在进行中的执行。同一动作的并发点击共享同一个 Future，
  /// 因此执行器只会被调用一次。
  final _inFlight = <String, Future<ResultActionRun>>{};

  /// 审批默认有效期，供接线统一审批时参考（审批本身由审批桥签发）。
  static const Duration approvalValidity = Duration(minutes: 5);

  Future<ResultCard?> findCard(String cardId) => repository.findCard(cardId);

  Future<List<ResultCard>> cards({ResultCardKind? kind, int limit = 50}) =>
      repository.listCards(kind: kind, limit: limit);

  Future<ResultActionRecord?> findAction(String actionId) =>
      repository.findAction(actionId);

  Future<List<ResultActionRecord>> actions(String cardId) =>
      repository.listActions(cardId);

  /// 重新读取卡片与资源，更新卡片状态；返回 null 表示卡片已被删除。
  Future<ResultCard?> refresh(String cardId) async {
    final card = await repository.findCard(cardId);
    if (card == null) return null;
    if (!card.referencesRealResource) return card;
    final resource = await resources.read(
        resourceType: card.resourceType, resourceId: card.resourceId);
    final now = _now().toUtc();
    final ResultCardStatus status;
    if (resource == null || !resource.exists) {
      status = ResultCardStatus.unavailable;
    } else if (resource.status == ResultCardStatus.expired ||
        resource.isExpiredAt(now)) {
      status = ResultCardStatus.expired;
    } else if (resource.status == ResultCardStatus.unavailable) {
      status = ResultCardStatus.unavailable;
    } else if (resource.status == ResultCardStatus.changed ||
        resource.version != card.resourceVersion) {
      status = ResultCardStatus.changed;
    } else {
      status = ResultCardStatus.active;
    }
    if (status == card.status) return card;
    final updated = card.copyWith(
        status: status, revision: card.revision + 1, updatedAt: now);
    await repository.saveCard(updated);
    return updated;
  }

  /// 准备动作：校验注册类型 -> 重新读取资源/版本 -> 权限 -> 审批要求。
  ///
  /// 危险动作不会直接执行，只创建 pendingConfirm 记录等待确认。
  Future<ResultActionRun> prepare(
    ResultCard card,
    String actionType, {
    String? idempotencyKey,
  }) async {
    final spec = ResultActionRegistry.find(actionType);
    if (spec == null) {
      return ResultActionRun(
        card: card,
        error: ResultActionErrorCode.unsupported,
        feedback: '该操作类型未注册，已拒绝执行',
      );
    }
    if (spec.kind != card.kind) {
      // 注册表里的动作不允许被挪到别的卡片类型上复用。
      return ResultActionRun(
        card: card,
        error: ResultActionErrorCode.unsupported,
        feedback: '该操作不属于当前卡片类型，已拒绝执行',
      );
    }
    final validation = await _validate(card, spec);
    if (!validation.ok) {
      return ResultActionRun(
        card: validation.card ?? card,
        error: validation.error,
        feedback: validation.message,
      );
    }
    final current = validation.card!;
    final key = _resolveKey(current, actionType, idempotencyKey);
    final existing = await repository.findActionByIdempotencyKey(key);
    if (existing != null) {
      return ResultActionRun(
        card: current,
        action: existing,
        feedback: existing.message.isEmpty
            ? '该操作已有结果，返回既有记录（不会重复执行）'
            : existing.message,
      );
    }
    final now = _now().toUtc();
    final requiresConfirmation = spec.requiresConfirmation;
    final record = ResultActionRecord(
      id: UniqueId.generate('result-action', now: now),
      cardId: current.id,
      cardRevision: current.revision,
      actionType: spec.actionType,
      status: requiresConfirmation
          ? ResultActionStatus.pendingConfirm
          : ResultActionStatus.prepared,
      idempotencyKey: key,
      risk: spec.risk,
      message: requiresConfirmation
          ? '「${spec.label}」需要确认后才能执行'
          : '校验通过，可以执行「${spec.label}」',
      createdAt: now,
      updatedAt: now,
    );
    try {
      await repository.saveAction(record);
    } catch (_) {
      // 幂等键唯一索引冲突说明另一个并发请求已先写入；返回对方记录。
      final raced = await repository.findActionByIdempotencyKey(key);
      if (raced == null) rethrow;
      return ResultActionRun(
        card: current,
        action: raced,
        feedback: '该操作已在处理中，返回既有记录（不会重复执行）',
      );
    }
    return ResultActionRun(
      card: current,
      action: record,
      feedback: record.message,
    );
  }

  /// 记录统一审批结果；审批过期或与动作不匹配时拒绝并落失败终态。
  Future<ResultActionRun> confirm(
      String actionId, ResultActionApproval approval) async {
    final action = await repository.findAction(actionId);
    if (action == null) {
      return const ResultActionRun(
        error: ResultActionErrorCode.unknown,
        feedback: '操作记录不存在，请刷新后重试',
      );
    }
    final card = await repository.findCard(action.cardId);
    final spec = ResultActionRegistry.find(action.actionType);
    if (spec == null) {
      return _persistFailure(
          action, ResultActionErrorCode.unsupported, '该操作类型未注册，已拒绝执行');
    }
    if (action.isTerminal) {
      return _run(action, card: card, feedback: _terminalFeedback(action));
    }
    if (!spec.requiresConfirmation) {
      return _run(action, card: card, feedback: '该操作无需确认，可以直接执行');
    }
    if (action.status != ResultActionStatus.pendingConfirm) {
      return _run(action, card: card, feedback: '当前状态不能确认该操作');
    }
    if ((action.approvalId ?? '').isNotEmpty &&
        action.approvalId != approval.approvalId) {
      return ResultActionRun(
          card: card,
          action: action,
          error: ResultActionErrorCode.conflict,
          feedback: '该操作已绑定其他审批，未覆盖已有决定');
    }
    final now = _now().toUtc();
    if (!approval.covers(
        cardId: action.cardId, actionType: action.actionType)) {
      return _persistFailure(
          action, ResultActionErrorCode.unauthorized, '审批与当前操作不匹配，已拒绝执行');
    }
    if (approval.isExpiredAt(now) || approval.grantedAt.isAfter(now)) {
      return _persistFailure(
          action, ResultActionErrorCode.unauthorized, '审批已过期，请重新发起并确认');
    }
    final verifier = approvalVerifier;
    if (verifier != null &&
        (card == null ||
            !await verifier.verify(
                action: action,
                card: card,
                approvalId: approval.approvalId,
                expiresAt: approval.expiresAt))) {
      return _persistFailure(action, ResultActionErrorCode.unauthorized,
          '没有匹配的有效持久审批，未授权执行；请重新确认');
    }
    if (action.approvalId == approval.approvalId) {
      return _run(action, card: card);
    }
    final updated = action.copyWith(
      approvalId: approval.approvalId,
      approvalExpiresAt: approval.expiresAt,
      message: '已确认，待执行「${spec.label}」',
      revision: action.revision + 1,
      updatedAt: now,
    );
    if (!await _saveTransition(updated, action, expectedCard: card)) {
      return _raced(action.id, card: card);
    }
    return _run(updated, card: card);
  }

  Future<ResultActionRun> rejectPending(String actionId,
      {String message = '审批已拒绝、过期或失效，未执行动作；可重新发起'}) async {
    final action = await repository.findAction(actionId);
    if (action == null) {
      return const ResultActionRun(
          error: ResultActionErrorCode.stale, feedback: '操作已不存在');
    }
    if (action.status != ResultActionStatus.pendingConfirm) return _run(action);
    final card = await repository.findCard(action.cardId);
    if (card == null || card.revision != action.cardRevision) {
      return _persistFailure(
          action,
          card == null
              ? ResultActionErrorCode.stale
              : ResultActionErrorCode.conflict,
          '审批期间资源已变化，旧审批未执行；请刷新',
          card: card);
    }
    return _persistFailure(action, ResultActionErrorCode.unauthorized, message);
  }

  /// 执行动作。
  ///
  /// 同一 actionId 的并发调用复用同一个 Future；终态动作直接返回既有结果。
  /// 执行前会再次读取卡片与资源，任何失败都不会写成 succeeded。
  Future<ResultActionRun> execute(String actionId,
      {bool Function()? canContinue}) {
    final pending = _inFlight[actionId];
    if (pending != null) return pending;
    final future = _execute(actionId, canContinue: canContinue);
    _inFlight[actionId] = future;
    return future.whenComplete(() => _inFlight.remove(actionId));
  }

  Future<ResultActionRun> _execute(String actionId,
      {bool Function()? canContinue}) async {
    final action = await repository.findAction(actionId);
    if (action == null) {
      return const ResultActionRun(
        error: ResultActionErrorCode.unknown,
        feedback: '操作记录不存在，请刷新后重试',
      );
    }
    final spec = ResultActionRegistry.find(action.actionType);
    if (spec == null) {
      return _persistFailure(
          action, ResultActionErrorCode.unsupported, '该操作类型未注册，已拒绝执行');
    }
    if (action.risk != spec.risk) {
      // 注册表声明变化后旧记录不再可信，宁可拒绝也不按旧风险等级执行。
      return _persistFailure(
          action, ResultActionErrorCode.unsupported, '动作声明已变化，请重新发起操作');
    }
    if (action.isTerminal) {
      return _run(action,
          card: await repository.findCard(action.cardId),
          feedback: _terminalFeedback(action));
    }
    final card = await repository.findCard(action.cardId);
    if (card == null) {
      return _persistFailure(
        action,
        ResultActionErrorCode.stale,
        '结果卡已不存在，可能已被删除；请刷新成果中心',
        status: ResultActionStatus.stale,
      );
    }
    if (card.kind != spec.kind) {
      return _persistFailure(
          action, ResultActionErrorCode.unsupported, '卡片类型与动作不匹配，已拒绝执行');
    }
    if (action.status == ResultActionStatus.pendingConfirm &&
        spec.requiresConfirmation) {
      if ((action.approvalId ?? '').trim().isEmpty) {
        return _run(action, card: card, feedback: '「${spec.label}」需要确认后才能执行');
      }
      if (action.isApprovalExpiredAt(_now().toUtc())) {
        return _persistFailure(
            action, ResultActionErrorCode.unauthorized, '审批已过期，请重新发起并确认');
      }
    }
    if (action.status != ResultActionStatus.prepared &&
        action.status != ResultActionStatus.pendingConfirm) {
      return _run(action,
          card: card,
          feedback: action.message.isEmpty ? '当前状态不能执行该操作' : action.message);
    }
    if (action.everExecuted) {
      // 上一次调用已进入执行器但没有落终态（进程中断）：不再重放，
      // 避免用户重复点击造成两次副作用。
      final recovered = action.copyWith(
        status: ResultActionStatus.failed,
        errorCode: ResultActionErrorCode.unknown,
        message: '上一次执行结果未知，已停止重放以避免重复副作用；请重新发起',
        revision: action.revision + 1,
        updatedAt: _now().toUtc(),
      );
      if (!await _saveTransition(recovered, action)) {
        return _raced(action.id, card: card);
      }
      return _run(recovered, card: card, error: ResultActionErrorCode.unknown);
    }
    final validation =
        await _validate(card, spec, expectedCardRevision: action.cardRevision);
    if (!validation.ok) {
      return _persistFailure(
        action,
        validation.error!,
        validation.message,
        status: _statusFor(validation.error!),
        card: validation.card ?? card,
      );
    }
    final current = validation.card!;
    final verifier = approvalVerifier;
    if (spec.requiresConfirmation &&
        verifier != null &&
        (action.approvalExpiresAt == null ||
            !await verifier.verify(
                action: action,
                card: current,
                approvalId: action.approvalId ?? '',
                expiresAt: action.approvalExpiresAt!))) {
      return _persistFailure(action, ResultActionErrorCode.unauthorized,
          '审批已撤回、过期或不属于当前操作，未执行；请重新确认');
    }
    final runner = executor;
    if (runner == null) {
      return _persistFailure(
          action, ResultActionErrorCode.unknown, '没有可用的操作执行器，已停止（不会伪造成功）');
    }
    final now = _now().toUtc();
    final running = action.copyWith(
      status: ResultActionStatus.running,
      attempts: action.attempts + 1,
      message: '正在执行「${spec.label}」',
      revision: action.revision + 1,
      updatedAt: now,
    );
    if (!await _saveTransition(running, action,
        expectedCard: current,
        authorize: spec.requiresConfirmation && verifier != null
            ? () => verifier.verify(
                action: action,
                card: current,
                approvalId: action.approvalId ?? '',
                expiresAt: action.approvalExpiresAt!)
            : null)) {
      return _raced(action.id, card: current);
    }
    try {
      final result = await runner.execute(ResultActionExecutionRequest(
        idempotencyKey: action.idempotencyKey,
        executorKey: spec.executorKey,
        actionType: spec.actionType,
        card: current,
        canContinue: () async {
          final latest = await repository.findAction(action.id);
          final target = await repository.findCard(current.id);
          if (latest == null ||
              target == null ||
              latest.status != ResultActionStatus.running ||
              latest.revision != running.revision ||
              target.revision != current.revision ||
              target.resourceType != current.resourceType ||
              target.resourceId != current.resourceId ||
              target.resourceVersion != current.resourceVersion ||
              target.status != ResultCardStatus.active) {
            return false;
          }
          if (spec.requiresConfirmation &&
              verifier != null &&
              !await verifier.verify(
                  action: latest,
                  card: target,
                  approvalId: latest.approvalId ?? '',
                  expiresAt: latest.approvalExpiresAt!,
                  forExecution: true)) {
            return false;
          }
          return canContinue?.call() ?? true;
        },
      ));
      final message = result.message.trim().isEmpty
          ? (result.ok ? spec.successMessage : spec.failureMessage)
          : result.message.trim();
      if (result.ok) {
        final succeeded = running.copyWith(
          status: ResultActionStatus.succeeded,
          message: message,
          result: result.result,
          revision: running.revision + 1,
          updatedAt: _now().toUtc(),
        );
        if (!await _saveTransition(succeeded, running)) {
          return await _raced(action.id, card: current, executed: true);
        }
        return _run(succeeded, card: current, executed: true);
      }
      final failed = running.copyWith(
        status: ResultActionStatus.failed,
        errorCode: ResultActionErrorCode.unknown,
        message: message,
        result: result.result,
        revision: running.revision + 1,
        updatedAt: _now().toUtc(),
      );
      if (!await _saveTransition(failed, running)) {
        return await _raced(action.id, card: current, executed: true);
      }
      return _run(failed,
          card: current, error: ResultActionErrorCode.unknown, executed: true);
    } catch (error) {
      // 执行器抛错时真实副作用状态未知，只能报告失败，绝不能记成功。
      final failed = running.copyWith(
        status: ResultActionStatus.failed,
        errorCode: ResultActionErrorCode.unknown,
        message: '执行「${spec.label}」失败（${error.runtimeType}），未产生成功结果',
        revision: running.revision + 1,
        updatedAt: _now().toUtc(),
      );
      if (!await _saveTransition(failed, running)) {
        return _raced(action.id, card: current, executed: true);
      }
      return _run(failed,
          card: current, error: ResultActionErrorCode.unknown, executed: true);
    }
  }

  /// 校验卡片与资源。`expectedCardRevision` 用于发现「准备后卡片又被更新」，
  /// 典型来源是其他设备同步或另一个页面刷新。
  Future<_Validation> _validate(
    ResultCard observed,
    ResultActionSpec spec, {
    int? expectedCardRevision,
  }) async {
    final current = await repository.findCard(observed.id);
    if (current == null) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '结果卡已不存在，可能已被删除');
    }
    if (expectedCardRevision != null &&
        current.revision != expectedCardRevision) {
      return const _Validation.fail(
          ResultActionErrorCode.conflict, '结果卡在准备后已被更新（可能来自其他设备），请刷新后重试');
    }
    if (current.revision != observed.revision) {
      return const _Validation.fail(
          ResultActionErrorCode.conflict, '结果卡已更新，请刷新后重试');
    }
    if (current.kind != spec.kind) {
      return const _Validation.fail(
          ResultActionErrorCode.unsupported, '卡片类型与动作不匹配，已拒绝执行');
    }
    if (current.resourceType != observed.resourceType ||
        current.resourceId != observed.resourceId) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '结果卡引用的资源已变化，请刷新后重试');
    }
    if (!current.referencesRealResource) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '结果卡缺少真实资源引用，不能执行操作');
    }
    switch (current.status) {
      case ResultCardStatus.expired:
      case ResultCardStatus.unavailable:
        return const _Validation.fail(
            ResultActionErrorCode.stale, '结果卡资源已失效，请刷新后重试');
      case ResultCardStatus.changed:
        return const _Validation.fail(
            ResultActionErrorCode.conflict, '结果卡资源已被其他设备修改，请刷新后重试');
      case ResultCardStatus.unknown:
        return const _Validation.fail(
            ResultActionErrorCode.stale, '结果卡状态未知，请刷新后重试');
      case ResultCardStatus.active:
        break;
    }
    final resource = await resources.read(
        resourceType: current.resourceType, resourceId: current.resourceId);
    final now = _now().toUtc();
    if (resource == null || !resource.exists) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '资源已删除或不可访问，请刷新后重试');
    }
    if (resource.status == ResultCardStatus.unavailable) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '资源当前不可用，请刷新后重试');
    }
    if (resource.status == ResultCardStatus.expired ||
        resource.isExpiredAt(now)) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '资源已过期，请刷新后重试');
    }
    if (resource.status == ResultCardStatus.changed) {
      return const _Validation.fail(
          ResultActionErrorCode.conflict, '资源已被其他设备修改，请刷新后重试');
    }
    if (resource.resourceType != current.resourceType ||
        resource.resourceId != current.resourceId) {
      return const _Validation.fail(
          ResultActionErrorCode.stale, '重新读取到的资源与卡片不一致，请刷新后重试');
    }
    if (resource.version != current.resourceVersion) {
      return _Validation.fail(
          ResultActionErrorCode.conflict,
          '资源版本已从 v${current.resourceVersion} 变为 v${resource.version}，'
          '可能已被其他设备修改；请刷新后重试');
    }
    final allowed = await permissions.canPerform(spec, current);
    if (!allowed) {
      return _Validation.fail(
          ResultActionErrorCode.unauthorized, '权限已撤销或不足，无法执行「${spec.label}」');
    }
    return _Validation.ok(current);
  }

  String _resolveKey(ResultCard card, String actionType, String? provided) {
    final explicit = provided?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    // 默认键绑定卡片、动作与资源版本：同一资源版本上的同一动作最多执行一次；
    // 资源更新后允许产生新的动作记录。
    return 'result-card:${card.id}:$actionType:v${card.resourceVersion}';
  }

  String _terminalFeedback(ResultActionRecord action) {
    if (action.message.trim().isNotEmpty) return action.message;
    return switch (action.status) {
      ResultActionStatus.succeeded => '该操作已成功，返回既有结果（不会重复执行）',
      ResultActionStatus.failed => '该操作已失败，返回既有结果（不会重复执行）',
      ResultActionStatus.stale => '资源已失效，返回既有结果；请刷新后重新发起',
      ResultActionStatus.conflict => '资源已变化，返回既有结果；请刷新后重新发起',
      _ => '该操作已结束，返回既有结果',
    };
  }

  Future<ResultActionRun> _persistFailure(
    ResultActionRecord action,
    ResultActionErrorCode code,
    String message, {
    ResultActionStatus? status,
    ResultCard? card,
  }) async {
    final updated = action.copyWith(
      status: status ?? _statusFor(code),
      errorCode: code,
      message: message,
      revision: action.revision + 1,
      updatedAt: _now().toUtc(),
    );
    if (!await _saveTransition(updated, action)) {
      return _raced(action.id, card: card);
    }
    return _run(updated, card: card, error: code);
  }

  Future<bool> _saveTransition(
      ResultActionRecord next, ResultActionRecord previous,
      {ResultCard? expectedCard, Future<bool> Function()? authorize}) async {
    final repo = repository;
    if (repo is ConditionalResultActionRepository) {
      return repo.compareAndSaveAction(next,
          expectedRevision: previous.revision,
          expectedCard: expectedCard,
          authorize: authorize);
    }
    if (authorize != null && !await authorize()) return false;
    await repo.saveAction(next);
    return true;
  }

  Future<ResultActionRun> _raced(String actionId,
          {ResultCard? card, bool executed = false}) async =>
      ResultActionRun(
          card: card,
          action: await repository.findAction(actionId),
          error: ResultActionErrorCode.conflict,
          executed: executed,
          feedback: executed
              ? '执行后记录已变化，结果待核实；不会重放或重建已删除的数据'
              : '操作已被其他执行者处理或删除，未重复执行；请刷新');

  ResultActionRun _run(
    ResultActionRecord action, {
    ResultCard? card,
    ResultActionErrorCode? error,
    bool executed = false,
    String? feedback,
  }) =>
      ResultActionRun(
        card: card,
        action: action,
        error: error,
        executed: executed,
        feedback: feedback ?? action.message,
      );

  static ResultActionStatus _statusFor(ResultActionErrorCode code) =>
      switch (code) {
        ResultActionErrorCode.stale => ResultActionStatus.stale,
        ResultActionErrorCode.conflict => ResultActionStatus.conflict,
        _ => ResultActionStatus.failed,
      };
}

/// 校验结果内部载体。
class _Validation {
  const _Validation.ok(ResultCard this.card)
      : error = null,
        message = '';

  const _Validation.fail(ResultActionErrorCode this.error, this.message)
      : card = null;

  final ResultCard? card;
  final ResultActionErrorCode? error;
  final String message;

  bool get ok => error == null;
}
