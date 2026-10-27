import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/mobile_workflow_service.dart';
import '../../application/providers.dart';
import '../../domain/mobile_workflow.dart';
import '../settings/settings_components.dart';
import '../widgets/async_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_disclosure.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/section_card.dart';
import '../widgets/confirm_action.dart';
import '../../application/local_error_copy.dart';

class MobileWorkflowsPage extends ConsumerStatefulWidget {
  const MobileWorkflowsPage({super.key});

  @override
  ConsumerState<MobileWorkflowsPage> createState() =>
      _MobileWorkflowsPageState();
}

class _MobileWorkflowsPageState extends ConsumerState<MobileWorkflowsPage> {
  final TextEditingController _topicController =
      TextEditingController(text: '冲刺周报核对与提醒归档');
  bool _loading = true;
  bool _executing = false;
  Object? _error;
  List<WorkflowDefinition> _definitions = const <WorkflowDefinition>[];
  List<WorkflowRunRecord> _runs = const <WorkflowRunRecord>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await ref.read(databaseProvider.future);
      final service = MobileWorkflowService(db);
      final defs = await service.listDefinitions();
      final runs = await service.listRuns();
      if (!mounted) return;
      setState(() {
        _definitions = defs;
        _runs = runs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _execute(
    WorkflowDefinition def, {
    required bool dryRun,
    required bool confirmed,
  }) async {
    if (_executing) return;
    final inputs = <String, String>{'topic': _topicController.text.trim()};
    setState(() => _executing = true);
    try {
      if (!dryRun) {
        final accepted = await showConfirmAction(context,
            title: '执行工作流？',
            message: '${def.name} · v${def.version}\n主题：${inputs['topic']}\n'
                '${def.steps.map((step) => '• ${step.title}').join('\n')}\n将按以上输入与步骤执行。',
            confirmLabel: '确认执行');
        if (!accepted || !mounted) return;
      }
      final db = await ref.read(databaseProvider.future);
      final service = MobileWorkflowService(db);
      final record = await service.runWorkflow(
        workflowId: def.id,
        inputs: inputs,
        expectedVersion: def.version,
        dryRun: dryRun,
        highRiskConfirmed: confirmed,
      );
      await _load();
      if (!mounted) return;
      FloatingToast.show(
        context,
        dryRun ? '试跑完成（状态：${record.status}）' : '工作流执行结束（状态：${record.status}）',
      );
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, LocalErrorCopy.of(error, action: '执行').headline());
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: settingsBgColor(context),
      appBar: NexusPageHeader(
        title: '可复用工作流',
        subtitle: '步骤编排与安全执行',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _executing ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: NexusPageLayout(
        child: AsyncStateView(
          loading: _loading,
          error: _error,
          onRetry: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              SectionCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '本次执行主题',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('mobile-workflow-topic-input'),
                      controller: _topicController,
                      enabled: !_executing,
                      decoration: const InputDecoration(
                        hintText: '输入工作流执行主题…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SettingsSectionTitle('已定义工作流'),
              for (final def in _definitions) ...<Widget>[
                SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${def.name} · v${def.version}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        def.description,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${def.steps.length} 个步骤 · ${def.steps.where((step) => step.requiresConfirmation).length} 项需确认',
                        style: theme.textTheme.bodySmall,
                      ),
                      NexusDisclosure(
                        title: const Text('查看执行步骤'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final step in def.steps)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '${step.title} · ${step.kind.label}${step.requiresConfirmation ? " · 需确认" : ""}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            key: ValueKey('workflow-dry-run-${def.id}'),
                            onPressed: _executing
                                ? null
                                : () => unawaited(
                                      _execute(def,
                                          dryRun: true, confirmed: false),
                                    ),
                            icon: const Icon(Icons.science_outlined, size: 16),
                            label: const Text('沙盒试跑'),
                          ),
                          FilledButton.tonalIcon(
                            key: ValueKey('workflow-confirm-run-${def.id}'),
                            onPressed: _executing
                                ? null
                                : () => unawaited(
                                      _execute(def,
                                          dryRun: false, confirmed: true),
                                    ),
                            icon: const Icon(Icons.play_circle_outline_rounded,
                                size: 16),
                            label: const Text('确认并执行'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_runs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                const SettingsSectionTitle('最近执行'),
                for (final run in _runs.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${run.dryRun ? "[试跑]" : "[正式]"} ${run.workflowId} · 状态：${run.status}',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          NexusDisclosure(
                            title: Text('执行明细 · ${run.stepTraces.length} 个步骤'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final trace in run.stepTraces)
                                  Text('${trace.title}：${trace.outputSummary}',
                                      style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
