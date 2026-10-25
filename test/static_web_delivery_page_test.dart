import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/artifact_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/projects/static_web_delivery_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture, workspace;
  late AppDatabase db;
  late ArtifactService artifacts;
  late PathProviderPlatform previousPaths;
  setUp(() {
    final parent = Directory('local/temp/web-delivery-widget-tests')
      ..createSync(recursive: true);
    fixture = parent.createTempSync('case-');
    workspace = Directory(p.join(fixture.path, 'website'))..createSync();
    File(p.join(workspace.path, 'index.html'))
        .writeAsStringSync('<h1>原始网页</h1>');
    File(p.join(workspace.path, 'styles.css'))
        .writeAsStringSync('h1 { color: blue; }');
    artifacts = ArtifactService(
        rootDirectory: () async =>
            Directory(p.join(fixture.path, 'artifacts')));
    db = AppDatabase(NativeDatabase.memory());
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FixturePaths(fixture.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await db.close();
    await fixture.delete(recursive: true);
  });

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    var completed = false;
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (ready() &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          completed = true;
          return;
        }
      }
    });
    expect(completed, isTrue, reason: 'Bounded fixture I/O did not complete');
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester,
      {double width = 360,
      double height = 800,
      double scale = 1.6,
      bool dark = false}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: StaticWebDeliveryPage(
                projectId: 'fixture-project',
                workspacePath: workspace.path,
                projectName: '我的手机网页',
                artifacts: artifacts))));
    await waitFor(tester, () => find.text('index.html').evaluate().isNotEmpty);
  }

  for (final state in [
    (360.0, 800.0, 1.6, false),
    (360.0, 800.0, 2.0, false),
    (360.0, 800.0, 1.6, true),
    (640.0, 360.0, 1.6, true)
  ]) {
    testWidgets('delivery is usable at $state', (tester) async {
      await show(tester,
          width: state.$1, height: state.$2, scale: state.$3, dark: state.$4);
      expect(find.byKey(const ValueKey('web-open-preview')), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const ValueKey('web-save-delivery')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'edit, review, save and retain an immutable ZIP through production services',
      (tester) async {
    await show(tester, scale: 1);
    await tester.ensureVisible(find.text('index.html'));
    await tester.tap(find.text('index.html'));
    await waitFor(tester, () => find.byType(TextField).evaluate().length == 2);
    await tester.enterText(find.byType(TextField).last, '<h1>手机修改完成</h1>');
    await tester.pump();
    await tester.tap(find.byTooltip('保存修改'));
    await waitFor(
        tester,
        () =>
            find.byTooltip('文件已保存').evaluate().isNotEmpty &&
            File(p.join(workspace.path, 'index.html'))
                .readAsStringSync()
                .contains('手机修改完成'));
    // The editor's success toast owns a finite three-second timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await waitFor(
        tester,
        () =>
            find
                .byKey(const ValueKey('web-save-delivery'))
                .evaluate()
                .isNotEmpty &&
            tester
                    .widget<FilledButton>(
                        find.byKey(const ValueKey('web-save-delivery')))
                    .onPressed !=
                null);
    await tester.ensureVisible(find.byKey(const ValueKey('web-save-delivery')));
    await tester.tap(find.byKey(const ValueKey('web-save-delivery')));
    await waitFor(
        tester, () => find.text('网页 ZIP 副本已保存到成果中心').evaluate().isNotEmpty);
    await tester.runAsync(() async {
      final saved = await artifacts.list(db, projectId: 'fixture-project');
      expect(saved, hasLength(1));
      final payload = await artifacts.verifiedPayload(saved.single);
      final before = await payload.readAsBytes();
      final zip = ZipDecoder().decodeBytes(before);
      expect(zip.files.map((file) => file.name), ['index.html', 'styles.css']);
      expect(utf8.decode(zip.files.first.content), '<h1>手机修改完成</h1>');
      await File(p.join(workspace.path, 'index.html'))
          .writeAsString('later source edit');
      expect(
          await (await artifacts.verifiedPayload(saved.single)).readAsBytes(),
          before);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an edit after review cannot silently publish and refresh recovers',
      (tester) async {
    await show(tester, scale: 1);
    File(p.join(workspace.path, 'styles.css'))
        .writeAsStringSync('changed after review');
    await tester.ensureVisible(find.byKey(const ValueKey('web-save-delivery')));
    await tester.tap(find.byKey(const ValueKey('web-save-delivery')));
    await waitFor(
        tester, () => find.textContaining('文件已变化').evaluate().isNotEmpty);
    await tester
        .runAsync(() async => expect(await artifacts.list(db), isEmpty));
    await tester.ensureVisible(find.text('刷新文件核对'));
    await tester.tap(find.text('刷新文件核对'));
    await waitFor(
        tester,
        () =>
            find.textContaining('文件已变化').evaluate().isEmpty &&
            tester
                    .widget<FilledButton>(
                        find.byKey(const ValueKey('web-save-delivery')))
                    .onPressed !=
                null);
    await tester.ensureVisible(find.byKey(const ValueKey('web-save-delivery')));
    await tester.tap(find.byKey(const ValueKey('web-save-delivery')));
    await waitFor(
        tester, () => find.text('网页 ZIP 副本已保存到成果中心').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
