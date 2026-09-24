import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Keeps workspace sheets above the keyboard while preserving their normal
/// three-quarter-screen height when the keyboard is closed.
class WorkspaceSheetFrame extends StatelessWidget {
  const WorkspaceSheetFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final available = math.max(
      0.0,
      media.size.height - keyboard - media.padding.top - AppTokens.sp4,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: math.min(media.size.height * 0.75, available),
        child: child,
      ),
    );
  }
}
