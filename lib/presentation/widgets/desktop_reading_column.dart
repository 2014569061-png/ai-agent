import 'package:flutter/material.dart';

import '../theme/desktop_theme.dart';

/// Shared reading measure for desktop messages and their composer.
/// Mobile layout is returned unchanged; large text gets a little more room.
class DesktopReadingColumn extends StatelessWidget {
  const DesktopReadingColumn({super.key, required this.child});

  final Widget child;

  static double maxWidthFor(BuildContext context) =>
      880 * (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.25);

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) == null) return child;
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidthFor(context)),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
