import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart' show databaseProvider;
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/diagnostics/operational_metrics_page.dart';
import 'package:mobile_agent/presentation/diagnostics/run_analysis_page.dart';

class MetricsFixtureChatController extends ChatController {
  @override
  ChatState build() => const ChatState();
}

void main() {
  for (final layout in <(double, double, double, Brightness)>[
    (360, 800, 1.6, Brightness.light),
    (360, 800, 2.0, Brightness.light),
    (360, 800, 1.6, Brightness.dark),
    (640, 360, 1.6, Brightness.dark)
  ]) {
    testWidgets(
        'metrics layout ${layout.$1}/${layout.$2}/${layout.$3}/${layout.$4}',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = Size(layout.$1, layout.$2);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: layout.$4),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(layout.$3)),
              child: child!),
          home: OperationalMetricsPage(
              database: () async => db, initialEnvironment: 'fixture')));
      await tester.pumpAndSettle();
      expect(find.text('本地观测，不是发布验收'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('本页参考目标（默认未配置）'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('本页参考目标（默认未配置）'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('应用本页参考目标'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'target validation, explicit application and safe controller disposal',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
        MaterialApp(home: OperationalMetricsPage(database: () async => db)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('本页参考目标（默认未配置）'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('本页参考目标（默认未配置）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '0');
    await tester.enterText(find.byType(TextField).at(2), '1');
    await tester.ensureVisible(find.text('应用本页参考目标'));
    await tester.tap(find.text('应用本页参考目标'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最少样本不得低于20'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '50');
    await tester.enterText(find.byType(TextField).at(2), '20');
    await tester.ensureVisible(find.text('应用本页参考目标'));
    await tester.tap(find.text('应用本页参考目标'));
    await tester.pumpAndSettle();
    expect(find.textContaining('P95 ≤ 50 ms'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('read failures do not become zero metrics or expose error bodies',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: OperationalMetricsPage(
            database: () async => throw StateError('SECRET-database-body'))));
    await tester.pumpAndSettle();
    expect(find.text('指标读取失败，未按0或通过处理。'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    final button = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '复制本机指标报告'));
    expect(button.onPressed, isNull);
  });
  testWidgets(
      'diagnostics navigation keeps the injected database and isolates chat initialization',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(MetricsFixtureChatController.new)
    ], child: const MaterialApp(home: RunAnalysisPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('链路指标与参考SLO'));
    await tester.pumpAndSettle();
    final page = tester
        .widget<OperationalMetricsPage>(find.byType(OperationalMetricsPage));
    expect(identical(await page.database(), db), true);
    Navigator.of(tester.element(find.byType(OperationalMetricsPage))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
