import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

import '../../widgets/brand_mark.dart';

class MascotAvatar extends StatelessWidget {
  final String modelName;
  final VoidCallback? onTap;

  const MascotAvatar({super.key, required this.modelName, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.brandBright.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border:
              Border.all(color: AppTheme.brandBright.withValues(alpha: 0.3)),
        ),
        child: const Center(child: BrandMark(size: 22)),
      ),
    );
  }
}
