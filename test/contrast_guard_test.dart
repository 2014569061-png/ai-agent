import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';

/// WCAG 2.1 对比度守护测试
///
/// 依据 WCAG 2.1 规范：
/// - AA 级普通文本（< 18pt 或 < 14pt 粗体）最低对比度 ≥ 4.5:1
/// - AA 级大号文本（≥ 18pt 或 ≥ 14pt 粗体）及 UI 控件/图标最低对比度 ≥ 3.0:1
/// - AAA 级普通文本最低对比度 ≥ 7.0:1
void main() {
  group('WCAG Contrast Compliance Tests', () {
    double contrastRatio(Color fg, Color bg) {
      final l1 = fg.computeLuminance();
      final l2 = bg.computeLuminance();
      final lighter = math.max(l1, l2);
      final darker = math.min(l1, l2);
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('Light mode semantic tokens pass WCAG AA on lightCanvas (白底)', () {
      final textRatio = contrastRatio(AppPalette.lightText, AppPalette.lightCanvas);
      expect(textRatio, greaterThanOrEqualTo(4.5), reason: '正文文本需达标 4.5:1');

      final mutedRatio = contrastRatio(AppPalette.lightTextMuted, AppPalette.lightCanvas);
      expect(mutedRatio, greaterThanOrEqualTo(4.5), reason: '次级灰需达标 4.5:1');

      final mutedHoverRatio = contrastRatio(AppPalette.lightTextMuted, AppPalette.lightSurfaceHover);
      expect(mutedHoverRatio, greaterThanOrEqualTo(4.5), reason: '次级灰在悬浮表面需达标 4.5:1');

      final brandRatio = contrastRatio(AppPalette.brand, AppPalette.lightCanvas);
      expect(brandRatio, greaterThanOrEqualTo(4.5), reason: '品牌色在白底需达标 4.5:1');

      final successRatio = contrastRatio(AppPalette.lightSuccess, AppPalette.lightCanvas);
      expect(successRatio, greaterThanOrEqualTo(4.5), reason: '成功色在白底需达标 4.5:1');

      final dangerRatio = contrastRatio(AppPalette.lightDanger, AppPalette.lightCanvas);
      expect(dangerRatio, greaterThanOrEqualTo(4.5), reason: '危险色在白底需达标 4.5:1');

      final warningRatio = contrastRatio(AppPalette.lightWarning, AppPalette.lightCanvas);
      expect(warningRatio, greaterThanOrEqualTo(4.5), reason: '告警色在白底需达标 4.5:1');
    });

    test('Light mode soft background brand text satisfies WCAG AA (≥4.5:1)', () {
      final ratio = contrastRatio(AppPalette.brandOnSoft, AppPalette.lightBrandSoft);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'brandOnSoft 在 lightBrandSoft 底上需达标 4.5:1');
    });

    test('Dark mode soft background brand text satisfies WCAG AA (≥4.5:1)', () {
      final ratio = contrastRatio(AppPalette.darkBrandText, AppPalette.darkBrandSoft);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'darkBrandText 在 darkBrandSoft 底上需达标 4.5:1');
    });

    test('Dark mode semantic tokens pass WCAG AA on darkCanvas (深色底)', () {
      final textRatio = contrastRatio(AppPalette.darkText, AppPalette.darkCanvas);
      expect(textRatio, greaterThanOrEqualTo(4.5), reason: '深色正文需达标 4.5:1');

      final mutedRatio = contrastRatio(AppPalette.darkTextMuted, AppPalette.darkCanvas);
      expect(mutedRatio, greaterThanOrEqualTo(4.5), reason: '深色次级文本需达标 4.5:1');

      final brandHoverRatio = contrastRatio(AppPalette.darkBrandHover, AppPalette.darkCanvas);
      expect(brandHoverRatio, greaterThanOrEqualTo(4.5), reason: '深色高亮品牌需达标 4.5:1');

      final darkBrandSurfaceRatio = contrastRatio(AppPalette.darkBrandText, AppPalette.darkSurface);
      expect(darkBrandSurfaceRatio, greaterThanOrEqualTo(4.5), reason: '深色品牌前景色在深色表面需达标 4.5:1');

      final darkBrandCanvasRatio = contrastRatio(AppPalette.darkBrandText, AppPalette.darkCanvas);
      expect(darkBrandCanvasRatio, greaterThanOrEqualTo(4.5), reason: '深色品牌前景色在深色画布需达标 4.5:1');

      final successRatio = contrastRatio(AppPalette.darkSuccess, AppPalette.darkCanvas);
      expect(successRatio, greaterThanOrEqualTo(4.5), reason: '深色成功色需达标 4.5:1');

      final dangerRatio = contrastRatio(AppPalette.darkDanger, AppPalette.darkCanvas);
      expect(dangerRatio, greaterThanOrEqualTo(4.5), reason: '深色危险色需达标 4.5:1');

      final warningRatio = contrastRatio(AppPalette.darkWarning, AppPalette.darkCanvas);
      expect(warningRatio, greaterThanOrEqualTo(4.5), reason: '深色告警色需达标 4.5:1');
    });

    test('Terminal palette foreground passes contrast on terminalSurface and terminalBg', () {
      final textOnBg = contrastRatio(AppPalette.terminalText, AppPalette.terminalBg);
      expect(textOnBg, greaterThanOrEqualTo(7.0), reason: '终端正文在黑底达到 AAA 级');

      final textOnSurface = contrastRatio(AppPalette.terminalText, AppPalette.terminalSurface);
      expect(textOnSurface, greaterThanOrEqualTo(4.5), reason: '终端正文在表面色达到 AA 级');

      final mutedOnSurface = contrastRatio(AppPalette.terminalTextMuted, AppPalette.terminalSurface);
      expect(mutedOnSurface, greaterThanOrEqualTo(4.5), reason: '终端次级文本达到 AA 级');
    });
  });
}
