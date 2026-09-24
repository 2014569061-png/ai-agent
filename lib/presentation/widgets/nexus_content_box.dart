import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 全局统一内容宽度约束容器（P1-12）
///
/// 在平板、横屏、大折叠屏展开态下将内容约束在 [maxWidth]（默认 700dp）并水平居中，
/// 避免长列表与表单横向拉伸过度影响阅读与单手操作。
class NexusContentBox extends StatelessWidget {
  const NexusContentBox({
    super.key,
    required this.child,
    this.maxWidth = AppTokens.kContentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
