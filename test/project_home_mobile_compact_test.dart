import 'package:mobile_agent/presentation/widgets/nexus_disclosure.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/project_settings.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/presentation/projects/project_home_page.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_list_tile.dart';
import 'package:mobile_agent/presentation/widgets/nexus_background.dart';
import 'package:mobile_agent/presentation/widgets/section_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// All records are in memory and all disk fixtures are inside the ignored
// acceptance subtree. No runtime, model, install or preview command is run.
class _FixtureEnvironment extends EnvironmentService {
  _FixtureEnvironment(this.result, {this.blocked});
  Future<EnvironmentSnapshot> Function() result;
  final String? blocked;
  int calls = 0;

  @override
  Future<EnvironmentSnapshot> inspect({bool force = false}) {
    calls++;
    return result();
  }

  @override
  String? blockedReasonFor({
    required ProjectKind kind,
    ProjectSettings settings = const ProjectSettings(),
    required EnvironmentSnapshot snapshot,
  }) =>
      blocked;
}

class _FixtureChat extends ChatController {
  String? openedProject;
  @override
  ChatState build() => const ChatState(loading: false);
  @override
  Future<void> openProject(Project project) async {
    openedProject = project.id;
  }
}

EnvironmentSnapshot _snapshot() {
  const runtime = LinuxRuntimeInfo(
    kind: LinuxRuntimeKind.hostProcess,
    label: 'Fixture shell',
    available: true,
    detail: 'Test fixture; no command was run',
    supportsInteractive: true,
    supportsShellSyntax: true,
    supportsLiveOutput: true,
  );
  return EnvironmentSnapshot(
    selected: runtime,
    candidates: const [runtime],
    architecture: 'fixture',
    freeBytes: 1000000000,
    checkedAt: DateTime(2026, 10, 18),
    tools: const [],
    templates: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory fixture;
  late _FixtureEnvironment environment;
  late _FixtureChat chat;
  late double previousGlass;
  const directoryKey = ValueKey('project-home-directory');
  const toolsKey = ValueKey('project-home-tools');
  const scrollKey = ValueKey('project-home-overview-scroll');

  setUpAll(() async {
    // Load actual production/fallback families for representative host renders.
    // These files are read only; missing platform fonts remain optional on CI.
    for (final config in [
      ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
      ('PingFang SC', 'C:/Windows/Fonts/msyh.ttc'),
      ('Noto Sans SC', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
      ('Inter', 'assets/fonts/Inter-Regular.ttf'),
    ]) {
      final file = File(config.$2);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        await (FontLoader(config.$1)
              ..addFont(Future.value(bytes.buffer.asByteData())))
            .load();
      }
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousGlass = AppAppearanceController.glassIntensity.value;
    AppAppearanceController.glassIntensity.value = .45;
    final parent = Directory(
      'local/temp/mobile-acceptance-2026-10-17/ui-flutter-project-home/fixtures',
    )..createSync(recursive: true);
    fixture = parent.createTempSync('project-home-');
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 10, 18);
    await db.insertProject(ProjectsCompanion.insert(
      id: 'compact-fixture',
      name: 'Fixture project',
      canonicalRootPath: fixture.absolute.path,
      projectKind: const Value('flutter'),
      createdAt: now,
      updatedAt: now,
    ));
    environment = _FixtureEnvironment(() async => _snapshot());
    chat = _FixtureChat();
  });

  tearDown(() async {
    await db.close();
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    AppAppearanceController.glassIntensity.value = previousGlass;
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool dark = false,
    bool desktop = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var theme = dark ? AppTheme.dark() : AppTheme.light();
    if (desktop) {
      theme = theme.copyWith(extensions: [
        ...theme.extensions.values,
        dark ? DesktopTheme.dark : DesktopTheme.light,
      ]);
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        environmentServiceProvider.overrideWithValue(environment),
        chatControllerProvider.overrideWith(() => chat),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const RepaintBoundary(
          key: ValueKey('project-home-capture'),
          child: NexusBackground(
            child: ProjectHomePage(projectId: 'compact-fixture'),
          ),
        ),
      ),
    ));
    // Directory.list uses real filesystem events, outside the fake test clock.
    // Let those events finish before waiting for animations to settle.
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 100),
        ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> revealSection(WidgetTester tester, String cardKey) async {
    final disclosure = find
        .descendant(
            of: find.byKey(ValueKey(cardKey)),
            matching: find.byType(NexusDisclosure))
        .first;
    await tester.ensureVisible(disclosure);
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
  }

  Future<void> revealTools(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(toolsKey),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(scrollKey),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 25,
    );
    await tester.pumpAndSettle();
    final more = find.text('Git、变更与远程');
    if (more.evaluate().isNotEmpty) {
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
    }
  }

  for (final width in [360.0, 390.0, 411.0]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      for (final dark in [false, true]) {
        testWidgets('mobile $width / $scale / dark=$dark keeps readable layout',
            (tester) async {
          await pumpPage(tester, width: width, scale: scale, dark: dark);
          if (width == 390 && scale == 1) {
            final output = Platform.environment['PROJECT_HOME_CAPTURE_DIR'];
            if (output != null) {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('project-home-capture')),
                );
                final image = await boundary.toImage(pixelRatio: 2);
                try {
                  final bytes =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  final directory = Directory(output)
                    ..createSync(recursive: true);
                  await File(
                          '${directory.path}/project-overview-widget-${dark ? 'dark' : 'light'}.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }
          }
          expect(find.byType(Tab), findsNWidgets(5));
          expect(tester.takeException(), isNull);
          final directory =
              tester.widget<SectionCard>(find.byKey(directoryKey));
          expect(directory.glass, isFalse);
          await revealSection(tester, 'project-home-directory');
          final path = tester.widget<SelectableText>(
            find.byKey(const ValueKey('project-home-path')),
          );
          expect(path.data, fixture.absolute.path);
          expect(path.maxLines, isNull);
          final copySize = tester.getSize(find.byTooltip('复制项目路径'));
          expect(copySize.width, greaterThanOrEqualTo(48));
          expect(copySize.height, greaterThanOrEqualTo(48));
          await revealTools(tester);
          expect(
              tester.widget<SectionCard>(find.byKey(toolsKey)).glass, isFalse);
          final rows = find.descendant(
            of: find.byKey(toolsKey),
            matching: find.byType(NexusListTile),
          );
          expect(rows, findsNWidgets(4));
          for (final row in rows.evaluate()) {
            expect(tester.getSize(find.byWidget(row.widget)).height,
                greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('project details start collapsed and remain accessible',
      (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const ValueKey('project-home-path')), findsNothing);
    expect(find.text('继续开发此项目'), findsOneWidget);
    await revealSection(tester, 'project-home-directory');
    expect(find.byKey(const ValueKey('project-home-path')), findsOneWidget);
    await revealTools(tester);
    expect(find.text('Git'), findsOneWidget);
    expect(find.text('远程执行验证'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps previous card and row policy', (tester) async {
    await pumpPage(tester, width: 1280, desktop: true);
    final directory = tester.widget<SectionCard>(find.byKey(directoryKey));
    expect(directory.glass, isNull);
    expect(directory.borderRadius, isNull);
    expect(directory.padding, const EdgeInsets.all(16));
    await revealTools(tester);
    final rows = find.descendant(
      of: find.byKey(toolsKey),
      matching: find.byType(NexusListTile),
    );
    for (final element in rows.evaluate()) {
      final row = element.widget as NexusListTile;
      expect(row.padding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
      expect(row.showDivider, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('long full path is preserved without fixed height',
      (tester) async {
    final project = (await db.findProject('compact-fixture'))!;
    final longPath =
        '${fixture.absolute.path}/${List.filled(12, 'long-segment').join('/')}';
    await db.saveProject(project.copyWith(canonicalRootPath: longPath));
    await pumpPage(tester, width: 360, scale: 1.6);
    await revealSection(tester, 'project-home-directory');
    expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('project-home-path')),
            )
            .data,
        longPath);
    expect(find.text('目录失效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading environment does not block project shell',
      (tester) async {
    final result = Completer<EnvironmentSnapshot>();
    environment = _FixtureEnvironment(() => result.future);
    await pumpPage(tester, settle: false);
    expect(find.byKey(directoryKey), findsOneWidget);
    expect(find.text('运行环境 · 检查中'), findsOneWidget);
    expect(find.text('继续开发此项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
    result.complete(_snapshot());
    await tester.pumpAndSettle();
    expect(find.text('正在检查本机环境…'), findsNothing);
  });

  testWidgets('environment error and retry remain real service states',
      (tester) async {
    environment = _FixtureEnvironment(
        () => Future.error(StateError('Fixture probe unavailable')));
    await pumpPage(tester, width: 360, scale: 1.6);
    expect(find.text('运行环境 · 检查失败'), findsOneWidget);
    await revealSection(tester, 'project-home-environment');
    expect(find.text('环境检查失败'), findsOneWidget);
    expect(find.textContaining('Fixture probe unavailable'), findsOneWidget);
    environment.result = () async => _snapshot();
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(environment.calls, 2);
    expect(find.text('环境检查失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing capability keeps install entry without executing it',
      (tester) async {
    environment =
        _FixtureEnvironment(() async => _snapshot(), blocked: 'Fixture SDK');
    await pumpPage(tester, width: 360, scale: 1.6);
    expect(find.text('运行环境 · 需要配置'), findsOneWidget);
    await revealSection(tester, 'project-home-environment');
    expect(find.text('缺失能力：Fixture SDK'), findsOneWidget);
    expect(find.text('安装缺失项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five tabs keep their original empty states', (tester) async {
    await pumpPage(tester);
    for (final entry in {
      '文件': '没有可见文件',
      '任务': '还没有任务',
      '产物': '还没有产物',
    }.entries) {
      await tester.tap(find.widgetWithText(Tab, entry.key));
      // Filesystem streams may start only after the project database future
      // resolves. Await the actual empty-state condition, not a busy spinner.
      for (var attempt = 0;
          attempt < 30 && find.text(entry.value).evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(() => Future<void>.delayed(
              const Duration(milliseconds: 20),
            ));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.widgetWithText(Tab, '终端'));
    await tester.pumpAndSettle();
    expect(find.text('远程交互终端'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, '概览'));
    await tester.pumpAndSettle();
    expect(find.byKey(directoryKey), findsOneWidget);
  });

  testWidgets('copy uses complete actual fixture path', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpPage(tester);
    await revealSection(tester, 'project-home-directory');
    await tester.tap(find.byTooltip('复制项目路径'));
    await tester.pump();
    expect(copied, fixture.absolute.path);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('static web delivery does not probe or require a shell runtime',
      (tester) async {
    final project = (await db.findProject('compact-fixture'))!;
    await db.saveProject(project.copyWith(projectKind: 'static-web'));
    await pumpPage(tester);
    expect(environment.calls, 0);
    expect(find.text('运行环境'), findsNothing);
    await revealTools(tester);
    expect(find.byKey(const ValueKey('project-web-delivery')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continue action opens the existing project in chat',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('继续开发此项目'));
    await tester.pumpAndSettle();
    expect(chat.openedProject, 'compact-fixture');
    expect(tester.takeException(), isNull);
  });
}
