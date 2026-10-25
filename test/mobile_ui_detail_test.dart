import 'package:flutter/rendering.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';
import 'package:mobile_agent/presentation/widgets/nexus_error_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_search_field.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_badge.dart';

void main() {
  testWidgets('permission descriptions stay readable at large text sizes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const description = '最多自动修复一次，再重跑全部检查。写文件仍遵循审批设置；环境和权限错误不自动修复。';
    await tester.pumpWidget(MaterialApp(
        theme: MobileTheme.apply(AppTheme.light()),
        home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: SettingsTile(
                        title: '验证失败后尝试修复',
                        subtitle: description,
                        wrapText: true,
                        showChevron: false))))));
    await tester.pump();
    expect(
        tester
            .renderObject<RenderParagraph>(find.text(description))
            .didExceedMaxLines,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local error offers recovery and expandable diagnostics',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        theme: MobileTheme.apply(AppTheme.light()),
        home: Scaffold(
            body: NexusErrorNotice(
                title: '未找到网页入口文件',
                message: '请添加 index.html 后重新核对。',
                details: 'FileSystemException: fixture',
                onRetry: () => retries++))));
    expect(find.text('FileSystemException: fixture'), findsNothing);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    await tester.tap(find.text('诊断详情'));
    await tester.pumpAndSettle();
    expect(find.text('FileSystemException: fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search clear affordance follows editing without a page rebuild',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var clears = 0;
    await tester.pumpWidget(MaterialApp(
      theme: MobileTheme.apply(AppTheme.light()),
      home: Scaffold(
        body: NexusSearchField(
          controller: controller,
          hintText: '搜索',
          onChanged: (_) {},
          onClear: () {
            clears++;
            controller.clear();
          },
        ),
      ),
    ));
    expect(find.byTooltip('清空搜索'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final editor = tester.state<EditableTextState>(find.byType(EditableText));
    await tester.enterText(find.byType(TextField), 'project');
    await tester.pump();
    expect(find.byTooltip('清空搜索'), findsOneWidget);
    expect(tester.state<EditableTextState>(find.byType(EditableText)), editor);
    expect(editor.widget.focusNode.hasFocus, isTrue);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(clears, 1);
    expect(find.byTooltip('清空搜索'), findsNothing);
    controller.text = 'external filter';
    await tester.pump();
    expect(find.byTooltip('清空搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long status badges fit large text and retain a 48dp hit target',
      (tester) async {
    var taps = 0;
    const label = '等待核实远程执行结果与文件改动';
    await tester.pumpWidget(MaterialApp(
      theme: MobileTheme.apply(AppTheme.light()),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              child: NexusStatusBadge(label: label, onTap: () => taps++),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final hitRect = tester.getRect(find.byType(InkWell));
    expect(hitRect.height, greaterThanOrEqualTo(48));
    expect(hitRect.width, greaterThanOrEqualTo(48));
    expect(find.byTooltip(label), findsOneWidget);
    await tester.tapAt(hitRect.bottomLeft + const Offset(5, -5));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
