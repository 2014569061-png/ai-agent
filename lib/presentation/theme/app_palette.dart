import 'package:flutter/material.dart';

/// 新视觉规范色彩定义（对标极简专业工程级风格）
/// 全站统一强调色 #335CFF
abstract final class AppPalette {
  // 浅色模式语义色
  static const lightCanvas = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF7F8FA);
  static const lightSurfaceHover = Color(0xFFEDEFF4);
  static const lightHairline = Color(0xFFE2E7F1);
  static const lightText = Color(0xFF1A1A1A);
  static const lightTextMuted = Color(0xFF6B7280);
  // 浅色模式下次级灰与微弱灰同值（#6B7280）：
  // 白底上为满足 WCAG AA 4.5:1 对比度，灰色亮度上限约为 #767676，
  // #6B7280（4.83:1）已贴近极限，物理上不存在合规的第三档浅灰。
  // 浅色下的第三层级需通过字号与字重（如 11px / 500）承担。
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

  // 浅色状态语义色（WCAG AA 实测达标：danger 5.62:1, success 5.27:1, warning 4.87:1）
  static const lightSuccess = Color(0xFF107C41);
  static const lightWarning = Color(0xFF9A6700);
  static const lightDanger = Color(0xFFC62828);

  // 深色状态语义色（WCAG AA 实测达标：danger 4.78:1, success 5.92:1, warning 9.22:1）
  static const darkSuccess = Color(0xFF2BA471);
  static const darkWarning = Color(0xFFF5A623);
  static const darkDanger = Color(0xFFE5484D);

  // 兼容别名（默认浅色实测达标值）
  static const success = lightSuccess;
  static const warning = lightWarning;
  static const danger = lightDanger;

  // 状态语义背景色（浅色 / 深色）
  static const lightSuccessSoft = Color(0xFFEAF8F1);
  static const darkSuccessSoft = Color(0xFF132B20);
  static const lightWarningSoft = Color(0xFFFEF7EA);
  static const darkWarningSoft = Color(0xFF2E2412);
  static const lightDangerSoft = Color(0xFFFDECEE);
  static const darkDangerSoft = Color(0xFF331518);
}
