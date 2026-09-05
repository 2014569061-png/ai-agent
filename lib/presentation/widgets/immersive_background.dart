import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ImmersiveBackground extends StatelessWidget {
  const ImmersiveBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBackground : AppTheme.background,
        gradient: RadialGradient(
          center: const Alignment(-.82, -.92),
          radius: 1.25,
          colors: isDark
              ? const [Color(0x263A78FF), Color(0x000B0F19)]
              : const [Color(0x1A7BA8FF), Color(0x00F6F8FB)],
        ),
      ),
      child: child,
    );
  }
}
