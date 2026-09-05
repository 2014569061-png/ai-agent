import 'package:flutter/material.dart';

import 'immersive_surface.dart';
import '../theme/app_tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard(
      {super.key, required this.child, this.margin = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return ImmersiveSurface(
      margin: margin,
      level: ImmersiveMaterialLevel.regular,
      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      child: child,
    );
  }
}
