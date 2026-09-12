import 'package:flutter/material.dart';

/// 新视觉规范色彩定义（对标 DeepSeek App 极简风格）
/// 全站只保留一个强调色 #4D6BFE
abstract final class AppPalette {
  // 浅色模式语义色
  static const lightCanvas = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF5F7FB);
  static const lightSurfaceHover = Color(0xFFEEF1F8);
  static const lightHairline = Color(0xFFE2E7F1);
  static const lightText = Color(0xFF1A1A1A);
  static const lightTextMuted = Color(0xFF6B7280);
  static const lightTextFaint = Color(0xFF6B7280);

  // 深色模式语义色
  static const darkCanvas = Color(0xFF0F121C);
  static const darkSurface = Color(0xFF181D2A);
  static const darkSurfaceHover = Color(0xFF22283A);
  static const darkHairline = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const darkText = Color(0xFFE6E8EF);
  static const darkTextMuted = Color(0xFFA8B0C4);
  static const darkTextFaint = Color(0xFF8A90A4);

  // 全站强调色及其衍生
  static const brand = Color(0xFF4D6BFE);
  static const brandDecorative = brand;
  static const brandAction = Color(0xFF3A55E5);
  static const lightBrandHover = Color(0xFF3A55E5);
  static const darkBrandHover = Color(0xFF5F7BFF);
  static const lightBrandActive = Color(0xFF2A44CC);
  static const darkBrandActive = Color(0xFF3A55E5);
  static const lightBrandSoft = Color(0xFFEAEEFE);
  static const darkBrandSoft = Color(0xFF1A234A);
  static const lightBrandFaint = Color(0xFFF3F5FE);
  static const darkBrandFaint = Color(0xFF141B38);

  // 别名支持
  static const brandSoftLight = lightBrandSoft;
  static const brandSoftDark = darkBrandSoft;
  static const brandFaintLight = lightBrandFaint;
  static const brandFaintDark = darkBrandFaint;

  /// brandSoft 底上的文字色（chip 选中态、软强调块标题）
  static const brandOnSoft = Color(0xFF2A3EB1);

  // 状态语义色（明暗通用）
  static const success = Color(0xFF2BA471);
  static const warning = Color(0xFFF5A623);
  static const danger = Color(0xFFE5484D);
}
