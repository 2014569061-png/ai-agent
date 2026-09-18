import 'package:flutter/widgets.dart';

/// Returns a bounded physical decode width for images displayed in the UI.
///
/// Backgrounds should be decoded for the viewport, not at their original
/// asset dimensions. The cap keeps unusually large screens from turning a
/// decorative image into a large memory allocation.
int imageCacheWidth(
  BuildContext context, {
  double? logicalWidth,
  int maxWidth = 2048,
}) {
  return imageCacheWidthFor(
    logicalWidth: logicalWidth ?? MediaQuery.sizeOf(context).width,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    maxWidth: maxWidth,
  );
}

int imageCacheWidthFor({
  required double logicalWidth,
  required double devicePixelRatio,
  int maxWidth = 2048,
}) {
  final physicalWidth = (logicalWidth * devicePixelRatio).ceil();
  return physicalWidth.clamp(1, maxWidth).toInt();
}
