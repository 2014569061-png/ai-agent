import 'package:flutter/material.dart';

import '../../application/device_action_runner.dart';
import '../theme/app_palette.dart';
import '../widgets/nexus_sheet.dart';

/// 设备动作执行前的确认面板：逐项展示目标、范围、影响、实际执行流程、
/// 是否可撤销与恢复方案。含 Root 或不可撤销动作时需要二次确认。
///
/// 返回 true 表示用户确认执行；false/null 表示放弃。
Future<bool?> showDeviceActionConfirmSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<PreparedDeviceAction> actions,
  String confirmLabel = '确认执行',
}) {
  return showNexusSheet<bool>(
context: context,
isScrollControlled: true,
useSafeArea: true,
showDragHandle: true,
builder: (context) => DeviceActionConfirmSheet(
      title: title,
      subtitle: subtitle,
      actions: actions,
      confirmLabel: confirmLabel,
    ),
);
}

class DeviceActionConfirmSheet extends StatefulWidget {
  const DeviceActionConfirmSheet({
    super.key,
    required this.title,
    required this.actions,
    this.subtitle,
    this.confirmLabel = '确认执行',
  });

  final String title;
  final String? subtitle;
  final List<PreparedDeviceAction> actions;
  final String confirmLabel;

  @override
  State<DeviceActionConfirmSheet> createState() =>
      _DeviceActionConfirmSheetState();
}

class _DeviceActionConfirmSheetState extends State<DeviceActionConfirmSheet> {
  bool _acknowledged = false;

  bool get _hasDanger => widget.actions.any(
        (action) =>
            action.executable &&
            (action.riskClass == 'dangerous' || !action.reversible),
      );

  bool get _hasExecutable => widget.actions.any((action) => action.executable);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canConfirm = _hasExecutable && (!_hasDanger || _acknowledged);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.subtitle!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: widget.actions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _ActionCard(index: index, action: widget.actions[index]),
            ),
          ),
          if (_hasDanger)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CheckboxListTile(
                key: const Key('device-action-ack'),
                value: _acknowledged,
                onChanged: (value) =>
                    setState(() => _acknowledged = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('我已查看上面的命令、路径和影响范围，了解其中包含 Root 或不可撤销的操作'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('device-action-cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('放弃'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('device-action-confirm'),
                    style: _hasDanger
                        ? FilledButton.styleFrom(
                            backgroundColor: AppPalette.danger)
                        : null,
                    onPressed: canConfirm
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(_hasExecutable ? widget.confirmLabel : '没有可执行项'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.index, required this.action});

  final int index;
  final PreparedDeviceAction action;

  String _text(Object? value) {
    if (value is Iterable) return value.map(_text).join('\n');
    if (value is Map) {
      return value.entries.map((e) => '${e.key}: ${_text(e.value)}').join('，');
    }
    return value?.toString() ?? '';
  }

  String _size(Object? bytes) {
    if (bytes is String) return bytes;
    final value = bytes is num ? bytes.toDouble() : 0.0;
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = value;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = action.preview ?? const <String, dynamic>{};
    final danger = action.riskClass == 'dangerous';
    final color = !action.executable
        ? theme.colorScheme.outline
        : danger
            ? AppPalette.danger
            : AppPalette.warning;
    final rows = <(String, String)>[
      if (preview['target'] != null) ('目标', _text(preview['target'])),
      if (preview['scope'] != null) ('范围', _text(preview['scope'])),
      if (preview['impact'] != null) ('影响', _text(preview['impact'])),
      if (preview['command'] != null) ('实际命令', _text(preview['command'])),
      if (preview['executionPlan'] != null)
        ('执行流程', _text(preview['executionPlan'])),
      if (preview['overwriteScope'] != null)
        ('覆盖范围', _text(preview['overwriteScope'])),
      if (preview['fileCount'] != null)
        (
          '文件',
          '${preview['fileCount']} 个，合计 ${_size(preview['totalSize'])}'
              '${(preview['remainingFiles'] ?? 0) is num && (preview['remainingFiles'] as num) > 0 ? '（仅列出前 20 个，另有 ${preview['remainingFiles']} 个）' : ''}',
        ),
      if (preview['files'] is List)
        ('清单', _text((preview['files'] as List).take(20).map(
              (file) => file is Map
                  ? '${file['path'] ?? file['name']}  ${_size(file['bytes'] ?? file['size'])}'
                  : file,
            ))),
      if (action.extra['fileCount'] != null)
        (
          '将删除',
          '${action.extra['fileCount']} 个文件，合计 ${_size(action.extra['totalBytes'])}'
              '${(action.extra['remaining'] as num? ?? 0) > 0 ? '；另有 ${action.extra['remaining']} 个符合条件的文件留待下次' : ''}',
        ),
      if (action.extra['sample'] is List)
        ('前 20 个', _text(action.extra['sample'])),
      if (preview['compatibility'] != null)
        ('兼容性', _text(preview['compatibility'])),
      if (preview['rollback'] != null) ('恢复方案', _text(preview['rollback'])),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                !action.executable
                    ? Icons.block_rounded
                    : danger
                        ? Icons.warning_amber_rounded
                        : Icons.shield_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${index + 1}. ${action.description}',
                    style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (action.executable)
                _Chip(
                  danger ? '危险 · 需二次确认' : '需确认',
                  color,
                ),
              if (action.executable && !action.reversible)
                const _Chip('不可撤销', AppPalette.danger),
              if (action.executable && action.reversible)
                const _Chip('可恢复', AppPalette.success),
              if (!action.executable) _Chip('不会执行', theme.colorScheme.outline),
            ],
          ),
          if (action.error != null) ...[
            const SizedBox(height: 6),
            Text(action.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          for (final (label, value) in rows)
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(label,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    Expanded(
                      child: SelectableText(
                        value,
                        style: label == '实际命令'
                            ? theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace')
                            : theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
