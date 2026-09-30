import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';
import '../../domain/unique_id.dart';

/// 运行预设（阶段 7d）：一组可保存、可切换的会话设置。
///
/// - **稳定 id**：创建时生成，重命名、更新快照都不变，导出/同步时可作为主键。
/// - **快照**：保存当时的服务商、模型、推理、模式、审批、联网与 Agent；
///   字段为 null 表示「应用时不改这一项」。
/// - **兼容性提示**：应用前检查引用的服务商 / Agent 是否仍存在、格式版本是否
///   比当前更新，缺失的项跳过并提示，而不是报错。

class PresetSnapshot {
  const PresetSnapshot({
    this.providerId,
    this.providerName,
    this.model,
    this.reasoningEffort,
    this.reasoningMode,
    this.chatMode,
    this.approvalMode,
    this.webSearch,
    this.agentId,
    this.agentName,
    this.unrecognized = const [],
  });

  final String? providerId;

  /// 仅用于提示（服务商被删后仍能说出它原来的名字）。
  final String? providerName;
  final String? model;
  final ReasoningEffort? reasoningEffort;
  final ReasoningMode? reasoningMode;
  final ChatMode? chatMode;
  final ApprovalMode? approvalMode;
  final bool? webSearch;
  final String? agentId;
  final String? agentName;

  /// 解码时无法识别的取值（例如更新版本新增的枚举值），形如 `mode=review`。
  final List<String> unrecognized;

  bool get isEmpty =>
      providerId == null &&
      reasoningEffort == null &&
      reasoningMode == null &&
      chatMode == null &&
      approvalMode == null &&
      webSearch == null &&
      agentId == null;

  /// 预设里设置了的每一项都与 [current] 相同（未设置的项不参与比较）。
  bool sameSettings(PresetSnapshot current) {
    bool same(Object? mine, Object? theirs) => mine == null || mine == theirs;
    return !isEmpty &&
        same(providerId, current.providerId) &&
        same(providerId == null ? null : model, current.model) &&
        same(providerId == null ? null : reasoningEffort, current.reasoningEffort) &&
        same(reasoningMode, current.reasoningMode) &&
        same(chatMode, current.chatMode) &&
        same(approvalMode, current.approvalMode) &&
        same(webSearch, current.webSearch) &&
        same(agentId, current.agentId);
  }

  Map<String, dynamic> toJson() => {
        if (providerId != null) 'providerId': providerId,
        if (providerName != null) 'providerName': providerName,
        if (model != null) 'model': model,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort!.name,
        if (reasoningMode != null) 'reasoningMode': reasoningMode!.name,
        if (chatMode != null) 'chatMode': chatMode!.name,
        if (approvalMode != null) 'approvalMode': approvalMode!.name,
        if (webSearch != null) 'webSearch': webSearch,
        if (agentId != null) 'agentId': agentId,
        if (agentName != null) 'agentName': agentName,
      };

  factory PresetSnapshot.fromJson(Map<String, dynamic> json) {
    final unrecognized = <String>[];
    T? enumOf<T extends Enum>(String key, List<T> values) {
      final raw = json[key];
      if (raw == null) return null;
      for (final value in values) {
        if (value.name == raw) return value;
      }
      unrecognized.add('$key=$raw');
      return null;
    }

    String? str(String key) {
      final raw = json[key];
      return raw is String && raw.trim().isNotEmpty ? raw : null;
    }

    return PresetSnapshot(
      providerId: str('providerId'),
      providerName: str('providerName'),
      model: str('model'),
      reasoningEffort: enumOf('reasoningEffort', ReasoningEffort.values),
      reasoningMode: enumOf('reasoningMode', ReasoningMode.values),
      chatMode: enumOf('chatMode', ChatMode.values),
      approvalMode: enumOf('approvalMode', ApprovalMode.values),
      webSearch: json['webSearch'] is bool ? json['webSearch'] as bool : null,
      agentId: str('agentId'),
      agentName: str('agentName'),
      unrecognized: unrecognized,
    );
  }

  /// 给界面展示的简要说明，按应用顺序排列。
  List<String> describe() => [
        if (providerId != null)
          '模型：${providerName ?? providerId}${model == null ? '' : ' / $model'}',
        if (reasoningEffort != null) '思考程度：${reasoningEffortLabel(reasoningEffort!)}',
        if (reasoningMode != null) '推理：${reasoningMode!.label}',
        if (agentId != null) 'Agent：${agentName ?? agentId}',
        if (chatMode != null) '模式：${chatMode!.label}',
        if (approvalMode != null) '审批：${approvalModeLabel(approvalMode!)}',
        if (webSearch != null) '联网搜索：${webSearch! ? '开' : '关'}',
      ];
}

String reasoningEffortLabel(ReasoningEffort effort) => switch (effort) {
      ReasoningEffort.auto => '自动',
      ReasoningEffort.off => '关闭',
      ReasoningEffort.low => '低',
      ReasoningEffort.medium => '中',
      ReasoningEffort.high => '高',
    };

String approvalModeLabel(ApprovalMode mode) => switch (mode) {
      ApprovalMode.ask => '每次询问',
      ApprovalMode.autoSafe => '自动允许安全操作',
      ApprovalMode.fullAccess => '完全访问',
    };

class RunPreset {
  const RunPreset({
    required this.id,
    required this.name,
    required this.snapshot,
    required this.createdAt,
    required this.updatedAt,
    this.formatVersion = currentFormatVersion,
  });

  static const currentFormatVersion = 1;
  static const idPrefix = 'preset';

  final String id;
  final String name;
  final PresetSnapshot snapshot;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 写入时的格式版本；比 [currentFormatVersion] 新时给出兼容性提示。
  final int formatVersion;

  /// 从当前会话设置抓取一个新预设（聊天状态的转换见 `run_preset_providers.dart`）。
  factory RunPreset.capture(
    String name, {
    String? providerId,
    String? providerName,
    String? model,
    ReasoningEffort? reasoningEffort,
    ReasoningMode? reasoningMode,
    ChatMode? chatMode,
    ApprovalMode? approvalMode,
    bool? webSearch,
    String? agentId,
    String? agentName,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final provider = _nonEmpty(providerId);
    final agent = _nonEmpty(agentId);
    return RunPreset(
      id: UniqueId.generate(idPrefix, now: at),
      name: name.trim(),
      createdAt: at,
      updatedAt: at,
      snapshot: PresetSnapshot(
        providerId: provider,
        providerName: provider == null ? null : _nonEmpty(providerName),
        model: provider == null ? null : _nonEmpty(model),
        reasoningEffort: provider == null ? null : reasoningEffort,
        reasoningMode: reasoningMode,
        chatMode: chatMode,
        approvalMode: approvalMode,
        webSearch: webSearch,
        agentId: agent,
        agentName: agent == null ? null : _nonEmpty(agentName),
      ),
    );
  }

  RunPreset copyWith({String? name, PresetSnapshot? snapshot, DateTime? updatedAt}) =>
      RunPreset(
        id: id,
        name: name ?? this.name,
        snapshot: snapshot ?? this.snapshot,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        formatVersion: formatVersion,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'formatVersion': formatVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'snapshot': snapshot.toJson(),
      };

  /// 损坏或缺少关键字段时返回 null，调用方跳过这一条即可。
  static RunPreset? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final id = map['id'];
    final name = map['name'];
    final snapshot = map['snapshot'];
    if (id is! String || id.isEmpty || name is! String || snapshot is! Map) {
      return null;
    }
    DateTime time(String key) =>
        DateTime.tryParse('${map[key]}')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return RunPreset(
      id: id,
      name: name,
      snapshot: PresetSnapshot.fromJson(snapshot.cast<String, dynamic>()),
      createdAt: time('createdAt'),
      updatedAt: time('updatedAt'),
      formatVersion: (map['formatVersion'] as num?)?.toInt() ?? 1,
    );
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

// ---------------------------------------------------------------------------
// 兼容性
// ---------------------------------------------------------------------------

enum PresetIssueLevel { info, warning }

class PresetIssue {
  const PresetIssue(this.level, this.message);

  final PresetIssueLevel level;
  final String message;

  @override
  String toString() => '${level.name}: $message';
}

/// 应用预设时可用的服务商与 Agent（id → 名称）。
class PresetEnvironment {
  const PresetEnvironment({this.providers = const {}, this.agents = const {}});

  final Map<String, String> providers;
  final Map<String, String> agents;
}

abstract final class PresetCompatibility {
  static List<PresetIssue> check(RunPreset preset, PresetEnvironment env) {
    final snap = preset.snapshot;
    return [
      if (preset.formatVersion > RunPreset.currentFormatVersion)
        const PresetIssue(PresetIssueLevel.warning,
            '这个预设由更新版本的应用创建，部分设置可能不会生效'),
      if (snap.unrecognized.isNotEmpty)
        PresetIssue(PresetIssueLevel.warning,
            '无法识别的设置已跳过：${snap.unrecognized.join('、')}'),
      if (snap.providerId != null && !env.providers.containsKey(snap.providerId))
        PresetIssue(PresetIssueLevel.warning,
            '服务商「${snap.providerName ?? snap.providerId}」已不存在，将保留当前模型'),
      if (snap.agentId != null && !env.agents.containsKey(snap.agentId))
        PresetIssue(PresetIssueLevel.warning,
            'Agent「${snap.agentName ?? snap.agentId}」已删除，将保留当前 Agent'),
      if (snap.approvalMode == ApprovalMode.fullAccess)
        const PresetIssue(PresetIssueLevel.info, '将开启「完全访问」：工具调用不再逐次询问'),
      if (snap.isEmpty)
        const PresetIssue(PresetIssueLevel.info, '这个预设没有保存任何设置'),
    ];
  }
}

// ---------------------------------------------------------------------------
// 应用
// ---------------------------------------------------------------------------

/// 预设作用的对象。聊天控制器通过适配器实现；测试里用假实现。
abstract interface class PresetTarget {
  bool get running;

  /// 切换到指定服务商，可同时覆盖模型与思考程度；找不到服务商时返回 false。
  Future<bool> switchProvider(String providerId,
      {String? model, ReasoningEffort? reasoningEffort});

  /// 找不到 Agent 时返回 false。
  Future<bool> selectAgentById(String agentId);

  Future<void> setReasoningMode(ReasoningMode mode);
  void setMode(ChatMode mode);
  void setApprovalMode(ApprovalMode mode);
  Future<void> setWebSearchEnabled(bool value);
}

class PresetApplyReport {
  const PresetApplyReport({
    required this.applied,
    required this.skipped,
    this.blocked = false,
  });

  /// 运行中不允许切换，整个预设都没有应用。
  final bool blocked;
  final List<String> applied;
  final List<String> skipped;
}

abstract final class RunPresetApplier {
  /// 顺序：服务商（会重置思考程度）→ Agent（会把模式切到 Agent）→ 模式 →
  /// 审批 → 推理 → 联网，保证预设里的值最终生效。
  static Future<PresetApplyReport> apply(
    RunPreset preset,
    PresetTarget target,
    PresetEnvironment env,
  ) async {
    if (target.running) {
      return const PresetApplyReport(
          applied: [], skipped: ['正在运行，结束后再切换预设'], blocked: true);
    }
    final snap = preset.snapshot;
    final applied = <String>[];
    final skipped = <String>[];

    final providerId = snap.providerId;
    if (providerId != null) {
      final ok = env.providers.containsKey(providerId) &&
          await target.switchProvider(providerId,
              model: snap.model, reasoningEffort: snap.reasoningEffort);
      (ok ? applied : skipped).add('模型');
      if (ok && snap.reasoningEffort != null) applied.add('思考程度');
    } else if (snap.reasoningEffort != null) {
      // 思考程度保存在服务商配置里，没有服务商就无处落地。
      skipped.add('思考程度');
    }

    final agentId = snap.agentId;
    if (agentId != null) {
      final ok = env.agents.containsKey(agentId) &&
          await target.selectAgentById(agentId);
      (ok ? applied : skipped).add('Agent');
    }
    if (snap.chatMode case final mode?) {
      target.setMode(mode);
      applied.add('模式');
    }
    if (snap.approvalMode case final mode?) {
      target.setApprovalMode(mode);
      applied.add('审批');
    }
    if (snap.reasoningMode case final mode?) {
      await target.setReasoningMode(mode);
      applied.add('推理');
    }
    if (snap.webSearch case final enabled?) {
      await target.setWebSearchEnabled(enabled);
      applied.add('联网搜索');
    }
    return PresetApplyReport(applied: applied, skipped: skipped);
  }
}

// ---------------------------------------------------------------------------
// 存储
// ---------------------------------------------------------------------------

class RunPresetStore {
  RunPresetStore({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  static const storageKey = 'run_presets.v1';
  static const maxPresets = 50;

  final Future<SharedPreferences> Function() _preferences;

  /// 最近更新的在前；损坏的条目被跳过。
  Future<List<RunPreset>> list() async {
    final prefs = await _preferences();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List) return [];
    final presets = [
      for (final item in decoded)
        if (RunPreset.tryFromJson(item) case final preset?) preset,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return presets;
  }

  /// 按 id 插入或替换。
  Future<void> save(RunPreset preset) async {
    final presets = [
      preset,
      for (final existing in await list())
        if (existing.id != preset.id) existing,
    ];
    await _write(presets.take(maxPresets).toList());
  }

  Future<void> delete(String id) async =>
      _write([for (final p in await list()) if (p.id != id) p]);

  Future<void> _write(List<RunPreset> presets) async {
    final prefs = await _preferences();
    await prefs.setString(
        storageKey, jsonEncode([for (final p in presets) p.toJson()]));
  }
}
