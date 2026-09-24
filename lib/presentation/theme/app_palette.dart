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
  static const lightTextMuted = Color(0xFF5F6672);
  // 浅色模式下次级灰收紧为 #5F6672（在 lightSurfaceHover 上满足 WCAG AA 5.03:1）
  // 微弱灰保持 #6B7280 用于 ≥13px/500 的第三层级文字
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
  // 品牌色 #335CFF 在浅色下天然通过 WCAG AA (5.10:1)；
  // 深色模式前景色使用专用的 darkBrandText (#7C97FF, 6.19:1)。
  static const brand = Color(0xFF335CFF);
  static const brandDecorative = brand;
  static const brandAction = brand;
  static const lightBrandHover = Color(0xFF264CE0);
  static const darkBrandHover = Color(0xFF5376FF);
  static const lightBrandActive = Color(0xFF1E3FB8);
  static const darkBrandActive = brand;
  static const lightBrandSoft = Color(0xFFEEF2FF);
  static const darkBrandSoft = Color(0xFF151E38);
  static const lightBrandFaint = Color(0xFFF5F7FF);
  static const darkBrandFaint = Color(0xFF10172C);

  /// 深色模式专用品牌文本/图标前景色（符合 WCAG AA ≥4.5:1，在深色表面 6.19:1）
  static const darkBrandText = Color(0xFF7C97FF);

  /// 根据深浅模式返回合规的品牌文字/前景色
  static Color brandTextFor(bool isDark) =>
      isDark ? darkBrandText : brandAction;

  /// 根据上下文环境返回合规的品牌文字/前景色
  static Color brandText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBrandText
          : brandAction;

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
  static const terminalSurface = Color(0xFF101622);
  static const terminalSurfaceHover = Color(0xFF182030);
  static const terminalHeaderBg = Color(0xFF0F141F);
  static const terminalText = Color(0xFFE2E8F0);
  static const terminalTextMuted = Color(0xFF94A3B8);

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

/// 统一代码语法高亮色系定义（支持自适应深浅模式）
abstract final class AppSyntaxPalette {
  // 浅色模式语法高亮色
  static const lightKeyword = Color(0xFFA626A4);
  static const lightString = Color(0xFF50A14F);
  static const lightComment = Color(0xFF9DA0A6);
  static const lightNumber = Color(0xFF986801);

  // 深色模式语法高亮色 (One Dark 配色规范)
  static const darkKeyword = Color(0xFFC678DD);
  static const darkString = Color(0xFF98C379);
  static const darkComment = Color(0xFF5C6773);
  static const darkNumber = Color(0xFFD19A66);
}
