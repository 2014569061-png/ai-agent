import 'package:flutter/material.dart';
import '../motion/motion_preferences.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 全局统一骨架屏动画容器（共享单一低频微光/呼吸脉冲，避免大量独立 Controller）
class NexusLoadingSkeleton extends StatefulWidget {
  final Widget child;

  const NexusLoadingSkeleton({super.key, required this.child});

  @override
  State<NexusLoadingSkeleton> createState() => _NexusLoadingSkeletonState();
}

class _NexusLoadingSkeletonState extends State<NexusLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _opacityAnimation = Tween<double>(begin: 0.45, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionPreferences.shouldReduceMotion(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 基础骨架块（线条/色块）
class NexusSkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const NexusSkeletonLine({
    super.key,
    this.width,
    this.height = 14.0,
    this.borderRadius = AppTokens.radiusControl,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppPalette.darkSurfaceHover : AppPalette.lightSurfaceHover;

    Widget block = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );

    return block;
  }
}

/// 聊天消息骨架（2~4条骨架消息：模拟用户短消息、助手短消息和长消息）
class NexusChatMessageSkeleton extends StatelessWidget {
  const NexusChatMessageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppPalette.darkSurface : AppPalette.lightSurface;

    return NexusLoadingSkeleton(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // 1. 用户提问骨架（靠右）
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 180,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NexusSkeletonLine(width: 140, height: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 2. 助手短回复骨架（靠左）
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 240,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NexusSkeletonLine(width: 200, height: 14),
                  SizedBox(height: 8),
                  NexusSkeletonLine(width: 120, height: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. 助手长回复骨架（靠左，带工具/段落感）
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 310,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NexusSkeletonLine(width: 260, height: 14),
                  SizedBox(height: 8),
                  NexusSkeletonLine(width: 240, height: 14),
                  SizedBox(height: 8),
                  NexusSkeletonLine(width: 170, height: 14),
                  SizedBox(height: 14),
                  NexusSkeletonLine(width: 110, height: 18, borderRadius: AppTokens.radiusPill),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表条目骨架
class NexusListSkeleton extends StatelessWidget {
  final int itemCount;

  const NexusListSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return NexusLoadingSkeleton(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return Container(
            height: AppTokens.kListRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const Row(
              children: [
                NexusSkeletonLine(
                  width: 20,
                  height: 20,
                  borderRadius: AppTokens.radiusPill,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NexusSkeletonLine(width: 160, height: 14),
                      SizedBox(height: 6),
                      NexusSkeletonLine(width: 90, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 卡片骨架
class NexusCardSkeleton extends StatelessWidget {
  final int count;

  const NexusCardSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppPalette.darkSurface : AppPalette.lightSurface;

    return NexusLoadingSkeleton(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NexusSkeletonLine(
                      width: 24,
                      height: 24,
                      borderRadius: AppTokens.radiusControl,
                    ),
                    SizedBox(width: 10),
                    NexusSkeletonLine(width: 120, height: 16),
                  ],
                ),
                SizedBox(height: 12),
                NexusSkeletonLine(width: 260, height: 13),
                SizedBox(height: 6),
                NexusSkeletonLine(width: 180, height: 13),
              ],
            ),
          );
        },
      ),
    );
  }
}
