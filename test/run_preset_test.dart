// 阶段 7d：运行预设。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/presets/run_preset.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTarget implements PresetTarget {
  _FakeTarget({this.running = false});

  @override
  bool running;
  final calls = <String>[];
  bool providerOk = true;
  bool agentOk = true;

  @override
  Future<bool> switchProvider(String providerId,
      {String? model, ReasoningEffort? reasoningEffort}) async {
    calls.add('provider:$providerId:$model:${reasoningEffort?.name}');
    return providerOk;
  }

  @override
  Future<bool> selectAgentById(String agentId) async {
    calls.add('agent:$agentId');
    return agentOk;
  }

  @override
  Future<void> setReasoningMode(ReasoningMode mode) async =>
      calls.add('reasoning:${mode.name}');

  @override
  void setMode(ChatMode mode) => calls.add('mode:${mode.name}');

  @override
  void setApprovalMode(ApprovalMode mode) => calls.add('approval:${mode.name}');

  @override
  Future<void> setWebSearchEnabled(bool value) async => calls.add('web:$value');
}

void main() {
  final now = DateTime(2026, 9, 30, 12);

  RunPreset full() => RunPreset.capture(
        '深度编码',
        providerId: 'p1',
        providerName: 'DeepSeek',
        model: 'deepseek-reasoner',
        reasoningEffort: ReasoningEffort.high,
        reasoningMode: ReasoningMode.deep,
        chatMode: ChatMode.plan,
        approvalMode: ApprovalMode.autoSafe,
        webSearch: false,
        agentId: 'a1',
        agentName: '代码助手',
        now: now,
      );

  const env = PresetEnvironment(
    providers: {'p1': 'DeepSeek'},
    agents: {'a1': '代码助手'},
  );

  test('capture gives a stable prefixed id and round-trips through JSON', () {
    final preset = full();
    expect(preset.id, startsWith('preset-'));
    final decoded = RunPreset.tryFromJson(jsonDecode(jsonEncode(preset.toJson())))!;
    expect(decoded.id, preset.id);
    expect(decoded.name, '深度编码');
    expect(decoded.createdAt, now);
    expect(decoded.snapshot.toJson(), preset.snapshot.toJson());
    expect(decoded.snapshot.unrecognized, isEmpty);

    final renamed = preset.copyWith(name: '新名字');
    expect(renamed.id, preset.id);
  });

  test('model and effort are only captured together with a provider', () {
    final preset = RunPreset.capture('x', model: 'm', reasoningEffort: ReasoningEffort.low,
        agentName: '孤儿', webSearch: true);
    expect(preset.snapshot.providerId, isNull);
    expect(preset.snapshot.model, isNull);
    expect(preset.snapshot.reasoningEffort, isNull);
    expect(preset.snapshot.agentName, isNull);
    expect(preset.snapshot.webSearch, isTrue);
  });

  test('decoding tolerates unknown values, newer versions and corrupt entries', () {
    final preset = RunPreset.tryFromJson({
      'id': 'preset-x',
      'name': '未来',
      'formatVersion': 3,
      'snapshot': {'chatMode': 'review', 'approvalMode': 'ask', 'extra': 1},
    })!;
    expect(preset.snapshot.chatMode, isNull);
    expect(preset.snapshot.approvalMode, ApprovalMode.ask);
    expect(preset.snapshot.unrecognized, ['chatMode=review']);
    final issues = PresetCompatibility.check(preset, env);
    expect(issues.map((i) => i.level), everyElement(PresetIssueLevel.warning));
    expect(issues.length, 2);

    expect(RunPreset.tryFromJson({'name': 'no id', 'snapshot': {}}), isNull);
    expect(RunPreset.tryFromJson('garbage'), isNull);
  });

  test('compatibility flags missing provider/agent and full access', () {
    final preset = full().copyWith(
      snapshot: PresetSnapshot.fromJson({
        ...full().snapshot.toJson(),
        'approvalMode': 'fullAccess',
      }),
    );
    expect(PresetCompatibility.check(preset, env).single.level,
        PresetIssueLevel.info);
    final issues = PresetCompatibility.check(preset, const PresetEnvironment());
    expect(issues.where((i) => i.level == PresetIssueLevel.warning).length, 2);
    expect(issues.first.message, contains('DeepSeek'));
    expect(issues[1].message, contains('代码助手'));
  });

  test('apply runs in order so the preset mode wins over the agent default', () async {
    final target = _FakeTarget();
    final report = await RunPresetApplier.apply(full(), target, env);
    expect(target.calls, [
      'provider:p1:deepseek-reasoner:high',
      'agent:a1',
      'mode:plan',
      'approval:autoSafe',
      'reasoning:deep',
      'web:false',
    ]);
    expect(report.blocked, isFalse);
    expect(report.skipped, isEmpty);
    expect(report.applied, contains('思考程度'));
  });

  test('apply skips missing references and refuses while running', () async {
    final target = _FakeTarget();
    final report =
        await RunPresetApplier.apply(full(), target, const PresetEnvironment());
    expect(target.calls.any((c) => c.startsWith('provider') || c.startsWith('agent')),
        isFalse);
    expect(report.skipped, ['模型', 'Agent']);
    expect(report.applied, isNot(contains('思考程度')));

    final busy = _FakeTarget(running: true);
    final blocked = await RunPresetApplier.apply(full(), busy, env);
    expect(blocked.blocked, isTrue);
    expect(busy.calls, isEmpty);
  });

  test('sameSettings ignores fields the preset does not set', () {
    final current = full().snapshot;
    expect(full().snapshot.sameSettings(current), isTrue);
    final partial = RunPreset.capture('p', webSearch: false).snapshot;
    expect(partial.sameSettings(current), isTrue);
    final different = RunPreset.capture('p', webSearch: true).snapshot;
    expect(different.sameSettings(current), isFalse);
    expect(const PresetSnapshot().sameSettings(current), isFalse);
  });

  test('store upserts by id, keeps newest first and skips corrupt data', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RunPresetStore();
    final a = RunPreset.capture('A', webSearch: true, now: now);
    final b = RunPreset.capture('B', webSearch: false,
        now: now.add(const Duration(minutes: 1)));
    await store.save(a);
    await store.save(b);
    expect((await store.list()).map((p) => p.name), ['B', 'A']);

    await store.save(a.copyWith(name: 'A2', updatedAt: now.add(const Duration(hours: 1))));
    final list = await store.list();
    expect(list.map((p) => p.name), ['A2', 'B']);
    expect(list.first.id, a.id);

    await store.delete(b.id);
    expect((await store.list()).single.name, 'A2');

    SharedPreferences.setMockInitialValues({RunPresetStore.storageKey: '{broken'});
    expect(await RunPresetStore().list(), isEmpty);
    SharedPreferences.setMockInitialValues({
      RunPresetStore.storageKey: jsonEncode([
        {'bad': true},
        a.toJson(),
      ]),
    });
    expect((await RunPresetStore().list()).single.id, a.id);
  });
}
