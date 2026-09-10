import 'package:flutter/material.dart';

/// 降级为无效果渲染，保留类名与参数以保持向后兼容
class EdgeGlow extends StatelessWidget {
  const EdgeGlow({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
