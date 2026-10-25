import 'package:flutter/material.dart';
import '../theme/desktop_theme.dart';
import '../theme/mobile_theme.dart';

/// Page-level reading measure. Existing scroll views, padding, state and
/// bottom actions remain owned by each page; terminal/editor canvases opt out.
class NexusPageLayout extends StatelessWidget {
  const NexusPageLayout(
      {super.key,
      required this.child,
      this.desktopMaxWidth = 1240,
      this.mobileMaxWidth = 760});
  final Widget child;
  final double desktopMaxWidth, mobileMaxWidth;

  @override
  Widget build(BuildContext context) {
    final maxWidth = DesktopTheme.maybeOf(context) == null
        ? mobileMaxWidth
        : desktopMaxWidth;
    final content = SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
    return DesktopTheme.maybeOf(context) == null
        ? MobileCanvas(child: content)
        : content;
  }
}
