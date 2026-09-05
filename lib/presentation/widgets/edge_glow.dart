import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EdgeGlow extends StatelessWidget {
  const EdgeGlow({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCapsule),
        boxShadow: active ? AppTheme.floatingShadow(isDark) : const [],
      ),
      child: child,
    );
  }
}
