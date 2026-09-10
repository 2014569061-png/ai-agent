import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/brand_mark.dart';

/// 起点建议项。
///
/// 保留类型仅为兼容既有调用点：对标 DeepSeek 的首页不含建议卡，
/// [ChatEmptyState] 已不再渲染这些内容。
@Deprecated('DeepSeek 风格首页不含起点建议卡，参数已忽略')
class QuickAction {
  const QuickAction({
    required this.label,
    String? prompt,
  }) : prompt = prompt ?? label;

  final String label;
  final String prompt;
}

/// 首页空态：品牌 Logo + 一句问候，整体在可用区域内垂直居中。
///
/// 对标 DeepSeek App 首页（图 1）：没有建议卡、没有副标题、没有额外说明，
/// 首屏只有「一个 Logo + 一句话」，把注意力全部让给输入框。
class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({
    super.key,
    @Deprecated('参数已忽略') this.suggestions = const [],
    @Deprecated('参数已忽略') this.onSuggestionTap,
    @Deprecated('参数已忽略') this.hasWorkspace = false,
    @Deprecated('参数已忽略') this.keyboardVisible = false,
  });

  final List<QuickAction> suggestions;
  final ValueChanged<QuickAction>? onSuggestionTap;
  final bool hasWorkspace;
  final bool keyboardVisible;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  /// 每次空态被插入（冷启动 / 新建会话）时重新挑一句，行为对齐 DeepSeek 的随机问候。
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
      '$slot，我能帮什么忙吗？',
      '$slot，想聊点什么？',
      '你好，让我们开始聊天吧',
      '嗨，有什么可以帮你的吗？',
    ];
    return pool[math.Random().nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 品牌 Logo 40px —— 占位与 DeepSeek 鲸鱼图标一致，素材本例替换为自家品牌
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
          ],
        ),
      ),
    );
  }
}
