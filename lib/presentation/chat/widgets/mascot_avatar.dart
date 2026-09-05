import 'package:flutter/material.dart';

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
          color: const Color(0xFF1677FF).withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border:
              Border.all(color: const Color(0xFF1677FF).withValues(alpha: 0.3)),
        ),
        child: const Center(child: BrandMark(size: 22)),
      ),
    );
  }
}
