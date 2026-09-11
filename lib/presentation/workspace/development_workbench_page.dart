import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/development_workflow.dart';
import '../../infrastructure/tools/command_tool.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

class DevelopmentWorkbenchPage extends StatefulWidget {
  const DevelopmentWorkbenchPage({super.key, required this.workspacePath});
  final String workspacePath;

  @override
  State<DevelopmentWorkbenchPage> createState() =>
      _DevelopmentWorkbenchPageState();
}

class _DevelopmentWorkbenchPageState extends State<DevelopmentWorkbenchPage> {
  late final TerminalCommandService _terminal;
  DevelopmentWorkflow _selected = DevelopmentWorkflowTemplates.flutterApk;
  DevelopmentWorkflowResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _terminal = TerminalCommandService(workspacePath: widget.workspacePath);
  }

  @override
  void dispose() {
    _terminal.stop();
    super.dispose();
  }

  Future<void> _run() async {
    final approved = await showConfirmAction(
      context,
      title: '确认执行开发工作流',
      message: '将依次在工作区执行以下构建与校验指令：',
      confirmLabel: '开始执行',
      cancelLabel: '取消',
      isDanger: false,
      bulletItems: _selected.steps.map((step) => step.command).toList(),
    );
    if (approved != true || _running || !mounted) {
      return;
    }
    setState(() {
      _running = true;
      _result = null;
    });
    final result = await DevelopmentWorkflowRunner(_terminal)
        .run(_selected, widget.workspacePath);
    if (mounted) {
      setState(() {
        _running = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas,
      appBar: const NexusPageHeader(
        title: '开发工作台',
        subtitle: '模板构建、校验与产物管理',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppPalette.brandAction,
        foregroundColor: Colors.white,
        onPressed: _running ? null : _run,
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
          // 模板选择
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<DevelopmentWorkflow>(
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
          ),
          const SizedBox(height: 14),

          // 步骤时间线：准备、执行、校验、产物
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
                      '工作流步骤时间线',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...List.generate(_selected.steps.length, (index) {
                  final step = _selected.steps[index];
                  const stageLabels = ['准备', '执行', '校验', '产物'];
                  final stageLabel = index < stageLabels.length
                      ? stageLabels[index]
                      : '步骤 ${index + 1}';
                  final isLast = index == _selected.steps.length - 1;

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: AppPalette.brandAction,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? AppPalette.darkBrandSoft
                                            : AppPalette.lightBrandSoft,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        stageLabel,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? AppPalette.brand
                                              : AppPalette.brandOnSoft,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      step.id,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF161B26)
                                        : const Color(0xFFF3F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '\$ ${step.command}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
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

          // 构建产物与执行结果区
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
                        _result!.success ? '构建校验完成' : '构建遇到错误',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _result!.success
                              ? AppPalette.success
                              : AppPalette.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_result!.artifactPath != null ||
                      _result!.sha256 != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppPalette.darkSurface
                            : AppPalette.lightSurface,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
                        border: Border.all(
                          color: isDark
                              ? AppPalette.darkHairline
                              : AppPalette.lightHairline,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_result!.artifactPath != null) ...[
                            Row(
                              children: [
                                const Icon(Icons.android_rounded,
                                    size: 16, color: AppPalette.success),
                                const SizedBox(width: 6),
                                const Text('APK 产物：',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                Expanded(
                                  child: Text(
                                    _result!.artifactPath!,
                                    style: const TextStyle(
                                        fontSize: 12, fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '复制产物路径',
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(
                                        text: _result!.artifactPath!));
                                    FloatingToast.show(context, '已复制产物路径');
                                  },
                                ),
                              ],
                            ),
                          ],
                          if (_result!.sha256 != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.fingerprint_rounded,
                                    size: 16, color: AppPalette.brand),
                                const SizedBox(width: 6),
                                const Text('.sha256：',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                Expanded(
                                  child: Text(
                                    _result!.sha256!,
                                    style: const TextStyle(
                                        fontSize: 11, fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '复制 SHA-256 校验和',
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: _result!.sha256!));
                                    FloatingToast.show(
                                        context, '已复制 SHA-256 校验和');
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          const Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 14, color: AppPalette.lightTextMuted),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '产物仅存留于本地工作区，未收到发布指令不会上传 Release。',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppPalette.lightTextMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
}
