import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../theme/desktop_theme.dart';

/// 会话输入区上方的聊天 / Agent / 计划分段切换控件。
///
/// Plan 模式下首轮只生成分步计划，经用户确认（可编辑）后才执行；
/// 运行中禁止切换，运行结束后再改模式。
class ChatModeSwitcher extends StatelessWidget {
  const ChatModeSwitcher({
    super.key,
    required this.mode,
    required this.running,
    required this.onChanged,
    this.inline = false,
  });

  final bool inline;
  final ChatMode mode;
  final bool running;
  final ValueChanged<ChatMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktop = DesktopTheme.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final outline = desktop?.border ??
        (isDark ? AppPalette.darkHairline : AppPalette.lightHairline);
    final surface =
        desktop?.hover ?? (isDark ? AppPalette.darkSurface : Colors.white);
    final isPlan = mode == ChatMode.plan;
    final enabled = !running;
    return Padding(
      padding: inline
          ? const EdgeInsets.only(right: 6)
          : const EdgeInsets.only(left: 12, right: 12, bottom: 6),
      child: Row(
          mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(desktop != null ? 8 : 999),
                border: Border.all(color: outline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _segment(
                  context,
                  key: const ValueKey('chat-mode-chat'),
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '聊天',
                  selected: mode == ChatMode.chat,
                  onTap: enabled ? () => onChanged(ChatMode.chat) : null,
                ),
                _segment(
                  context,
                  key: const ValueKey('chat-mode-agent'),
                  icon: Icons.smart_toy_outlined,
                  label: 'Agent',
                  selected: mode == ChatMode.agent,
                  onTap: enabled ? () => onChanged(ChatMode.agent) : null,
                ),
                _segment(
                  context,
                  key: const ValueKey('chat-mode-plan'),
                  icon: Icons.checklist_rounded,
                  label: '计划',
                  selected: isPlan,
                  onTap: enabled ? () => onChanged(ChatMode.plan) : null,
                ),
              ]),
            ),
            if (isPlan && !inline) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '计划模式已开启 · 首轮需要确认',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ),
            ],
          ]),
    );
  }

  Widget _segment(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final desktop = DesktopTheme.maybeOf(context);
    final duration =
        DesktopTheme.motionDuration(context, AppTokens.durationFast);
    return Tooltip(
      message: running
          ? '任务运行中，结束后可切换工作模式'
          : key == const ValueKey('chat-mode-plan')
              ? '计划：先生成计划，确认后再执行'
              : key == const ValueKey('chat-mode-agent')
                  ? 'Agent：可使用工具执行任务，遵循当前审批策略'
                  : '聊天：仅进行对话，不使用文件或终端工具',
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label 模式',
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(desktop != null ? 6 : 999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
                horizontal: desktop != null ? 10 : 12,
                vertical: desktop != null ? 4 : 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(desktop != null ? 6 : 999),
              color: selected
                  ? (desktop != null
                      ? desktop.panel
                      : theme.colorScheme.primary.withValues(alpha: 0.14))
                  : Colors.transparent,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 13,
                  color: selected
                      ? (desktop?.text ?? theme.colorScheme.primary)
                      : (desktop?.muted ?? theme.hintColor)),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: desktop != null ? 12 : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? (desktop?.text ?? theme.colorScheme.primary)
                      : (desktop?.muted ?? theme.hintColor),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
