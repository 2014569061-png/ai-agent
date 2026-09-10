import '../theme/app_palette.dart';
import 'package:flutter/material.dart';

/// 非 Web 目标的降级视图。网页仍可通过系统浏览器打开。
class PhonePreviewView extends StatelessWidget {
  const PhonePreviewView({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.lightSurface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.language_rounded,
                  size: 42, color: Colors.blueGrey.shade300),
              const SizedBox(height: 12),
              const Text(
                '当前运行目标不支持内嵌网页',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppPalette.lightTextMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '请点击右上角按钮用系统浏览器打开\n$url',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
