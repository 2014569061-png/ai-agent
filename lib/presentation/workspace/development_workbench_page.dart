import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../application/apk_install_bridge.dart';
import '../../application/artifact_service.dart';
import '../../application/chat_controller.dart';
import '../../application/development_verification.dart';
import '../../application/providers.dart';
import '../../application/development_workflow.dart';
import '../../application/project_kind.dart';
import '../../application/verification_repair_service.dart';
import '../../infrastructure/tools/command_tool.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_status_pill.dart';
import '../widgets/section_card.dart';

class DevelopmentWorkbenchPage extends ConsumerStatefulWidget {
  const DevelopmentWorkbenchPage({
    super.key,
    required this.workspacePath,
    this.projectId,
  });
  final String workspacePath;
  final String? projectId;

  @override
  ConsumerState<DevelopmentWorkbenchPage> createState() =>
      _DevelopmentWorkbenchPageState();
}

class _DevelopmentWorkbenchPageState
    extends ConsumerState<DevelopmentWorkbenchPage> {
  late final TerminalCommandService _terminal;
  late final DevelopmentWorkflowRunner _runner;
  DevelopmentWorkflow _selected = DevelopmentWorkflowTemplates.flutterApk;
  DevelopmentWorkflowResult? _result;
  bool _running = false;
  bool _detecting = true;
  ProjectKindDetection? _project;

  @override
  void initState() {
    super.initState();
    _terminal = TerminalCommandService(workspacePath: widget.workspacePath);
    _runner = DevelopmentWorkflowRunner(_terminal);
    _detect();
  }

  Future<void> _detect() async {
    final workflow = await _runner.detectWorkflow(widget.workspacePath);
    final project =
        await DevelopmentVerificationService().planFor(widget.workspacePath);
    if (!mounted) return;
    setState(() {
      _selected = workflow;
      _project = project.project;
      _detecting = false;
    });
  }

  @override
  void dispose() {
    _terminal.stop();
    super.dispose();
  }

  Future<void> _run({String? retryStepId}) async {
    final steps = _result?.plan?.steps ??
        DevelopmentVerificationService()
            .planFromDetection(_project ??
                const ProjectKindDetection(
                    kind: ProjectKind.unknown, confidence: 0, signals: []))
            .steps;
    final preview = retryStepId == null
        ? steps.map((step) => step.command.isEmpty ? step.title : step.command)
        : steps
            .where((step) => step.id == retryStepId)
            .map((step) => step.command.isEmpty ? step.title : step.command);
    final approved = await showConfirmAction(
      context,
      title: retryStepId == null ? '确认执行开发工作流' : '确认重试失败步骤',
      message: retryStepId == null
          ? '将依次在工作区执行分析、测试、构建，并检查真实产物：'
          : '只会重新执行失败步骤及其后续校验：',
      confirmLabel: retryStepId == null ? '开始执行' : '重试此步',
      cancelLabel: '取消',
      isDanger: false,
      bulletItems: preview.toList(),
    );
    if (approved != true || _running || !mounted) {
      return;
    }
    setState(() {
      _running = true;
      if (retryStepId == null) _result = null;
    });
    final result = await _runner.run(
      _selected,
      widget.workspacePath,
      retryStepId: retryStepId,
      previousPlan: _result?.plan,
    );
    if (mounted) {
      setState(() {
        _running = false;
        _result = result;
      });
    }
    if (result.success && widget.projectId != null) {
      try {
        final db = await ref.read(databaseProvider.future);
        final taskId =
            ref.read(chatControllerProvider).currentTaskId ?? 'manual';
        final artifact = result.artifactPath;
        if (artifact != null && artifact.isNotEmpty) {
          await const ArtifactService().record(
            db: db,
            projectId: widget.projectId!,
            taskId: taskId,
            runId: taskId,
            workspacePath: widget.workspacePath,
            inspection: ArtifactInspection(
              relativePath: p.relative(artifact, from: widget.workspacePath),
              exists: result.artifactExists,
              absolutePath: artifact,
              bytes: result.artifactBytes,
              sha256: result.sha256,
              packageName: result.packageName,
              notes: result.notes,
            ),
          );
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final steps = _result?.plan?.steps ??
        (_project == null
            ? _selected.steps
                .map((step) => VerificationStep(
                      id: step.id,
                      title: step.title ?? step.id,
                      command: step.command,
                      kind: step.kind,
                      expectedArtifactPath: step.expectedArtifactPath,
                    ))
                .toList()
            : DevelopmentVerificationService()
                .planFromDetection(_project!)
                .steps);

    return Scaffold(
      appBar: const NexusPageHeader(
        title: '开发工作台',
        subtitle: '识别项目、执行验证并检查真实产物',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppPalette.brandAction,
        foregroundColor: Colors.white,
        onPressed: _running ? null : () => _run(),
        icon: _running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ))
            : const Icon(Icons.play_arrow_rounded),
        label: Text(_running ? '构建中…' : '开始执行'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _detecting
                      ? '正在识别项目类型…'
                      : '当前项目：${_project?.kind.label ?? _selected.name}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.workspacePath,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<DevelopmentWorkflow>(
                  initialValue: _selected,
                  decoration: const InputDecoration(
                    labelText: '工作流模板',
                    isDense: true,
                  ),
                  items: DevelopmentWorkflowTemplates.all
                      .map((workflow) => DropdownMenuItem(
                          value: workflow, child: Text(workflow.name)))
                      .toList(),
                  onChanged: _running
                      ? null
                      : (value) => setState(() => _selected = value!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.timeline_rounded,
                        size: 18, color: AppPalette.brand),
                    SizedBox(width: 8),
                    Text(
                      '验证步骤',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...List.generate(steps.length, (index) {
                  final step = steps[index];
                  final isLast = index == steps.length - 1;
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            _statusDot(step.status),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 1.5,
                                  color: AppPalette.brandAction
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        step.title,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    NexusStatusPill.fromString(step.status.id,
                                        isCompact: true,
                                        customLabel: step.status.label),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (step.command.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppPalette.darkSurface
                                          : AppPalette.lightSurface,
                                      borderRadius: BorderRadius.circular(
                                          AppTokens.radiusControl),
                                    ),
                                    child: Text(
                                      '\$ ${step.command}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (step.canRetry && !_running)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          _run(retryStepId: step.id),
                                      icon: const Icon(Icons.refresh_rounded,
                                          size: 16),
                                      label: const Text('重试此步'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 14),
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _result!.success
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: _result!.success
                            ? AppPalette.success
                            : AppPalette.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _result!.success ? '验证完成' : '验证遇到错误',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _result!.success
                              ? AppPalette.success
                              : AppPalette.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_result!.artifactPath != null) _artifactPanel(isDark),
                  if (!_result!.success) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _continueFixFromFailure,
                        icon: const Icon(Icons.healing_outlined, size: 16),
                        label: const Text('根据这次错误继续修复'),
                      ),
                    ),
                  ],
                  const Text('步骤日志',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  ..._result!.steps.map((step) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(
                          step.message,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11.5),
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusDot(VerificationStepStatus status) {
    final color = switch (status) {
      VerificationStepStatus.passed => AppPalette.success,
      VerificationStepStatus.failed => AppPalette.danger,
      VerificationStepStatus.running => AppPalette.brand,
      VerificationStepStatus.skipped => AppPalette.warning,
      VerificationStepStatus.pending => AppPalette.brandAction,
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(
        switch (status) {
          VerificationStepStatus.passed => Icons.check,
          VerificationStepStatus.failed => Icons.close,
          VerificationStepStatus.running => Icons.more_horiz,
          VerificationStepStatus.skipped => Icons.remove,
          VerificationStepStatus.pending => Icons.circle_outlined,
        },
        size: 12,
        color: Colors.white,
      ),
    );
  }

  Widget _artifactPanel(bool isDark) {
    final path = _result!.artifactPath!;
    final exists = _result!.artifactExists;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(
            color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  exists
                      ? Icons.inventory_2_outlined
                      : Icons.warning_amber_rounded,
                  size: 16,
                  color: exists ? AppPalette.success : AppPalette.warning,
                ),
                const SizedBox(width: 6),
                Text(exists ? '真实产物' : '产物不存在',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '复制产物路径',
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: path));
                    FloatingToast.show(context, '已复制产物路径');
                  },
                ),
              ],
            ),
            if (_result!.sha256 != null)
              Text('SHA-256：${_result!.sha256}',
                  style:
                      const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            if (_result!.packageName != null)
              Text('包名：${_result!.packageName}',
                  style: const TextStyle(fontSize: 12)),
            if (_result!.artifactBytes != null)
              Text('大小：${_result!.artifactBytes} 字节',
                  style: const TextStyle(fontSize: 12)),
            for (final note in _result!.notes)
              Text(note, style: const TextStyle(fontSize: 12)),
            if (exists) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _shareArtifact(path),
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('分享'),
                  ),
                  if (path.toLowerCase().endsWith('.apk'))
                    FilledButton.tonalIcon(
                      onPressed: () => _installApk(path),
                      icon: const Icon(Icons.install_mobile_outlined, size: 16),
                      label: const Text('安装'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _shareArtifact(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        FloatingToast.show(context, '产物文件不存在', tone: ToastTone.warning);
      }
      return;
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: p.basename(path),
    ));
  }

  Future<void> _continueFixFromFailure() async {
    final plan = _result?.plan;
    if (plan == null) return;
    final request = const VerificationRepairService().fromFailedPlan(
      plan: plan,
      workspacePath: widget.workspacePath,
    );
    if (request == null) {
      if (mounted) {
        FloatingToast.show(context, '没有可形成修复任务的失败步骤', tone: ToastTone.warning);
      }
      return;
    }
    final prompt = const VerificationRepairService().promptFor(request);
    try {
      await ref.read(chatControllerProvider.notifier).enqueueRepairFollowUp(
            prompt: prompt,
          );
      if (mounted) {
        FloatingToast.show(context, '已创建关联修复任务，失败证据已保留',
            tone: ToastTone.success);
      }
    } catch (error) {
      await Clipboard.setData(ClipboardData(text: prompt));
      if (mounted) {
        FloatingToast.show(context, '入队失败，已复制修复提示：$error',
            tone: ToastTone.warning);
      }
    }
  }

  Future<void> _installApk(String path) async {
    final result = await const ApkInstallBridge().install(path);
    if (!mounted) return;
    final message = switch (result.status) {
      'started' => '已拉起系统安装器',
      'cancelled' => '用户取消安装',
      'permission_required' => '需要允许安装未知应用后再试',
      _ => result.message ?? '无法拉起系统安装器',
    };
    FloatingToast.show(
      context,
      message,
      tone: result.started ? ToastTone.success : ToastTone.warning,
    );
    if (result.failed) {
      await Clipboard.setData(ClipboardData(text: path));
    }
  }
}
