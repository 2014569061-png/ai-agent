import 'package:flutter/material.dart';

import '../../../application/chat_controller.dart';
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
    return ImmersiveSurface(
      level: ImmersiveMaterialLevel.thin,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => setState(() => _open = true),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.running)
              const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.handyman_rounded,
                  size: 14, color: theme.colorScheme.onSurface),
            const SizedBox(width: 4),
            Text(
              '工具 ${widget.activities.length}',
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
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => setState(() => _open = false),
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

  Widget _row(BuildContext context, ToolActivity a) {
    final theme = Theme.of(context);
    final running = a.status == '执行中';
    final done = a.status == '已完成';
    final pending = a.status == '等待确认';
    final args = a.call.arguments.toString();
    final argsBrief = args.length > 48 ? '${args.substring(0, 48)}…' : args;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
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
                    : pending
                        ? Icons.error_outline
                        : Icons.radio_button_unchecked,
                size: 18,
                color: done
                    ? Colors.green
                    : pending
                        ? Colors.orange
                        : theme.hintColor,
              ),
        title: Text(a.call.name,
            style:
                theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
        subtitle: Text(argsBrief,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        trailing: pending
            ? Text('待确认',
                style:
                    theme.textTheme.labelSmall?.copyWith(color: Colors.orange))
            : null,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('参数: $args',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace')),
          ),
          const SizedBox(height: 4),
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
    );
  }
}
