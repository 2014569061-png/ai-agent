import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/result_card.dart';
import 'package:mobile_agent/presentation/chat/widgets/result_card_view.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('result states remain readable at 320dp large text dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final status in ResultCardStatus.values) {
        await tester.pumpWidget(MaterialApp(
            theme: MobileTheme.apply(dark ? AppTheme.dark() : AppTheme.light()),
            home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: Scaffold(
                    body: ListView(children: [
                  ResultCardView(
                      card: ResultCard(
                          id: 'test',
                          kind: ResultCardKind.file,
                          resourceType: 'artifact',
                          resourceId: 'long-resource-identifier',
                          resourceVersion: 1,
                          title: '项目分析报告与后续改进建议.md',
                          summary: '已整理项目结构与待处理事项。',
                          status: status),
                      onAction: (_) {},
                      onRefresh: () {})
                ])))));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('资源详情'));
        await tester.pumpAndSettle();
        expect(find.textContaining('long-resource-identifier'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
