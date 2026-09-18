import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_tokens.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/widgets/nexus_surface.dart';
import 'package:mobile_agent/presentation/widgets/section_card.dart';
import 'package:mobile_agent/presentation/widgets/section_header.dart';
import 'package:mobile_agent/presentation/widgets/nexus_list_tile.dart';

void main() {
  test('semantic colors and motion tokens exist for both themes', () {
    expect(AppTheme.lightSemantic.canvas, AppTheme.background);
    expect(AppTheme.darkSemantic.canvas, AppTheme.darkBackground);
    expect(AppTheme.lightSemantic.chatUser, isNotNull);
    expect(AppTheme.darkSemantic.chatAssistant, isNotNull);
    expect(AppTokens.durationBase.inMilliseconds, greaterThan(0));
    expect(AppTokens.durationModal.inMilliseconds,
        greaterThan(AppTokens.durationFast.inMilliseconds));
  });

  test('default glass policy favors a light effect on mobile targets', () {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    expect(
      AppAppearanceController.defaultGlassIntensity,
      isMobile ? 0.45 : 0.8,
    );
  });

  test('theme shape presets are applied to core Material components', () {
    final light = AppTheme.light();
    expect(light.cardTheme.shape, isNotNull);
    expect(light.inputDecorationTheme.border, isNotNull);
    final lightBorder =
        (light.inputDecorationTheme.enabledBorder as OutlineInputBorder)
            .borderSide;
    final darkBorder = (AppTheme.dark().inputDecorationTheme.enabledBorder
            as OutlineInputBorder)
        .borderSide;
    expect(lightBorder.color, AppPalette.lightTextMuted);
    expect(darkBorder.color, AppPalette.darkTextFaint);
    expect(lightBorder.width, 1.0);
    expect(darkBorder.width, 1.0);
    // 弹层表面由 NexusSurface 提供：showNexusSheet 与 showNexusDialog
    // 两个包装器内部都会把 dialogTheme 局部覆盖为透明与零高度。
    // 全局值保留 canvas 色，作为裸 showDialog(AlertDialog) 的兜底，
    // 否则漏改的调用点会渲染出透明（看不见）的弹窗。
    expect(light.dialogTheme.backgroundColor, AppTheme.background);
    expect(light.dialogTheme.titleTextStyle, isNotNull);
    expect(light.navigationBarTheme.height, 68);
  });

  testWidgets('immersive core widgets render in light and dark themes',
      (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SectionHeader(title: '测试分组'),
                SectionCard(child: Text('测试卡片')),
                NexusListTile(
                  title: '测试设置',
                  subtitle: '统一沉浸列表行',
                  icon: Icons.tune,
                ),
                NexusSurface(child: Text('测试浮层')),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('测试分组'), findsOneWidget);
      expect(find.text('测试卡片'), findsOneWidget);
      expect(find.text('测试设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
