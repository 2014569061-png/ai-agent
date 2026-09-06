import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_tokens.dart';
import 'package:mobile_agent/presentation/widgets/immersive_surface.dart';
import 'package:mobile_agent/presentation/widgets/section_card.dart';
import 'package:mobile_agent/presentation/widgets/section_header.dart';
import 'package:mobile_agent/presentation/widgets/immersive_list_tile.dart';

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

  test('theme shape presets are applied to core Material components', () {
    final light = AppTheme.light();
    expect(light.cardTheme.shape, isNotNull);
    expect(light.inputDecorationTheme.border, isNotNull);
    // P0.2 起弹层表面由 ImmersiveSurface 提供：dialogTheme 透明化、bottomSheetTheme 已删除。
    expect(light.dialogTheme.backgroundColor, Colors.transparent);
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
                ImmersiveListTile(
                  title: '测试设置',
                  subtitle: '统一沉浸列表行',
                  icon: Icons.tune,
                ),
                ImmersiveSurface(child: Text('测试浮层')),
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
