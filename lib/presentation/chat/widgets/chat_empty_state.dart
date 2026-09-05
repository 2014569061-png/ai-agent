import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/immersive_surface.dart';

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

  /// 文档 3.3 层级颜色 / 6.2 卡片规格。
  static const cardBackground = Color(0xFF131C2B);
  static const cardBorder = Color(0x1AFFFFFF); // 白 10%
  static const brandBlue = Color(0xFF2F81F7);
  static const textPrimary = Color(0xFFF2F5FA);

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
    final cardHeight = shortScreen ? 64.0 : 76.0;

    final greetingText = Text(
      greeting,
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontSize: 34,
        height: 1.2,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.onSurface,
      ),
    );

    final full = Column(
      key: const ValueKey('full'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 首页品牌图标：带有微弱光晕效果（尺寸 72dp）
        SizedBox(height: shortScreen ? 12 : 32),
        SizedBox(
          width: shortScreen ? 72 : 88,
          height: shortScreen ? 72 : 88,
          child: BrandMark(
            size: shortScreen ? 72 : 88,
            withGlow: true,
          ),
        ),
        SizedBox(height: shortScreen ? 24 : 36),
        greetingText,
        SizedBox(height: shortScreen ? 28 : 44),
        ...suggestions.map(
          (text) => Padding(
            padding: EdgeInsets.only(bottom: shortScreen ? 8 : 10),
            child: _QuickActionCard(
              label: text,
              height: cardHeight,
              onTap: () => onSuggestionTap(text),
            ),
          ),
        ),
        if (!hasWorkspace) ...[
          const SizedBox(height: 4),
          Text(
            '解读项目和修复问题会先引导你选择工作区',
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

/// 品牌图标：视觉识别用，不承担点击；光晕控制在图标 1.2~1.4 倍且低透明度。
/// 独立横向快捷操作卡片：圆角 16、图标统一品牌蓝、右侧箭头、按压有亮度反馈。
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.label,
    required this.onTap,
    this.height = 60,
  });

  final String label;
  final VoidCallback onTap;
  final double height;

  IconData get _icon => switch (label) {
        '解读项目' => Icons.account_tree_outlined,
        '修复问题' => Icons.build_outlined,
        '头脑风暴' => Icons.lightbulb_outline_rounded,
        _ => Icons.auto_awesome_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ImmersiveSurface(
      level: ImmersiveMaterialLevel.ultraThick,
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4C8DFF), Color(0xFF9333EA)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4C8DFF).withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(_icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
