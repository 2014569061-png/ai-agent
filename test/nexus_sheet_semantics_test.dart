import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_sheet.dart';

void main() {
  for (final label in <String?>[null, '关闭项目菜单']) {
    testWidgets('ordinary sheet keeps its correct barrier label: $label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: false,
            accessibleNavigation: false,
          ),
          child: child!,
        ),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showNexusSheet<void>(
                        context: context,
                        barrierLabel: label,
                        builder: (_) =>
                            const SizedBox(height: 120, child: Text('项目选项')),
                      ),
                      child: const Text('打开'),
                    ))),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(label ?? '关闭弹窗'), findsWidgets);
      expect(find.bySemanticsLabel('关闭审批弹窗'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
