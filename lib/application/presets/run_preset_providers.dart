import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../chat_controller.dart';
import '../providers.dart';
import 'run_preset.dart';

export 'run_preset.dart';

/// 从聊天状态抓取预设快照。
RunPreset presetFromChatState(String name, ChatState state, {DateTime? now}) =>
    RunPreset.capture(
      name,
      providerId: state.activeProviderId,
      providerName: state.activeProviderName,
      model: state.activeModel,
      reasoningEffort: state.activeReasoningEffort,
      reasoningMode: state.reasoningMode,
      chatMode: state.mode,
      approvalMode: state.approvalMode,
      webSearch: state.webSearchEnabled,
      agentId: state.agentId,
      agentName: state.agentName,
      now: now,
    );

/// 聊天控制器上的 [PresetTarget] 实现。
class ChatPresetTarget implements PresetTarget {
  ChatPresetTarget(this._ref);

  final Ref _ref;

  ChatController get _chat => _ref.read(chatControllerProvider.notifier);

  @override
  bool get running => _ref.read(chatControllerProvider).running;

  @override
  Future<bool> switchProvider(String providerId,
      {String? model, ReasoningEffort? reasoningEffort}) async {
    final profiles = await _ref.read(providerConfigStoreProvider).loadAll();
    final matches = profiles.where((p) => p.id == providerId);
    if (matches.isEmpty) return false;
    final profile = matches.first;
    await _chat.switchProvider(profile.copyWith(
      model: model,
      reasoningEffort: reasoningEffort,
    ));
    return true;
  }

  @override
  Future<bool> selectAgentById(String agentId) async {
    final db = await _ref.read(databaseProvider.future);
    final agent = await db.findAgent(agentId);
    if (agent == null) return false;
    await _chat.selectAgent(agent);
    return true;
  }

  @override
  Future<void> setReasoningMode(ReasoningMode mode) =>
      _chat.setReasoningMode(mode);

  @override
  void setMode(ChatMode mode) => _chat.setMode(mode);

  @override
  void setApprovalMode(ApprovalMode mode) => _chat.setApprovalMode(mode);

  @override
  Future<void> setWebSearchEnabled(bool value) =>
      _chat.setWebSearchEnabled(value);
}

class RunPresetService {
  RunPresetService(this._ref, {RunPresetStore? store})
      : store = store ?? RunPresetStore();

  final Ref _ref;
  final RunPresetStore store;

  Future<List<RunPreset>> list() => store.list();

  /// 把当前会话设置保存为新预设。
  Future<RunPreset> saveCurrent(String name) async {
    final preset = presetFromChatState(name, _ref.read(chatControllerProvider));
    await store.save(preset);
    return preset;
  }

  /// 用当前设置覆盖预设的快照；id 与名称不变。
  Future<RunPreset> updateFromCurrent(RunPreset preset) async {
    final fresh = presetFromChatState(preset.name, _ref.read(chatControllerProvider));
    final updated =
        preset.copyWith(snapshot: fresh.snapshot, updatedAt: DateTime.now());
    await store.save(updated);
    return updated;
  }

  Future<RunPreset> rename(RunPreset preset, String name) async {
    final updated = preset.copyWith(name: name.trim(), updatedAt: DateTime.now());
    await store.save(updated);
    return updated;
  }

  Future<void> delete(String id) => store.delete(id);

  /// 当前设置是否与预设一致（用于在列表里标出「当前」）。
  bool matchesCurrent(RunPreset preset) => preset.snapshot
      .sameSettings(presetFromChatState('', _ref.read(chatControllerProvider)).snapshot);

  Future<PresetEnvironment> environment() async {
    final profiles = await _ref.read(providerConfigStoreProvider).loadAll();
    final db = await _ref.read(databaseProvider.future);
    final agents = await db.allAgents();
    return PresetEnvironment(
      providers: {for (final p in profiles) p.id: p.name},
      agents: {for (final a in agents) a.id: a.name},
    );
  }

  Future<List<PresetIssue>> check(RunPreset preset) async =>
      PresetCompatibility.check(preset, await environment());

  Future<PresetApplyReport> apply(RunPreset preset) async =>
      RunPresetApplier.apply(preset, ChatPresetTarget(_ref), await environment());
}

final runPresetServiceProvider =
    Provider<RunPresetService>((ref) => RunPresetService(ref));
