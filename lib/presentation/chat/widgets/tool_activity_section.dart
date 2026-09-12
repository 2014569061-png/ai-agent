import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/chat_controller.dart';
import '../../../domain/tool_result.dart';
import '../../../infrastructure/tools/tool_humanizer.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';

/// G1 工具执行明细悬浮胶囊:收起为底部居中小胶囊,展开为固定高度、内部可滚动
/// 的毛玻璃浮动面板。列表为 ZCode 进程面板式细行(状态图标 + 工具名),点击行
/// 展开参数与输出详情。悬浮于聊天 Stack 顶层,不内联挤压消息流。
class ToolActivityCapsule extends StatefulWidget {
  const ToolActivityCapsule({
    super.key,
    required this.activities,
    required this.running,
  });

  final List<ToolActivity> activities;
  final bool running;

  @override
  State<ToolActivityCapsule> createState() => _ToolActivityCapsuleState();
}

class _ToolActivityCapsuleState extends State<ToolActivityCapsule> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _open ? _panel(context) : _capsule(context),
        ),
      ),
    );
  }

  Widget _capsule(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);
    final summary = _summary;
    return ImmersiveSurface(
      level: ImmersiveMaterialLevel.thin,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _open = true);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.running)
              const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                summary.unknown > 0
                    ? Icons.help_outline_rounded
                    : summary.failed > 0
                        ? Icons.error_outline_rounded
                        : Icons.verified_outlined,
                size: 15,
                color: summary.unknown > 0
                    ? semantic.warning
                    : summary.failed > 0
                        ? theme.colorScheme.error
                        : semantic.success,
              ),
            const SizedBox(width: 4),
            Text(
              widget.running ? _liveSummary : _completedSummary(summary),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final height = (size.height * 0.30).clamp(180.0, 320.0).toDouble();
    return ImmersiveSurface(
      level: ImmersiveMaterialLevel.thin,
      borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  '工具执行明细 (${widget.activities.length})',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _open = false);
                },
              ),
            ]),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: .5)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: widget.activities.length,
              itemBuilder: (context, i) => _row(context, widget.activities[i]),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: .5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${widget.activities.length}'
                ' · 完成 ${widget.activities.where((a) => a.status == '已完成').length}'
                '${runningCount > 0 ? ' · 执行中 $runningCount' : ''}'
                '${pendingCount > 0 ? ' · 待确认 $pendingCount' : ''}',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  int get runningCount =>
      widget.activities.where((a) => a.status == '执行中').length;
  int get pendingCount =>
      widget.activities.where((a) => a.status == '等待确认').length;

  _ToolSummary get _summary => _ToolSummary.from(widget.activities);

  String get _liveSummary {
    final current = widget.activities.lastOrNull;
    if (current == null) return '准备执行';
    return switch (current.status) {
      '等待确认' => '等待确认 ${current.call.name}',
      '执行中' => '正在执行 ${current.call.name}',
      _ => '已完成 ${widget.activities.length} 项工具',
    };
  }

  String _completedSummary(_ToolSummary summary) {
    if (summary.unknown > 0) return '有 ${summary.unknown} 项结果待核验';
    if (summary.failed > 0) return '${summary.failed} 项未完成，查看原因';
    if (summary.applied > 0) return '${summary.applied} 项操作已执行';
    return '${widget.activities.length} 项工具已完成';
  }

  String _actionOf(ToolActivity activity) =>
      const ToolHumanizer().summaryOf(activity.call) ?? '执行一项工具操作';

  String _resultTitle(ToolActivity activity) {
    final action = _actionOf(activity);
    if (activity.status == '执行中') return '正在处理：$action';
    if (activity.status == '等待确认') return '需要你的确认：$action';
    if (activity.effect == ToolEffect.unknown) return '需要核验：$action';
    if (activity.status == '执行失败' || activity.ok == false) {
      return '未完成：$action';
    }
    if (activity.status == '已完成' || activity.ok == true) {
      return '已完成：$action';
    }
    return '准备处理：$action';
  }

  String _resultSubtitle(ToolActivity activity) {
    if (activity.effect == ToolEffect.unknown) {
      return '执行状态无法确认，请先检查目标状态再继续。';
    }
    if (activity.status == '等待确认') return '确认后才会执行此操作。';
    if (activity.status == '执行中') return '正在执行，完成后会在这里显示结果。';
    if (activity.status == '执行失败' || activity.ok == false) {
      return '操作没有完成。展开可查看技术详情。';
    }
    if (activity.status == '已完成' || activity.ok == true) {
      return '操作结果已记录。';
    }
    return '等待开始执行。';
  }

  Widget _row(BuildContext context, ToolActivity a) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);
    final running = a.status == '执行中';
    final done = a.status == '已完成';
    final pending = a.status == '等待确认';
    final failed = a.status == '执行失败';
    final args = a.call.arguments.toString();
    final effect = a.effect;
    final effectLabel = switch (effect) {
      ToolEffect.applied => '已执行',
      ToolEffect.unknown => '待核验',
      ToolEffect.none => '未执行',
      null => null,
    };
    final effectColor = switch (effect) {
      ToolEffect.applied => semantic.success,
      ToolEffect.unknown => semantic.warning,
      ToolEffect.none => semantic.textMuted,
      null => semantic.textMuted,
    };
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          minTileHeight: 40,
          leading: running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
                  done
                      ? Icons.check_circle_outline
                      : failed
                          ? Icons.cancel_outlined
                          : pending
                              ? Icons.error_outline
                              : Icons.radio_button_unchecked,
                  size: 18,
                  color: done
                      ? semantic.success
                      : failed
                          ? theme.colorScheme.error
                          : pending
                              ? semantic.warning
                              : semantic.textMuted,
                ),
          title: Text(_resultTitle(a),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(_resultSubtitle(a),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: semantic.textMuted)),
          trailing: effectLabel != null
              ? Text(effectLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: effectColor, fontWeight: FontWeight.w500))
              : pending
                  ? Text('待确认',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: semantic.warning))
                  : null,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('技术详情',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('工具: ${a.call.name}\n参数: $args',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace')),
            ),
            const SizedBox(height: 4),
            if (a.code != null && a.code!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('结果码: ${a.code}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace', color: effectColor)),
              ),
            if (effect == ToolEffect.unknown)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('结果无法确认，请先检查目标状态再重试。'),
                ),
              ),
            if (a.code != null && a.code!.isNotEmpty) const SizedBox(height: 4),
            if (a.result != null && a.result!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '输出: ${a.result}',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolSummary {
  const _ToolSummary({
    required this.applied,
    required this.unknown,
    required this.failed,
  });

  final int applied;
  final int unknown;
  final int failed;

  factory _ToolSummary.from(Iterable<ToolActivity> activities) {
    var applied = 0;
    var unknown = 0;
    var failed = 0;
    for (final activity in activities) {
      if (activity.effect == ToolEffect.applied) applied++;
      if (activity.effect == ToolEffect.unknown) unknown++;
      if (activity.status == '执行失败') failed++;
    }
    return _ToolSummary(applied: applied, unknown: unknown, failed: failed);
  }
}
