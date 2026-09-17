import 'package:flutter/material.dart';

/// Groups non-overlapping glass surfaces so Flutter can reuse their backdrop
/// input. Keep overlapping surfaces in different groups; otherwise a shared
/// backdrop key can make one surface appear to filter another.
class GlassSurfaceGroup extends StatelessWidget {
  const GlassSurfaceGroup({super.key, required this.child, this.backdropKey});

  final Widget child;
  final BackdropKey? backdropKey;

  @override
  Widget build(BuildContext context) {
    return BackdropGroup(
      backdropKey: backdropKey,
      child: child,
    );
  }
}
