import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/plan_panel.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_approval_sheet.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A11y Compliance Tests', () {
    testWidgets('SettingsDivider is wrapped in ExcludeSemantics',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SettingsDivider(),
          ),
        ),
      );

      final excludeSemanticsFinder = find.descendant(
        of: find.byType(SettingsDivider),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludeSemanticsFinder, findsOneWidget);

      final dividerFinder = find.descendant(
        of: excludeSemanticsFinder,
        matching: find.byType(Divider),
      );
      expect(dividerFinder, findsOneWidget);
    });

    testWidgets('PlanPanel buttons satisfy >= 48dp touch constraints',
        (tester) async {
      const plan = PlanState(
        steps: [
          PlanStep(id: 's1', description: '步骤 1', status: 'pending'),
        ],
        status: 'draft',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PlanPanel(
              plan: plan,
              onApprove: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final iconButtons =
          tester.widgetList<IconButton>(find.byType(IconButton));
      expect(iconButtons.isNotEmpty, isTrue);

      for (final btn in iconButtons) {
        expect(btn.constraints?.minWidth, greaterThanOrEqualTo(48.0));
        expect(btn.constraints?.minHeight, greaterThanOrEqualTo(48.0));
      }
    });

    testWidgets('ToolApprovalSheet semantics compliance', (tester) async {
      const call = ToolCall(
        id: 'call-1',
        name: 'run_shell',
        arguments: {'CommandLine': 'ls -la'},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ToolApprovalSheet(
              call: call,
              risk: ToolRisk.dangerous,
            ),
          ),
        ),
      );

      await tester.pump();

      // Risk header has Semantics with non-empty label
      final headerSemantics = find.descendant(
        of: find.byType(ToolApprovalSheet),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label?.isNotEmpty ?? false),
        ),
      );
      expect(headerSemantics, findsWidgets);

      // Decorative icons are wrapped in ExcludeSemantics
      final excludedIcons = find.descendant(
        of: find.byType(ToolApprovalSheet),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludedIcons, findsWidgets);
    });
  });
}
