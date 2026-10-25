import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/desktop_theme.dart';

class QuickAction {
  const QuickAction({this.id = '', required this.label, String? prompt})
      : prompt = prompt ?? label;

  final String id;
  final String label;
  final String prompt;
}

class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({
    super.key,
    this.suggestions = const [],
    this.onSuggestionTap,
    this.hasWorkspace = false,
    this.providerConfigured = false,
    this.keyboardVisible = false,
    this.workspaceLabel,
    this.modelLabel,
    this.onWorkspaceTap,
    this.onModelTap,
    this.onConfigureModel,
    this.onAnalyzeWorkspace,
    this.onCreateAgent,
    this.trailing,
  });

  final List<QuickAction> suggestions;
  final ValueChanged<QuickAction>? onSuggestionTap;
  final bool hasWorkspace;
  final bool providerConfigured;
  final bool keyboardVisible;
  final String? workspaceLabel;
  final String? modelLabel;
  final VoidCallback? onWorkspaceTap;
  final VoidCallback? onModelTap;
  final VoidCallback? onConfigureModel;
  final VoidCallback? onAnalyzeWorkspace;
  final VoidCallback? onCreateAgent;
  final Widget? trailing;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktopWelcome(context);
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = widget.keyboardVisible || constraints.maxHeight < 380;
      final top =
          compact ? 12.0 : (constraints.maxHeight * .32).clamp(48.0, 240.0);
      return Align(
        alignment: compact ? Alignment.center : Alignment.topCenter,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, top, 16, 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!compact) ...[
                Text('N',
                    style: TextStyle(
                        fontSize: 44,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary)),
                const SizedBox(height: 16),
              ],
              Semantics(
                header: true,
                child: Text(
                  '我是 NEXUS，很高兴见到你',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: compact ? 18 : 20,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('有什么可以帮你？',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (!compact) ...[
                const SizedBox(height: 20),
                _welcomeAction(
                    context,
                    '整理一份资料',
                    () => widget.onSuggestionTap?.call(const QuickAction(
                        label: '整理资料', prompt: '请帮我整理资料，先问清我的目标和需要整理的内容。'))),
                _welcomeAction(
                    context,
                    '分析当前项目',
                    widget.hasWorkspace
                        ? widget.onAnalyzeWorkspace
                        : widget.onWorkspaceTap),
              ],
              if (!compact &&
                  !widget.providerConfigured &&
                  widget.onConfigureModel != null) ...[
                const SizedBox(height: 16),
                TextButton(
                    onPressed: widget.onConfigureModel,
                    child: const Text('配置模型')),
              ],
              if (widget.trailing != null) widget.trailing!,
            ]),
          ),
        ),
      );
    });
  }

  Widget _welcomeAction(
      BuildContext context, String label, VoidCallback? onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right_rounded, size: 18),
      ]),
    );
  }

  Widget _desktopWelcome(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DesktopTheme.maybeOf(context)!;
    const actions = [
      (
        icon: Icons.build_outlined,
        label: '修复报错',
        desc: '定位异常堆栈并验证修复',
        prompt: '请帮我定位并修复当前项目的报错，先分析原因，再修改并验证。'
      ),
      (
        icon: Icons.difference_outlined,
        label: '审查改动',
        desc: '检查 Diff 风险与回归测试',
        prompt: '请审查当前项目的代码改动，优先指出真实的错误，并说明验证方法。'
      ),
      (
        icon: Icons.science_outlined,
        label: '运行测试',
        desc: '自动探测入口并报告结果',
        prompt: '请检查当前项目的测试入口，运行合适的测试并报告真实结果。'
      ),
    ];
    void trigger(
        ({IconData icon, String label, String desc, String prompt}) action) {
      if (!widget.providerConfigured) {
        widget.onConfigureModel?.call();
      } else if (!widget.hasWorkspace) {
        widget.onWorkspaceTap?.call();
      } else {
        widget.onSuggestionTap
            ?.call(QuickAction(label: action.label, prompt: action.prompt));
      }
    }

    return Center(
        child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 676),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: colors.selected,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: colors.border)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.auto_awesome_outlined,
                                size: 14, color: colors.accent),
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text(
                                    widget.hasWorkspace
                                        ? 'NEXUS · 项目工作台'
                                        : 'NEXUS · 开始新的工作',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: AppTokens.fontSizeSubcaption,
                                        fontWeight: FontWeight.w500,
                                        color: colors.muted))),
                          ])),
                      const SizedBox(height: 14),
                      Text('把想法，变成下一步。',
                          style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: DesktopTheme.heroSize,
                              letterSpacing: -.6)),
                      const SizedBox(height: 6),
                      Text(
                          widget.hasWorkspace
                              ? '描述目标，让 Agent 帮你修改、执行和验证。'
                              : '选择本地项目，或从左侧继续最近的会话。',
                          style: TextStyle(
                              fontSize: AppTokens.fontSizeBodySmall,
                              height: 1.45,
                              color: colors.muted)),
                      if (!widget.providerConfigured) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                            onPressed: widget.onConfigureModel,
                            icon: const Icon(Icons.settings_outlined, size: 16),
                            label: const Text('配置模型'))
                      ] else if (!widget.hasWorkspace) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                            onPressed: widget.onWorkspaceTap,
                            icon: const Icon(Icons.folder_open_outlined,
                                size: 16),
                            label: const Text('选择项目'))
                      ],
                      if (!widget.keyboardVisible) ...[
                        const SizedBox(height: 22),
                        LayoutBuilder(builder: (context, box) {
                          final useGrid = box.maxWidth >= 500 &&
                              MediaQuery.textScalerOf(context).scale(12) <= 16;
                          if (!useGrid) {
                            return Column(children: [
                              for (final action in actions)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                        decoration: BoxDecoration(
                                            color: colors.panel,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: colors.border)),
                                        child: ListTile(
                                            dense: true,
                                            leading: Icon(action.icon,
                                                size: 16, color: colors.text),
                                            title: Text(action.label),
                                            trailing: Icon(Icons.north_east,
                                                size: 14, color: colors.muted),
                                            onTap: () => trigger(action)))),
                            ]);
                          }
                          return Row(children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(
                                  child: Material(
                                      color: colors.panel,
                                      borderRadius: BorderRadius.circular(12),
                                      child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () => trigger(actions[i]),
                                          child: Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: colors.border)),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      Container(
                                                          width: 28,
                                                          height: 28,
                                                          decoration: BoxDecoration(
                                                              color:
                                                                  colors.panel,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          7),
                                                              border: Border.all(
                                                                  color: colors
                                                                      .border)),
                                                          child: Icon(
                                                              actions[i].icon,
                                                              size: 15,
                                                              color: colors
                                                                  .accent)),
                                                      const Spacer(),
                                                      Icon(
                                                          Icons
                                                              .arrow_outward_rounded,
                                                          size: 14,
                                                          color: colors.muted),
                                                    ]),
                                                    const SizedBox(height: 12),
                                                    Text(actions[i].label,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            fontSize: AppTokens
                                                                .fontSizeBodySmall,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                colors.text)),
                                                    const SizedBox(height: 4),
                                                    Text(actions[i].desc,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            fontSize: AppTokens
                                                                .fontSizeSubcaption,
                                                            color:
                                                                colors.muted)),
                                                  ]))))),
                            ],
                          ]);
                        }),
                        if (widget.trailing != null) widget.trailing!,
                      ],
                    ]))));
  }
}
