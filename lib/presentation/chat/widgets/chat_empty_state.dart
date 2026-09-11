import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/brand_mark.dart';

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
    this.keyboardVisible = false,
    this.workspaceLabel,
    this.modelLabel,
    this.onWorkspaceTap,
    this.onModelTap,
  });

  final List<QuickAction> suggestions;
  final ValueChanged<QuickAction>? onSuggestionTap;
  final bool hasWorkspace;
  final bool keyboardVisible;
  final String? workspaceLabel;
  final String? modelLabel;
  final VoidCallback? onWorkspaceTap;
  final VoidCallback? onModelTap;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  late final String _greeting = _pickGreeting();

  static String _pickGreeting() {
    final hour = DateTime.now().hour;
    final slot = hour < 6
        ? '夜深了'
        : hour < 12
            ? '早上好'
            : hour < 18
                ? '下午好'
                : '晚上好';
    final pool = <String>[
      '$slot，有什么可以帮你的吗？',
      '$slot，想聊点什么？',
      '你好，让我们开始吧',
      '嗨，有什么可以帮你的吗？',
    ];
    return pool[math.Random().nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 40),
            const SizedBox(height: AppTokens.sp6),
            Text(
              _greeting,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: textColor,
              ),
            ),
            if (!widget.keyboardVisible && widget.suggestions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  _StatusPill(
                    icon: Icons.folder_outlined,
                    onTap: widget.onWorkspaceTap,
                    label: widget.hasWorkspace
                        ? widget.workspaceLabel ?? '工作区已选择'
                        : '未选择工作区',
                  ),
                  _StatusPill(
                    icon: Icons.memory_outlined,
                    onTap: widget.onModelTap,
                    label: widget.modelLabel?.isNotEmpty == true
                        ? widget.modelLabel!
                        : '未配置模型',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!widget.hasWorkspace)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '选择工作区后可直接分析代码和运行构建任务',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: textMuted),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...widget.suggestions.take(3).map((action) {
                    return ActionChip(
                      avatar: Icon(
                        action.label.contains('代码')
                            ? Icons.code_rounded
                            : Icons.auto_awesome_rounded,
                        size: 16,
                      ),
                      label: Text(action.label),
                      onPressed: widget.onSuggestionTap == null
                          ? null
                          : () => widget.onSuggestionTap!(action),
                    );
                  }),
                  if (widget.suggestions.length > 3)
                    ActionChip(
                      avatar: const Icon(Icons.more_horiz_rounded, size: 16),
                      label: const Text('更多建议'),
                      onPressed: () =>
                          _showMoreSuggestions(context, widget.suggestions),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMoreSuggestions(
      BuildContext context, List<QuickAction> suggestions) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppPalette.darkSurface
          : AppPalette.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusModal)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '建议任务',
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final action in suggestions)
                  ListTile(
                    leading: Icon(
                      action.label.contains('代码')
                          ? Icons.code_rounded
                          : Icons.auto_awesome_rounded,
                      size: 20,
                    ),
                    title: Text(action.label,
                        style: const TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      widget.onSuggestionTap?.call(action);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 200,
          minHeight: AppTokens.kMinTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
