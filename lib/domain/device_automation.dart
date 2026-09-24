import 'package:flutter/foundation.dart';

/// 设备自动化规则的领域模型（纯 Dart，便于测试）。
///
/// 规则 = 触发条件 + 白名单设备动作。触发后只生成“待确认”记录，执行必须由
/// 用户在前台逐项查看预览后确认；动作最终仍通过 android_device 的
/// 预览 → 审批 → 一次性票据流程执行。

enum AutomationTriggerType {
  time('time'),
  wifiConnected('wifi_connected'),
  batteryBelow('battery_below');

  const AutomationTriggerType(this.wire);
  final String wire;

  static AutomationTriggerType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

@immutable
class AutomationTrigger {
  const AutomationTrigger.time({
    required int this.hour,
    required int this.minute,
    this.days = const [],
  })  : type = AutomationTriggerType.time,
        ssid = null,
        threshold = null;

  const AutomationTrigger.wifiConnected(String this.ssid)
      : type = AutomationTriggerType.wifiConnected,
        hour = null,
        minute = null,
        days = const [],
        threshold = null;

  const AutomationTrigger.batteryBelow(int this.threshold)
      : type = AutomationTriggerType.batteryBelow,
        hour = null,
        minute = null,
        days = const [],
        ssid = null;

  final AutomationTriggerType type;
  final int? hour;
  final int? minute;

  /// ISO 星期（1=周一 … 7=周日），空表示每天。
  final List<int> days;
  final String? ssid;
  final int? threshold;

  static AutomationTrigger? fromJson(Object? json) {
    if (json is! Map) return null;
    switch (AutomationTriggerType.fromWire(json['type'])) {
      case AutomationTriggerType.time:
        final hour = json['hour'];
        final minute = json['minute'];
        if (hour is! num || minute is! num) return null;
        return AutomationTrigger.time(
          hour: hour.toInt(),
          minute: minute.toInt(),
          days: (json['days'] as List? ?? const [])
              .whereType<num>()
              .map((e) => e.toInt())
              .toList(growable: false),
        );
      case AutomationTriggerType.wifiConnected:
        final ssid = json['ssid'];
        return ssid is String ? AutomationTrigger.wifiConnected(ssid) : null;
      case AutomationTriggerType.batteryBelow:
        final threshold = json['threshold'];
        return threshold is num
            ? AutomationTrigger.batteryBelow(threshold.toInt())
            : null;
      case null:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.wire,
        if (hour != null) 'hour': hour,
        if (minute != null) 'minute': minute,
        if (type == AutomationTriggerType.time) 'days': days,
        if (ssid != null) 'ssid': ssid,
        if (threshold != null) 'threshold': threshold,
      };

  String? validate() {
    switch (type) {
      case AutomationTriggerType.time:
        if (hour == null || hour! < 0 || hour! > 23) return '小时必须在 0–23 之间';
        if (minute == null || minute! < 0 || minute! > 59) {
          return '分钟必须在 0–59 之间';
        }
        if (days.any((day) => day < 1 || day > 7)) {
          return 'days 使用 ISO 星期 1–7';
        }
      case AutomationTriggerType.wifiConnected:
        final value = ssid?.trim() ?? '';
        if (value.isEmpty || value.length > 32) {
          return 'Wi-Fi 名称（SSID）需为 1–32 个字符';
        }
      case AutomationTriggerType.batteryBelow:
        if (threshold == null || threshold! < 5 || threshold! > 95) {
          return '电量阈值必须在 5%–95% 之间';
        }
    }
    return null;
  }

  String describe() {
    switch (type) {
      case AutomationTriggerType.time:
        final time =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        if (days.isEmpty) return '每天 $time';
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final sorted = [...days]..sort();
        return '每周${sorted.map((d) => names[d - 1]).join('、')} $time';
      case AutomationTriggerType.wifiConnected:
        return '连接 Wi-Fi「$ssid」后';
      case AutomationTriggerType.batteryBelow:
        return '电量低于 $threshold% 且未充电时';
    }
  }
}

/// 自动化允许使用的设备动作白名单。
///
/// 故意不包含任意文件写入、Root 文件操作、防火墙/hosts、飞行模式等：
/// 这些动作影响面大或可能切断远程控制，不适合“定时/条件触发”。
const automationAllowedActions = <String>{
  'launch_app',
  'launch_app_by_name',
  'launch_deep_link',
  'stop_app',
  'clear_app_cache',
  'set_wifi',
  'set_bluetooth',
  'set_do_not_disturb',
  'set_brightness',
  'set_volume',
  'set_auto_rotate',
  'clean_folder',
};

/// 当前设备的执行通道（来自 privilegeStatus）。
class AutomationPrivilegeContext {
  const AutomationPrivilegeContext({
    required this.shellAvailable,
    required this.rootUidAvailable,
    required this.sdkInt,
    this.permissions = const {},
  });

  factory AutomationPrivilegeContext.fromStatus(Map<String, dynamic> status) {
    final routes = status['routes'];
    final permissions = status['permissions'];
    final sdk = status['sdkInt'];
    return AutomationPrivilegeContext(
      shellAvailable: routes is Map && routes['shell'] != null,
      rootUidAvailable: routes is Map && routes['rootUid'] != null,
      sdkInt: sdk is num ? sdk.toInt() : 0,
      permissions: permissions is Map
          ? {
              for (final entry in permissions.entries)
                entry.key.toString(): entry.value == true,
            }
          : const {},
    );
  }

  final bool shellAvailable;
  final bool rootUidAvailable;
  final int sdkInt;
  final Map<String, bool> permissions;

  bool allowed(String permission) => permissions[permission] == true;
}

/// 在当前通道下，该动作触发时会降级成什么；null 表示仍能直接完成。
///
/// 规则与原生 PrivilegedDeviceControl 的降级顺序一致：
/// Root → Shizuku → 系统 API（需对应权限）→ 打开系统设置页。
String? automationFallbackFor(
  AutomationAction action,
  AutomationPrivilegeContext context,
) {
  final label = action.describe();
  switch (action.action) {
    case 'set_wifi':
      if (context.shellAvailable ||
          (context.sdkInt > 0 && context.sdkInt < 29)) {
        return null;
      }
      return '$label：只能打开 Wi-Fi 面板，由你手动切换';
    case 'set_bluetooth':
      if (context.shellAvailable ||
          (context.sdkInt > 0 &&
              context.sdkInt < 33 &&
              context.allowed('bluetoothConnect'))) {
        return null;
      }
      return '$label：只能打开蓝牙设置页或系统确认框，由你手动完成';
    case 'set_do_not_disturb':
      if (context.shellAvailable || context.allowed('notificationPolicy')) {
        return null;
      }
      return '$label：未授予勿扰权限，只能打开勿扰授权页';
    case 'set_brightness':
    case 'set_auto_rotate':
      if (context.shellAvailable || context.allowed('writeSettings')) {
        return null;
      }
      return '$label：未允许“修改系统设置”，只能打开授权页';
    case 'stop_app':
      if (context.shellAvailable) return null;
      return '$label：只能结束后台进程并打开应用详情页，需要你点“强行停止”';
    case 'clear_app_cache':
      if (context.rootUidAvailable ||
          (context.shellAvailable && context.sdkInt >= 34)) {
        return null;
      }
      return '$label：只能打开应用详情页，由你手动清除缓存';
  }
  return null;
}

/// 可能需要降级的自动化动作（其余动作不依赖特权）。
const automationFallbackCandidates = <String>{
  'set_wifi',
  'set_bluetooth',
  'set_do_not_disturb',
  'set_brightness',
  'set_auto_rotate',
  'stop_app',
  'clear_app_cache',
};

/// 需要特权（Root 或 Shizuku）的自动化动作；规则里含这些动作时，创建/启用按 dangerous 审批。
///
/// 没有 Root/Shizuku 时，原生层会降级为系统 API 或打开系统设置页（执行确认页会显示实际通道）。
const automationRootActions = <String>{
  'stop_app',
  'clear_app_cache',
  'set_wifi',
  'set_bluetooth',
  'set_do_not_disturb',
};

/// 不可撤销的自动化动作。
const automationIrreversibleActions = <String>{
  'clear_app_cache',
  'clean_folder'
};

@immutable
class AutomationAction {
  const AutomationAction(this.action, [this.arguments = const {}]);

  final String action;
  final Map<String, dynamic> arguments;

  static AutomationAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final action = json['action'];
    if (action is! String) return null;
    final arguments = <String, dynamic>{};
    for (final entry in json.entries) {
      if (entry.key == 'action') continue;
      arguments[entry.key.toString()] = entry.value;
    }
    return AutomationAction(action, arguments);
  }

  Map<String, dynamic> toJson() => {'action': action, ...arguments};

  bool get requiresRoot => automationRootActions.contains(action);
  bool get irreversible => automationIrreversibleActions.contains(action);

  /// 结构校验；具体参数（包名、数值范围等）由 android_device 预览再次校验。
  String? validate() {
    if (!automationAllowedActions.contains(action)) {
      return '自动化不支持动作 $action；允许：${automationAllowedActions.join('、')}';
    }
    if (action == 'clean_folder') {
      final treeUri = arguments['treeUri'];
      final days = arguments['olderThanDays'];
      if (treeUri is! String || !treeUri.startsWith('content://')) {
        return 'clean_folder 需要已授权目录的 treeUri（list_authorized_folders 返回的 uri）';
      }
      if (days is! num || days < 0 || days > 3650) {
        return 'clean_folder 需要 olderThanDays（0–3650）';
      }
      final extension = arguments['extension'];
      if (extension != null &&
          (extension is! String ||
              !RegExp(r'^\.?[A-Za-z0-9]{1,10}$').hasMatch(extension))) {
        return 'clean_folder 的 extension 格式无效';
      }
    }
    return null;
  }

  String describe() {
    final args = arguments;
    return switch (action) {
      'launch_app' => '打开应用 ${args['packageName']}',
      'launch_app_by_name' => '打开应用「${args['appName'] ?? args['query']}」',
      'launch_deep_link' => '打开 ${args['packageName']} 的页面 ${args['deepLink']}',
      'stop_app' => '停止应用 ${args['packageName']}（Root/Shizuku）',
      'clear_app_cache' => '清理 ${args['packageName']} 的缓存（Root/Shizuku，不可撤销）',
      'set_wifi' =>
        '${args['enabled'] == true ? '开启' : '关闭'} Wi-Fi（Root/Shizuku）',
      'set_bluetooth' =>
        '${args['enabled'] == true ? '开启' : '关闭'}蓝牙（Root/Shizuku）',
      'set_do_not_disturb' =>
        '${args['enabled'] == true ? '开启' : '关闭'}勿扰模式（Root/Shizuku）',
      'set_brightness' => '亮度设为 ${((args['value'] as num?) ?? 0) * 100 ~/ 1}%',
      'set_volume' =>
        '${args['stream']} 音量设为 ${((args['value'] as num?) ?? 0) * 100 ~/ 1}%',
      'set_auto_rotate' => '${args['enabled'] == true ? '开启' : '关闭'}自动旋转',
      'clean_folder' =>
        '删除授权目录中 ${args['olderThanDays']} 天前的${args['extension'] != null ? ' .${(args['extension'] as String).replaceFirst('.', '')} ' : ''}文件（不可撤销，每次最多 100 个）',
      _ => action,
    };
  }
}

@immutable
class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.trigger,
    required this.actions,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;
  final String name;
  final bool enabled;
  final AutomationTrigger trigger;
  final List<AutomationAction> actions;
  final int createdAtMs;
  final int updatedAtMs;

  static const maxActions = 5;

  bool get requiresRoot => actions.any((action) => action.requiresRoot);
  bool get hasIrreversibleAction =>
      actions.any((action) => action.irreversible);

  static AutomationRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final trigger = AutomationTrigger.fromJson(json['trigger']);
    final rawActions = json['actions'];
    if (id is! String ||
        name is! String ||
        trigger == null ||
        rawActions is! List) {
      return null;
    }
    final actions = rawActions
        .map(AutomationAction.fromJson)
        .whereType<AutomationAction>()
        .toList(growable: false);
    return AutomationRule(
      id: id,
      name: name,
      enabled: json['enabled'] != false,
      trigger: trigger,
      actions: actions,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'trigger': trigger.toJson(),
        'actions': actions.map((action) => action.toJson()).toList(),
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  AutomationRule copyWith({bool? enabled, int? updatedAtMs}) => AutomationRule(
        id: id,
        name: name,
        enabled: enabled ?? this.enabled,
        trigger: trigger,
        actions: actions,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  String? validate() {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) return '规则名称需为 1–40 个字符';
    final triggerError = trigger.validate();
    if (triggerError != null) return triggerError;
    if (actions.isEmpty) return '至少需要一个动作';
    if (actions.length > maxActions) return '每条规则最多 $maxActions 个动作';
    for (final action in actions) {
      final error = action.validate();
      if (error != null) return error;
    }
    return null;
  }
}

/// 一次触发（fire）的执行记录。
@immutable
class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.ruleId,
    required this.ruleName,
    required this.trigger,
    required this.startedAtMs,
    required this.status,
    required this.steps,
    this.fireId,
  });

  final String id;
  final String ruleId;
  final String ruleName;
  final String? fireId;
  final String trigger;
  final int startedAtMs;

  /// executed / partial / failed / dismissed / skipped
  final String status;
  final List<AutomationStepResult> steps;

  static AutomationRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final ruleId = json['ruleId'];
    if (id is! String || ruleId is! String) return null;
    return AutomationRun(
      id: id,
      ruleId: ruleId,
      ruleName: json['ruleName']?.toString() ?? '',
      fireId: json['fireId'] as String?,
      trigger: json['trigger']?.toString() ?? '',
      startedAtMs: (json['startedAtMs'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'unknown',
      steps: (json['steps'] as List? ?? const [])
          .map(AutomationStepResult.fromJson)
          .whereType<AutomationStepResult>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleId': ruleId,
        'ruleName': ruleName,
        if (fireId != null) 'fireId': fireId,
        'trigger': trigger,
        'startedAtMs': startedAtMs,
        'status': status,
        'steps': steps.map((step) => step.toJson()).toList(),
      };

  AutomationRun copyWithSteps(List<AutomationStepResult> steps) =>
      AutomationRun(
        id: id,
        ruleId: ruleId,
        ruleName: ruleName,
        fireId: fireId,
        trigger: trigger,
        startedAtMs: startedAtMs,
        status: status,
        steps: steps,
      );
}

@immutable
class AutomationStepResult {
  const AutomationStepResult({
    required this.description,
    required this.deviceAction,
    required this.ok,
    required this.code,
    required this.message,
    required this.reversible,
    this.undoArguments,
    this.undoDescription,
    this.undoneAtMs,
  });

  final String description;
  final String deviceAction;
  final bool ok;
  final String code;
  final String message;
  final bool reversible;

  /// 撤销时交给 android_device 的参数（同样需要预览与确认）。
  final Map<String, dynamic>? undoArguments;
  final String? undoDescription;
  final int? undoneAtMs;

  bool get canUndo => ok && undoArguments != null && undoneAtMs == null;

  static AutomationStepResult? fromJson(Object? json) {
    if (json is! Map) return null;
    return AutomationStepResult(
      description: json['description']?.toString() ?? '',
      deviceAction: json['deviceAction']?.toString() ?? '',
      ok: json['ok'] == true,
      code: json['code']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      reversible: json['reversible'] == true,
      undoArguments: json['undoArguments'] is Map
          ? Map<String, dynamic>.from(json['undoArguments'] as Map)
          : null,
      undoDescription: json['undoDescription'] as String?,
      undoneAtMs: (json['undoneAtMs'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'description': description,
        'deviceAction': deviceAction,
        'ok': ok,
        'code': code,
        'message': message,
        'reversible': reversible,
        if (undoArguments != null) 'undoArguments': undoArguments,
        if (undoDescription != null) 'undoDescription': undoDescription,
        if (undoneAtMs != null) 'undoneAtMs': undoneAtMs,
      };

  AutomationStepResult markUndone(int atMs) => AutomationStepResult(
        description: description,
        deviceAction: deviceAction,
        ok: ok,
        code: code,
        message: message,
        reversible: reversible,
        undoArguments: undoArguments,
        undoDescription: undoDescription,
        undoneAtMs: atMs,
      );
}

/// 根据执行前读取的系统设置计算撤销参数；拿不到原值时返回 null（明确不可自动撤销）。
({Map<String, dynamic> arguments, String description})? automationUndoFor(
  Map<String, dynamic> deviceArguments,
  Map<String, dynamic> settingsBefore,
) {
  final action = deviceArguments['action'];
  bool? previousBool(String key) =>
      settingsBefore[key] is bool ? settingsBefore[key] as bool : null;
  double? previousDouble(String key) {
    final value = settingsBefore[key];
    return value is num && value >= 0 && value <= 1 ? value.toDouble() : null;
  }

  switch (action) {
    case 'set_wifi':
    case 'set_bluetooth':
    case 'set_do_not_disturb':
    case 'set_auto_rotate':
      final key = switch (action) {
        'set_wifi' => 'wifiEnabled',
        'set_bluetooth' => 'bluetoothEnabled',
        'set_do_not_disturb' => 'doNotDisturbEnabled',
        _ => 'autoRotate',
      };
      final previous = previousBool(key);
      if (previous == null || previous == deviceArguments['enabled']) {
        return null;
      }
      return (
        arguments: {'action': action, 'enabled': previous},
        description: '恢复为${previous ? '开启' : '关闭'}',
      );
    case 'set_brightness':
      final previous = previousDouble('brightness');
      if (previous == null) return null;
      return (
        arguments: {'action': 'set_brightness', 'value': previous},
        description: '亮度恢复为 ${(previous * 100).round()}%',
      );
    case 'set_volume':
      final stream = deviceArguments['stream'];
      final key = switch (stream) {
        'music' => 'musicVolume',
        'ring' => 'ringVolume',
        _ => null,
      };
      final previous = key == null ? null : previousDouble(key);
      if (previous == null) return null;
      return (
        arguments: {
          'action': 'set_volume',
          'stream': stream,
          'value': previous
        },
        description: '$stream 音量恢复为 ${(previous * 100).round()}%',
      );
    case 'stop_app':
      return (
        arguments: {
          'action': 'launch_app',
          'packageName': deviceArguments['packageName'],
        },
        description: '重新启动应用（进程状态无法完全还原）',
      );
  }
  return null;
}
