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

  // 全站强调色及其衍生（统一冷靛蓝 #335CFF，天然通过 WCAG AA 对比度）
  static const brand = Color(0xFF335CFF);
  static const brandDecorative = brand;
  static const brandAction = Color(0xFF335CFF);
  static const lightBrandHover = Color(0xFF264CE0);
  static const darkBrandHover = Color(0xFF5376FF);
  static const lightBrandActive = Color(0xFF1E3FB8);
  static const darkBrandActive = Color(0xFF335CFF);
  static const lightBrandSoft = Color(0xFFEEF2FF);
  static const darkBrandSoft = Color(0xFF151E38);
  static const lightBrandFaint = Color(0xFFF5F7FF);
  static const darkBrandFaint = Color(0xFF10172C);

  // 别名支持
  static const brandSoftLight = lightBrandSoft;
  static const brandSoftDark = darkBrandSoft;
  static const brandFaintLight = lightBrandFaint;
  static const brandFaintDark = darkBrandFaint;

  /// brandSoft 底上的文字色（chip 选中态、软强调块标题）
  static const brandOnSoft = Color(0xFF2344D0);

  // 环境光微遮蔽阴影色
  static const lightShadowAmbient = Color(0x0F000000); // rgba(0,0,0,0.06)
  static const darkShadowAmbient = Color(0x66000000); // rgba(0,0,0,0.40)

  // 代码 Diff 语义色
  static const diffAddedBg = Color(0x1F10B981);
  static const diffAddedText = Color(0xFF34D399);
  static const diffRemovedBg = Color(0x1FEF4444);
  static const diffRemovedText = Color(0xFFF87171);

  // 终端与执行卡片语义色
  static const terminalBg = Color(0xFF080C12);
  static const terminalBorder = Color(0xFF1E293B);

  // 思考块（Reasoning）背景与边框
  static const reasoningBgDark = Color(0xFF111722);
  static const reasoningBgLight = Color(0xFFF8FAFC);
  static const reasoningBorderDark = Color(0xFF1E293B);
  static const reasoningBorderLight = Color(0xFFE2E8F0);

  // 状态语义色（明暗通用）
  static const success = Color(0xFF2BA471);
  static const warning = Color(0xFFF5A623);
  static const danger = Color(0xFFE5484D);

  // 状态语义背景色（浅色 / 深色）
  static const lightSuccessSoft = Color(0xFFEAF8F1);
  static const darkSuccessSoft = Color(0xFF132B20);
  static const lightWarningSoft = Color(0xFFFEF7EA);
  static const darkWarningSoft = Color(0xFF2E2412);
  static const lightDangerSoft = Color(0xFFFDECEE);
  static const darkDangerSoft = Color(0xFF331518);
}
