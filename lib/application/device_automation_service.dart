import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/device_automation.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/android_device_tool.dart';
import 'audit_service.dart';
import 'device_action_runner.dart';
import 'providers.dart';

/// 原生触发器通道（`nexus/device_automation`）。
class DeviceAutomationBridge {
  const DeviceAutomationBridge();

  static const MethodChannel _channel =
      MethodChannel('nexus/device_automation');

  /// 通知被点击时由原生侧调用；在应用启动时注册一次。
  static void listen(void Function(String fireId) onFire) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'automationFired' && call.arguments is String) {
        onFire(call.arguments as String);
      }
      return null;
    });
  }

  Future<void> syncRules(List<AutomationRule> rules) => _channel.invokeMethod(
        'syncRules',
        {'rules': jsonEncode(rules.map((rule) => rule.toJson()).toList())},
      );

  Future<List<AutomationFire>> pendingFires() async {
    final raw = await _channel.invokeMethod<String>('pendingFires');
    final decoded = raw == null ? const [] : jsonDecode(raw);
    return [
      for (final item in decoded is List ? decoded : const [])
        if (AutomationFire.fromJson(item) case final fire?) fire,
    ];
  }

  Future<void> resolveFire(String fireId) =>
      _channel.invokeMethod('resolveFire', {'fireId': fireId});

  Future<String?> consumeLaunchFire() =>
      _channel.invokeMethod<String>('consumeLaunchFire');

  Future<Map<String, dynamic>> triggerStatus() async =>
      await _channel.invokeMapMethod<String, dynamic>('triggerStatus') ??
      const {};

  Future<int> evaluateNow() async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>('evaluateNow');
    return (result?['fired'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> listFolderFiles({
    required String treeUri,
    int? modifiedBeforeMs,
    String? extension,
    int limit = 100,
  }) async =>
      await _channel.invokeMapMethod<String, dynamic>('listFolderFiles', {
        'treeUri': treeUri,
        if (modifiedBeforeMs != null) 'modifiedBeforeMs': modifiedBeforeMs,
        if (extension != null) 'extension': extension,
        'limit': limit,
      }) ??
      const {};
}

/// 原生侧记录的一次待确认触发。
class AutomationFire {
  const AutomationFire({
    required this.fireId,
    required this.ruleId,
    required this.ruleName,
    required this.trigger,
    required this.firedAtMs,
  });

  final String fireId;
  final String ruleId;
  final String ruleName;
  final String trigger;
  final int firedAtMs;

  static AutomationFire? fromJson(Object? json) {
    if (json is! Map) return null;
    final fireId = json['fireId'];
    final ruleId = json['ruleId'];
    if (fireId is! String || ruleId is! String) return null;
    return AutomationFire(
      fireId: fireId,
      ruleId: ruleId,
      ruleName: json['ruleName']?.toString() ?? '',
      trigger: json['trigger']?.toString() ?? '',
      firedAtMs: (json['firedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一次触发（或手动运行）准备好的执行计划：每个动作都已生成预览。
class PreparedAutomation {
  PreparedAutomation({
    required this.rule,
    required this.triggerText,
    required this.actions,
    this.fire,
  });

  final AutomationRule rule;
  final AutomationFire? fire;
  final String triggerText;
  final List<PreparedDeviceAction> actions;

  String get userRequest => '自动化规则「${rule.name}」· $triggerText';
}

/// 设备自动化：规则存储、原生同步、触发确认、执行记录、撤销与审计。
///
/// 规则与执行记录保存在 SharedPreferences（有上限），避免为此做数据库迁移；
/// 所有规则变更和执行都写入审计日志（不受诊断审计开关影响）。
class DeviceAutomationService {
  DeviceAutomationService({
    DeviceActionRunner? runner,
    DeviceAutomationBridge? bridge,
    AuditService? audit,
    Future<AppDatabase> Function()? database,
    DateTime Function()? clock,
    Future<Map<String, dynamic>> Function({bool probeRoot})? privilegeStatus,
  })  : _privilegeStatus = privilegeStatus ??
            (({bool probeRoot = true}) => const AndroidDeviceControlBridge()
                .privilegeStatus(probeRoot: probeRoot)),
        _runner = runner ?? DeviceActionRunner(),
        _bridge = bridge ?? const DeviceAutomationBridge(),
        _audit = audit ?? AuditService(),
        _database = database,
        _clock = clock ?? DateTime.now;

  final DeviceActionRunner _runner;
  final DeviceAutomationBridge _bridge;
  final AuditService _audit;
  final Future<AppDatabase> Function()? _database;
  final DateTime Function() _clock;
  final Future<Map<String, dynamic>> Function({bool probeRoot})
      _privilegeStatus;
  Map<String, dynamic>? _lastPrivilegeStatus;
  DateTime? _lastPrivilegeAt;
  List<AutomationRule>? _rulesCache;

  static const rulesKey = 'device_automation.rules.v1';
  static const runsKey = 'device_automation.runs.v1';
  static const maxRules = 30;
  static const maxRuns = 200;

  static const _settingsActions = {
    'set_wifi',
    'set_bluetooth',
    'set_do_not_disturb',
    'set_auto_rotate',
    'set_brightness',
    'set_volume',
  };

  DeviceActionRunner get runner => _runner;
  DeviceAutomationBridge get bridge => _bridge;

  // -------------------------------------------------------------------------
  // 规则
  // -------------------------------------------------------------------------

  Future<List<AutomationRule>> rules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(rulesKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      final parsed = [
        for (final item in decoded is List ? decoded : const [])
          if (AutomationRule.fromJson(item) case final rule?) rule,
      ];
      _rulesCache = List.unmodifiable(parsed);
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  /// 规则里在当前设备上无法自动完成（只能打开系统页面或部分生效）的动作说明。
  ///
  /// 空列表表示全部动作都能直接执行；无法读取通道状态时返回 null（未知）。
  /// 先不执行 su 读取；只有设备存在 su 但本次运行尚未检查时才探测 Root，
  /// 这时规则本身就包含需要特权的动作，弹出 Root 授权框是预期行为。
  Future<List<String>?> privilegeFallbackWarnings(AutomationRule rule) async {
    if (!_hasFallbackCandidates(rule)) return const [];
    final status = await refreshPrivilegeStatus();
    return status == null ? null : _fallbackWarnings(rule, status);
  }

  /// 读取并缓存执行通道状态；非 Android 或读取失败时返回 null。
  Future<Map<String, dynamic>?> refreshPrivilegeStatus() async {
    try {
      var status = await _privilegeStatus(probeRoot: false);
      final root = status['root'];
      final routes = status['routes'];
      final shell = routes is Map ? routes['shell'] : null;
      if (shell == null &&
          root is Map &&
          root['suPresent'] == true &&
          root['probed'] != true) {
        status = await _privilegeStatus(probeRoot: true);
      }
      _lastPrivilegeStatus = status;
      _lastPrivilegeAt = _clock();
      return status;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 最近 5 分钟内的执行通道状态（本服务或 android_device 读取过的都算）。
  Map<String, dynamic>? get recentPrivilegeStatus {
    final at = _lastPrivilegeAt;
    if (_lastPrivilegeStatus != null &&
        at != null &&
        _clock().difference(at) < const Duration(minutes: 5)) {
      return _lastPrivilegeStatus;
    }
    return AndroidDeviceControlBridge.recentPrivilegeStatus;
  }

  /// 同步版本（供审批详情使用）：基于最近的通道快照；没有快照时返回 null。
  List<String>? cachedFallbackWarnings(AutomationRule rule) {
    if (!_hasFallbackCandidates(rule)) return const [];
    final status = recentPrivilegeStatus;
    return status == null ? null : _fallbackWarnings(rule, status);
  }

  /// 最近一次读取到的规则（同步查找，供审批详情使用）。
  AutomationRule? cachedRule(String id) {
    for (final rule in _rulesCache ?? const <AutomationRule>[]) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  bool _hasFallbackCandidates(AutomationRule rule) => rule.actions
      .any((action) => automationFallbackCandidates.contains(action.action));

  List<String> _fallbackWarnings(
    AutomationRule rule,
    Map<String, dynamic> status,
  ) {
    final context = AutomationPrivilegeContext.fromStatus(status);
    return [
      for (final action in rule.actions)
        if (automationFallbackFor(action, context) case final note?) note,
    ];
  }

  Future<AutomationRule?> findRule(String id) async {
    for (final rule in await rules()) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  Future<void> _saveRules(List<AutomationRule> rules) async {
    _rulesCache = List.unmodifiable(rules);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      rulesKey,
      jsonEncode(rules.map((rule) => rule.toJson()).toList()),
    );
    await syncToNative(rules);
  }

  /// 把规则同步给原生触发器；非 Android 平台或插件缺失时静默跳过。
  Future<void> syncToNative([List<AutomationRule>? current]) async {
    try {
      await _bridge.syncRules(current ?? await rules());
    } on MissingPluginException {
      // 测试或非 Android 平台。
    } on PlatformException {
      // 同步失败不影响本地规则；下次打开页面会再同步。
    }
  }

  Future<AutomationRule> createRule({
    required String name,
    required AutomationTrigger trigger,
    required List<AutomationAction> actions,
    String? userRequest,
  }) async {
    final now = _clock().millisecondsSinceEpoch;
    final rule = AutomationRule(
      id: UniqueId.generate('auto'),
      name: name.trim(),
      enabled: true,
      trigger: trigger,
      actions: actions,
      createdAtMs: now,
      updatedAtMs: now,
    );
    final error = rule.validate();
    if (error != null) throw ArgumentError(error);
    final existing = await rules();
    if (existing.length >= maxRules) {
      throw StateError('最多保留 $maxRules 条自动化规则');
    }
    await _saveRules([...existing, rule]);
    await _auditRule('created', rule, userRequest: userRequest);
    return rule;
  }

  Future<AutomationRule> setEnabled(
    String id,
    bool enabled, {
    String? userRequest,
  }) async {
    final existing = await rules();
    final index = existing.indexWhere((rule) => rule.id == id);
    if (index < 0) throw StateError('规则不存在');
    final updated = existing[index].copyWith(
      enabled: enabled,
      updatedAtMs: _clock().millisecondsSinceEpoch,
    );
    final next = [...existing]..[index] = updated;
    await _saveRules(next);
    await _auditRule(enabled ? 'enabled' : 'paused', updated,
        userRequest: userRequest);
    return updated;
  }

  Future<void> deleteRule(String id, {String? userRequest}) async {
    final existing = await rules();
    final rule = existing.where((rule) => rule.id == id).firstOrNull;
    if (rule == null) throw StateError('规则不存在');
    await _saveRules(existing.where((rule) => rule.id != id).toList());
    await _auditRule('deleted', rule, userRequest: userRequest);
  }

  // -------------------------------------------------------------------------
  // 触发与执行
  // -------------------------------------------------------------------------

  Future<List<AutomationFire>> pendingFires() async {
    try {
      return await _bridge.pendingFires();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// 已通过 SAF 授权的目录（供“清理目录”规则选择 treeUri）。
  Future<List<Map<String, String>>> authorizedFolders() async {
    try {
      return await const AndroidDeviceControlBridge().listAuthorizedFolders();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// 为每个动作生成预览；“清理目录”会先列出将删除的文件（最多 100 个）。
  Future<PreparedAutomation> prepare(
    AutomationRule rule, {
    AutomationFire? fire,
  }) async {
    final prepared = <PreparedDeviceAction>[];
    for (final action in rule.actions) {
      prepared.add(await _prepareAction(action));
    }
    return PreparedAutomation(
      rule: rule,
      fire: fire,
      triggerText: fire?.trigger ?? '手动运行',
      actions: prepared,
    );
  }

  Future<PreparedDeviceAction> _prepareAction(AutomationAction action) async {
    final description = action.describe();
    final validation = action.validate();
    if (validation != null) {
      return PreparedDeviceAction(
        description: description,
        arguments: action.toJson(),
        error: validation,
      );
    }
    if (action.action != 'clean_folder') {
      return _runner.prepare(description, action.toJson());
    }
    final days = (action.arguments['olderThanDays'] as num).toInt();
    final extension = action.arguments['extension'] as String?;
    Map<String, dynamic> listing;
    try {
      listing = await _bridge.listFolderFiles(
        treeUri: action.arguments['treeUri'] as String,
        modifiedBeforeMs:
            _clock().subtract(Duration(days: days)).millisecondsSinceEpoch,
        extension: extension,
      );
    } on PlatformException catch (error) {
      return PreparedDeviceAction(
        description: description,
        arguments: action.toJson(),
        error: '无法列出目录：${error.message ?? error.code}',
      );
    } on MissingPluginException {
      return PreparedDeviceAction(
        description: description,
        arguments: action.toJson(),
        error: '目录清理仅支持 Android',
      );
    }
    final files = (listing['files'] as List? ?? const [])
        .whereType<Map>()
        .map((file) => Map<String, dynamic>.from(file))
        .toList();
    if (files.isEmpty) {
      return PreparedDeviceAction(
        description: description,
        arguments: action.toJson(),
        error: '没有符合条件的文件，无需清理',
      );
    }
    final extra = {
      'fileCount': files.length,
      'matchedCount': listing['matchedCount'] ?? files.length,
      'totalBytes': listing['totalBytes'] ?? 0,
      'remaining': listing['remaining'] ?? 0,
      'sample': files.take(20).map((file) => file['name']).toList(),
    };
    return _runner.prepare(
      description,
      {
        'action': 'file_operation',
        'operation': 'delete',
        'uris': files.map((file) => file['uri'] as String).toList(),
      },
      extra: extra,
    );
  }

  /// 用户确认后执行，并记录执行历史、撤销信息与审计。
  Future<AutomationRun> executePrepared(PreparedAutomation prepared) async {
    // 每个设置类动作执行前单独读取一次系统设置，用于计算该步的撤销参数。
    final settingsBefore = <PreparedDeviceAction, Map<String, dynamic>>{};
    final outcomes = await _runner.executeConfirmed(
      prepared.actions,
      userRequest: prepared.userRequest,
      toolName: 'android_automation',
      intentSource: 'automation_rule',
      beforeEach: (action) async {
        if (_settingsActions.contains(action.arguments['action'])) {
          settingsBefore[action] = await _readSettings();
        }
      },
    );
    final steps = <AutomationStepResult>[];
    for (final outcome in outcomes) {
      final undo = outcome.result.ok
          ? automationUndoFor(
              outcome.prepared.arguments,
              settingsBefore[outcome.prepared] ?? const {},
            )
          : null;
      steps.add(AutomationStepResult(
        description: outcome.prepared.description,
        deviceAction: outcome.prepared.arguments['action']?.toString() ?? '',
        ok: outcome.result.ok,
        code: outcome.result.code,
        message: outcome.result.message,
        reversible: outcome.prepared.reversible,
        undoArguments: undo?.arguments,
        undoDescription: undo?.description,
      ));
    }
    final okCount = steps.where((step) => step.ok).length;
    final run = AutomationRun(
      id: UniqueId.generate('autorun'),
      ruleId: prepared.rule.id,
      ruleName: prepared.rule.name,
      fireId: prepared.fire?.fireId,
      trigger: prepared.triggerText,
      startedAtMs: outcomes.isEmpty
          ? _clock().millisecondsSinceEpoch
          : outcomes.first.startedAt.millisecondsSinceEpoch,
      status: okCount == steps.length
          ? 'executed'
          : okCount == 0
              ? 'failed'
              : 'partial',
      steps: steps,
    );
    await _appendRun(run);
    await _resolve(prepared.fire);
    await _auditRule('executed_${run.status}', prepared.rule,
        trigger: prepared.triggerText);
    return run;
  }

  /// 用户放弃本次触发：作废预览、记录历史与审计。
  Future<AutomationRun> dismiss(PreparedAutomation prepared) async {
    await _runner.reject(
      prepared.actions,
      userRequest: prepared.userRequest,
      toolName: 'android_automation',
      intentSource: 'automation_rule',
    );
    final run = AutomationRun(
      id: UniqueId.generate('autorun'),
      ruleId: prepared.rule.id,
      ruleName: prepared.rule.name,
      fireId: prepared.fire?.fireId,
      trigger: prepared.triggerText,
      startedAtMs: _clock().millisecondsSinceEpoch,
      status: 'dismissed',
      steps: const [],
    );
    await _appendRun(run);
    await _resolve(prepared.fire);
    await _auditRule('dismissed', prepared.rule, trigger: prepared.triggerText);
    return run;
  }

  /// 规则已被删除时，直接清掉孤立的触发。
  Future<void> discardFire(AutomationFire fire) async {
    await _resolve(fire);
  }

  Future<void> _resolve(AutomationFire? fire) async {
    if (fire == null) return;
    try {
      await _bridge.resolveFire(fire.fireId);
    } on MissingPluginException {
      // 非 Android。
    } on PlatformException {
      // 待确认记录 12 小时后自动过期。
    }
  }

  Future<Map<String, dynamic>> _readSettings() async {
    try {
      final result = await _runner.tool.execute({'action': 'system_settings'});
      return result.ok ? (result.data ?? const {}) : const {};
    } catch (_) {
      return const {};
    }
  }

  // -------------------------------------------------------------------------
  // 撤销
  // -------------------------------------------------------------------------

  Future<PreparedDeviceAction> prepareUndo(String runId, int stepIndex) async {
    final run = (await runs()).where((run) => run.id == runId).firstOrNull;
    if (run == null || stepIndex < 0 || stepIndex >= run.steps.length) {
      throw StateError('执行记录不存在');
    }
    final step = run.steps[stepIndex];
    if (!step.canUndo) throw StateError('该步骤不可撤销或已撤销');
    return _runner.prepare(
      '撤销：${step.description} → ${step.undoDescription ?? ''}',
      step.undoArguments!,
    );
  }

  Future<DeviceActionOutcome> executeUndo(
    String runId,
    int stepIndex,
    PreparedDeviceAction prepared,
  ) async {
    final outcome = (await _runner.executeConfirmed(
      [prepared],
      userRequest: '撤销自动化执行记录 $runId 第 ${stepIndex + 1} 步',
      toolName: 'android_automation',
      intentSource: 'automation_undo',
    ))
        .single;
    if (outcome.result.ok) {
      final all = await runs();
      final index = all.indexWhere((run) => run.id == runId);
      if (index >= 0) {
        final run = all[index];
        final steps = [...run.steps];
        steps[stepIndex] =
            steps[stepIndex].markUndone(_clock().millisecondsSinceEpoch);
        all[index] = run.copyWithSteps(steps);
        await _saveRuns(all);
      }
    }
    return outcome;
  }

  // -------------------------------------------------------------------------
  // 执行记录
  // -------------------------------------------------------------------------

  Future<List<AutomationRun>> runs({String? ruleId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(runsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return [
        for (final item in decoded is List ? decoded : const [])
          if (AutomationRun.fromJson(item) case final run?)
            if (ruleId == null || run.ruleId == ruleId) run,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _appendRun(AutomationRun run) async {
    final all = await runs();
    await _saveRuns([run, ...all].take(maxRuns).toList());
  }

  Future<void> _saveRuns(List<AutomationRun> runs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      runsKey,
      jsonEncode(runs.map((run) => run.toJson()).toList()),
    );
  }

  Future<void> _auditRule(
    String event,
    AutomationRule rule, {
    String? userRequest,
    String? trigger,
  }) async {
    final database = _database;
    if (database == null) return;
    try {
      await _audit.logDeviceAutomationEvent(
        await database(),
        event: event,
        ruleId: rule.id,
        ruleName: rule.name,
        trigger: trigger ?? rule.trigger.describe(),
        actions: rule.actions.map((action) => action.describe()).toList(),
        requiresRoot: rule.requiresRoot,
        irreversible: rule.hasIrreversibleAction,
        userRequest: userRequest,
      );
    } catch (_) {
      // 审计服务内部已记录失败。
    }
  }
}

final deviceAutomationServiceProvider =
    Provider<DeviceAutomationService>((ref) {
  return DeviceAutomationService(
    runner: ref.watch(deviceActionRunnerProvider),
    audit: ref.watch(auditServiceProvider),
    database: () => ref.read(databaseProvider.future),
  );
});
