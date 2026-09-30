import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/presets/run_preset_providers.dart';
import '../widgets/confirm_action.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_sheet.dart';
import '../widgets/section_card.dart';

/// 打开运行预设面板（阶段 7d）。
Future<void> showRunPresetsSheet(BuildContext context) => showNexusSheet<void>(
      context: context,
      builder: (_) => const RunPresetsSheet(),
    );

/// 运行预设：保存当前设置、一键切换、更新、重命名、删除。
class RunPresetsSheet extends ConsumerStatefulWidget {
  const RunPresetsSheet({super.key});

  @override
  ConsumerState<RunPresetsSheet> createState() => _RunPresetsSheetState();
}

class _RunPresetsSheetState extends ConsumerState<RunPresetsSheet> {
  List<RunPreset>? _presets;
  bool _busy = false;

  RunPresetService get _service => ref.read(runPresetServiceProvider);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final presets = await _service.list();
    if (mounted) setState(() => _presets = presets);
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        FloatingToast.show(context, '操作失败', detail: '$error', tone: ToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCurrent() async {
    final name = await _askName(title: '保存为预设', initial: '');
    if (name == null) return;
    await _guard(() async {
      await _service.saveCurrent(name);
      await _reload();
      if (mounted) FloatingToast.show(context, '已保存预设「$name」', tone: ToastTone.success);
    });
  }

  Future<void> _apply(RunPreset preset) async {
    await _guard(() async {
      final issues = await _service.check(preset);
      if (!mounted) return;
      if (issues.isNotEmpty) {
        final hasWarning = issues.any((i) => i.level == PresetIssueLevel.warning);
        final confirmed = await showConfirmAction(
          context,
          title: '应用「${preset.name}」？',
          message: hasWarning ? '部分设置无法恢复，其余设置会照常应用。' : '请确认以下变化。',
          confirmLabel: '应用',
          isDanger: false,
          bulletItems: [for (final issue in issues) issue.message],
        );
        if (!confirmed || !mounted) return;
      }
      final report = await _service.apply(preset);
      if (!mounted) return;
      if (report.blocked) {
        FloatingToast.show(context, report.skipped.first, tone: ToastTone.warning);
        return;
      }
      FloatingToast.show(
        context,
        '已应用「${preset.name}」',
        tone: report.skipped.isEmpty ? ToastTone.success : ToastTone.warning,
        detail: report.skipped.isEmpty ? null : '未能恢复：${report.skipped.join('、')}',
      );
      setState(() {});
    });
  }

  Future<void> _update(RunPreset preset) => _guard(() async {
        await _service.updateFromCurrent(preset);
        await _reload();
        if (mounted) FloatingToast.show(context, '已用当前设置更新「${preset.name}」');
      });

  Future<void> _rename(RunPreset preset) async {
    final name = await _askName(title: '重命名预设', initial: preset.name);
    if (name == null || name == preset.name) return;
    await _guard(() async {
      await _service.rename(preset, name);
      await _reload();
    });
  }

  Future<void> _delete(RunPreset preset) async {
    final confirmed = await showConfirmAction(
      context,
      title: '删除预设',
      message: '删除「${preset.name}」？当前会话设置不受影响。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    await _guard(() async {
      await _service.delete(preset.id);
      await _reload();
    });
  }

  Future<String?> _askName({required String title, required String initial}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PresetNameDialog(title: title, initial: initial),
    );
    final name = result?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = _presets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('运行预设', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('保存模型、思考、模式、审批、联网与 Agent 的组合，一键切换',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _saveCurrent,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('保存当前设置为预设'),
          ),
          const SizedBox(height: 8),
          if (presets == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (presets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('还没有预设',
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: presets.length,
                itemBuilder: (context, index) => _tile(presets[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(RunPreset preset) {
    final theme = Theme.of(context);
    final current = _service.matchesCurrent(preset);
    final summary = preset.snapshot.describe();
    return SectionCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        key: ValueKey(preset.id),
        leading: Icon(
          current ? Icons.check_circle_rounded : Icons.tune_rounded,
          color: current ? theme.colorScheme.primary : null,
        ),
        title: Row(children: [
          Flexible(child: Text(preset.name, overflow: TextOverflow.ellipsis)),
          if (current) ...[
            const SizedBox(width: 6),
            Text('当前',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        ]),
        subtitle: Text(
          summary.isEmpty ? '没有保存任何设置' : summary.join(' · '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: _busy ? null : () => _apply(preset),
        trailing: PopupMenuButton<String>(
          tooltip: '更多',
          enabled: !_busy,
          onSelected: (value) => switch (value) {
            'update' => _update(preset),
            'rename' => _rename(preset),
            _ => _delete(preset),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'update', child: Text('用当前设置更新')),
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

/// 命名对话框自己持有输入控制器，退场动画结束、元素卸载时才释放。
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: '例如：深度编码、快速问答'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('确定'),
          ),
        ],
      );
}
