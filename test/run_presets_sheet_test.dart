// 阶段 7d：运行预设面板。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/presets/run_preset_providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/presets/run_presets_sheet.dart';

class _FakeService extends RunPresetService {
  _FakeService(super.ref);

  final presets = <RunPreset>[];
  final applied = <String>[];
  List<PresetIssue> issues = const [];

  @override
  Future<List<RunPreset>> list() async => List.of(presets);

  @override
  Future<RunPreset> saveCurrent(String name) async {
    final preset = RunPreset.capture(name,
        chatMode: ChatMode.agent, approvalMode: ApprovalMode.autoSafe, webSearch: true);
    presets.insert(0, preset);
    return preset;
  }

  @override
  bool matchesCurrent(RunPreset preset) => false;

  @override
  Future<List<PresetIssue>> check(RunPreset preset) async => issues;

  @override
  Future<PresetApplyReport> apply(RunPreset preset) async {
    applied.add(preset.id);
    return const PresetApplyReport(applied: ['模式'], skipped: ['Agent']);
  }

  @override
  Future<void> delete(String id) async => presets.removeWhere((p) => p.id == id);
}

void main() {
  testWidgets('save current, then apply after confirming warnings', (tester) async {
    late _FakeService service;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        runPresetServiceProvider.overrideWith((ref) => service = _FakeService(ref)),
      ],
      child: const MaterialApp(home: Scaffold(body: RunPresetsSheet())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('还没有预设'), findsOneWidget);

    await tester.tap(find.text('保存当前设置为预设'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '快速问答');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('快速问答'), findsOneWidget);
    expect(find.textContaining('模式：Agent'), findsOneWidget);
    expect(find.textContaining('联网搜索：开'), findsOneWidget);

    service.issues = const [
      PresetIssue(PresetIssueLevel.warning, 'Agent「代码助手」已删除，将保留当前 Agent'),
    ];
    await tester.tap(find.text('快速问答'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已删除'), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(service.applied, [service.presets.single.id]);

    // 让提示条的计时器走完。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
