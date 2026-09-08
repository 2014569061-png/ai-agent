import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/brand_mark.dart';

/// 对话页空态：品牌图标 + 动态问候语 + 三个独立快捷操作卡片。
/// 键盘弹出时收敛为仅问候语（文档 9），短屏压缩间距并缩小品牌图标。
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({
    super.key,
    required this.suggestions,
    required this.onSuggestionTap,
    this.hasWorkspace = false,
    this.keyboardVisible = false,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSuggestionTap;
  final bool hasWorkspace;

  /// 键盘弹出时隐藏品牌图标与快捷卡片，仅保留问候语（文档 9）。
  final bool keyboardVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.semanticOf(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了，想先做点什么？'
        : hour < 12
            ? '早上好，想先做点什么？'
            : hour < 18
                ? '下午好，想先做点什么？'
                : '晚上好，想先做点什么？';

    final shortScreen = MediaQuery.sizeOf(context).height < 620;

    final greetingText = Text(
      greeting,
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontSize: 22,
        height: 1.2,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
      ),
    );

    final full = Column(
      key: const ValueKey('full'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: shortScreen ? 12 : 24),
        const SizedBox(
          width: 56,
          height: 56,
          child: BrandMark(
            size: 56,
            withGlow: true,
          ),
        ),
        SizedBox(height: shortScreen ? 16 : 24),
        greetingText,
        const SizedBox(height: 8),
        Text(
          '直接输入需求，或试试这些',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            color: colors.textMuted,
          ),
        ),
        SizedBox(height: shortScreen ? 20 : 32),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 44,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final text = suggestions[index];
            return _SuggestionChip(
              label: text,
              onTap: () => onSuggestionTap(text),
            );
          },
        ),
        if (!hasWorkspace) ...[
          const SizedBox(height: 16),
          Text(
            '解读和修复等操作会先引导你选择工作区',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    );

    final compact = Column(
      key: const ValueKey('compact'),
      mainAxisSize: MainAxisSize.min,
      children: [greetingText],
    );

    // 页面进入动效（文档 10：180~240ms）：淡入 + 轻微上移。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, shortScreen ? 8 : 24, 24, shortScreen ? 12 : 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                        CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                );
              },
              child: keyboardVisible ? compact : full,
            ),
          ),
        ),
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  IconData get _icon => switch (label) {
        '解读项目' => Icons.account_tree_outlined,
        '修复问题' => Icons.build_outlined,
        '头脑风暴' => Icons.lightbulb_outline_rounded,
        '解读工作区' => Icons.description_outlined,
        _ => Icons.auto_awesome_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);

    return Material(
      color: semantic.surfaceTint,
      borderRadius: BorderRadius.circular(AppTokens.radiusCapsule),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppTokens.radiusCapsule),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCapsule),
            border: Border.all(
              color: semantic.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_icon, size: 18, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
