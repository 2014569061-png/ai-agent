import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../widgets/brand_mark.dart';

class MascotAvatar extends StatelessWidget {
  final String modelName;
  final VoidCallback? onTap;

  const MascotAvatar({super.key, required this.modelName, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: surface,
          shape: BoxShape.circle,
          border: Border.all(color: hairline, width: 1.0),
        ),
        child: const Center(child: BrandMark(size: 18)),
      ),
    );
  }
}
