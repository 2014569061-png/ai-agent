import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_status_colors.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_badge.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_pill.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  for (final dark in [false, true]) {
    for (final hc in [false, true]) {
      for (final tone in AppStatusTone.values) {
        testWidgets('shared status pair $tone dark=$dark highContrast=$hc',
            (tester) async {
          late AppStatusColors pair;
          await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(highContrast: hc, disableAnimations: true),
              child: Builder(builder: (context) {
                pair = AppStatusColors.resolve(context, tone);
                return const SizedBox();
              }),
            ),
          ));
          expect(pair.foreground.a, 1);
          expect(pair.background.a, 1);
          expect(contrast(pair.foreground, pair.background),
              greaterThanOrEqualTo(hc ? 7 : 4.5));
        });
      }
      testWidgets('rendered pill and badge pairs dark=$dark highContrast=$hc',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(highContrast: hc, disableAnimations: true),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Wrap(children: [
              for (final state in NexusStatusType.values)
                NexusStatusPill(status: state),
              for (final tone in NexusBadgeTone.values)
                NexusStatusBadge(label: 'badge-$tone', tone: tone),
            ]))),
          ),
        ));
        await tester.pumpAndSettle();
        for (final widgetType in [NexusStatusPill, NexusStatusBadge]) {
          for (final textElement in find
              .descendant(
                of: find.byType(widgetType),
                matching: find.byType(Text),
              )
              .evaluate()) {
            final text = textElement.widget as Text;
            Color? fill;
            textElement.visitAncestorElements((element) {
              final widget = element.widget;
              if (widget is Container && widget.decoration is BoxDecoration) {
                fill = (widget.decoration! as BoxDecoration).color;
                return false;
              }
              return true;
            });
            expect(fill, isNotNull);
            expect(fill!.a, 1);
            expect(contrast(text.style!.color!, fill!),
                greaterThanOrEqualTo(hc ? 7 : 4.5));
          }
        }
        expect(find.text('等待审批'), findsOneWidget);
        expect(find.text('执行失败'), findsOneWidget);
        expect(find.text('已完成'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('business state aliases and custom labels stay unchanged', () {
    for (final value in ['success', 'done', 'completed']) {
      expect(
          NexusStatusPill.fromString(value).status, NexusStatusType.completed);
    }
    expect(NexusStatusPill.fromString('awaiting_approval').status,
        NexusStatusType.waitingApproval);
    expect(NexusStatusPill.fromString('unknown').status, NexusStatusType.draft);
    expect(NexusStatusPill.fromString('error', customLabel: '保持原文').customLabel,
        '保持原文');
  });
}
