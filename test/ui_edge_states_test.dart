import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/tasks/development_tasks_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/async_state_view.dart';
import 'package:mobile_agent/presentation/widgets/desktop_resource_view.dart';
import 'package:mobile_agent/presentation/widgets/empty_state_view.dart';
import 'package:mobile_agent/presentation/widgets/nexus_background.dart';
import 'package:mobile_agent/presentation/widgets/nexus_disclosure.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_pill.dart';

class _TaskFixture extends TaskService {
  _TaskFixture(this.rows);
  final List<Task> rows;
  Completer<List<Task>>? pending;
  @override
  Future<List<Task>> allTasks(AppDatabase db, {int limit = 100}) =>
      pending?.future ?? Future.value(rows);
}

Task task(int index, {String status = 'running', String? title}) {
  final now = DateTime(2026, 10, 16, 12);
  return Task(
      id: 'edge-$index',
      conversationId: 'edge-conversation',
      projectId: null,
      stateRevision: 0,
      type: 'development:bug_fix',
      status: status,
      requestJson: jsonEncode({
        'title': title ?? '开发任务 $index',
        'prompt': '检查并修复可复现的问题，保留授权和原有文件。',
        'workspacePath': '/workspace/sample-project'
      }),
      progressJson: '{}',
      resumeCount: 0,
      createdAt: now,
      updatedAt: now);
}

class _StateProbe extends StatefulWidget {
  const _StateProbe();
  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  final scroll = ScrollController();
  var count = 0;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
      controller: scroll,
      itemCount: 100,
      itemBuilder: (_, index) => index == 0
          ? TextButton(
              onPressed: () => setState(() => count++),
              child: Text('增加 $count'))
          : SizedBox(height: 50, child: Text('已加载记录 $index')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
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
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Widget child,
          {double scale = 1, bool desktop = false, bool dark = false}) =>
      MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: desktop
              ? DesktopTheme.apply(dark ? AppTheme.dark() : AppTheme.light())
              : dark
                  ? AppTheme.dark()
                  : AppTheme.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true),
              child: child!),
          home: NexusBackground(child: child));
  Widget tasksHost(_TaskFixture service, {double scale = 1}) {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return ProviderScope(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      taskServiceProvider.overrideWithValue(service)
    ], child: host(const DevelopmentTasksPage(), scale: scale));
  }

  testWidgets(
      'empty state can scroll to its action in short large-text layouts in both themes',
      (tester) async {
    await size(tester, const Size(320, 240));
    var actions = 0;
    for (final dark in [false, true]) {
      await tester.pumpWidget(host(
          Scaffold(
              body: EmptyStateView(
                  icon: Icons.search_off,
                  title: '当前筛选下暂无匹配的任务',
                  message: '尝试修改关键词或清除筛选；其他任务记录仍然保留。',
                  actionLabel: '清除筛选',
                  onAction: () => actions++)),
          scale: 2,
          dark: dark));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('清除筛选'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '清除筛选'));
      expect(button.style!.foregroundColor!.resolve({}),
          AppPalette.brandTextFor(dark));
      await tester.tap(find.text('清除筛选'));
      expect(tester.takeException(), isNull);
    }
    expect(actions, 2);
  });

  testWidgets(
      'running task badges respect reduced motion without changing their status',
      (tester) async {
    for (final reduced in [true, false]) {
      await tester.pumpWidget(host(Scaffold(
          body: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const NexusStatusPill(status: NexusStatusType.running)))));
      await tester.pump();
      expect(find.text('执行中'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator),
          reduced ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('loading state is readable and announced without fake progress',
      (tester) async {
    await size(tester, const Size(320, 120));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(host(
          const Scaffold(
              body: AsyncStateView(loading: true, child: Text('不可提前显示'))),
          scale: 2));
      expect(find.text('正在加载…'), findsOneWidget);
      expect(find.bySemanticsLabel('正在加载内容'), findsOneWidget);
      expect(
          tester
              .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator))
              .value,
          isNull);
      expect(find.text('不可提前显示'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'refresh and partial failure retain element state and list scroll offset',
      (tester) async {
    await size(tester, const Size(390, 640));
    Widget page({bool refresh = false, Object? error}) => host(Scaffold(
        body: AsyncStateView(
            loading: false,
            refreshing: refresh,
            error: error,
            retainContentOnError: true,
            onRetry: () {},
            child: const _StateProbe())));
    await tester.pumpWidget(page());
    await tester.tap(find.text('增加 0'));
    final state = tester.state<_StateProbeState>(find.byType(_StateProbe));
    state.scroll.jumpTo(300);
    await tester.pump();
    for (final config in [
      (true, null),
      (false, 'SocketException: Failed host lookup: example.test'),
      (false, null)
    ]) {
      await tester.pumpWidget(page(refresh: config.$1, error: config.$2));
      await tester.pump();
      expect(identical(tester.state(find.byType(_StateProbe)), state), isTrue);
      expect(state.count, 1);
      expect(state.scroll.offset, closeTo(300, 1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'partial failure is usable at large scale in a very short viewport',
      (tester) async {
    await size(tester, const Size(320, 180));
    var retries = 0;
    await tester.pumpWidget(host(
        Scaffold(
            body: AsyncStateView(
                loading: false,
                error: 'SocketException: Failed host lookup: example.test',
                retainContentOnError: true,
                onRetry: () => retries++,
                child: const Center(child: Text('已有结果仍可查看')))),
        scale: 2));
    await tester.pump();
    expect(find.text('已有结果仍可查看'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('重试'), 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained content also works inside an unbounded outer list',
      (tester) async {
    await size(tester, const Size(390, 640));
    for (final error in [null, '网络连接超时']) {
      await tester.pumpWidget(host(Scaffold(
          body: ListView(children: [
        AsyncStateView(
            loading: false,
            refreshing: error == null,
            error: error,
            retainContentOnError: true,
            child: const SizedBox(height: 80, child: Text('嵌入式内容')))
      ]))));
      await tester.pump();
      expect(find.text('嵌入式内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'fatal error does not misrepresent stale content as a successful load',
      (tester) async {
    await size(tester, const Size(320, 320));
    var retries = 0;
    await tester.pumpWidget(host(
        Scaffold(
            body: AsyncStateView(
                loading: false,
                error: 'SocketException: Failed host lookup: example.test',
                onRetry: () => retries++,
                child: const Text('不能显示为成功'))),
        scale: 2));
    expect(find.text('加载未成功'), findsOneWidget);
    expect(find.text('不能显示为成功'), findsNothing);
    await tester.scrollUntilVisible(find.text('重试'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long technical details have a bounded viewport and copy the complete text',
      (tester) async {
    await size(tester, const Size(390, 640));
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
    final error =
        'SocketException: Failed host lookup: example.test\n${List.generate(400, (i) => 'frame $i').join('\n')}\nlast-diagnostic-line';
    await tester.pumpWidget(host(Scaffold(
        body: AsyncStateView(
            loading: false, error: error, child: const SizedBox()))));
    await tester.tap(find.text('技术诊断详情'));
    await tester.pumpAndSettle();
    final detailsScroll = find.descendant(
        of: find.byType(NexusDisclosure),
        matching: find.byType(SingleChildScrollView));
    expect(tester.getSize(detailsScroll).height, lessThanOrEqualTo(240));
    await tester.ensureVisible(find.byTooltip('复制详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('复制详情'));
    expect(copied, contains('last-diagnostic-line'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'long desktop resource lists stay lazy and can reach the last record',
      (tester) async {
    await size(tester, const Size(1440, 900));
    var built = 0;
    await tester.pumpWidget(host(
        DesktopResourceView<int>(
            title: '长列表验证',
            description: '隔离数据，不调用外部服务',
            icon: Icons.list,
            items: List.generate(1000, (i) => i),
            searchText: (i) => '$i',
            itemBuilder: (_, i) {
              built++;
              return ListTile(title: Text('列表记录 $i'));
            },
            emptyTitle: '暂无记录',
            emptyMessage: '尚未生成测试数据'),
        desktop: true));
    await tester.pumpAndSettle();
    expect(built, lessThan(60));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('列表记录 999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'task filters distinguish zero matches and restore existing tasks at double text scale',
      (tester) async {
    await size(tester, const Size(320, 700));
    final title = '长时间执行的任务仍保留完整状态与可查看的详细结果';
    await tester
        .pumpWidget(tasksHost(_TaskFixture([task(1, title: title)]), scale: 2));
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('失败'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('失败'));
    await tester.pumpAndSettle();
    expect(find.text('当前筛选下暂无任务'), findsOneWidget);
    expect(find.text('暂无开发任务记录'), findsNothing);
    await tester.ensureVisible(find.text('清除筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task refresh failure keeps loaded rows and retry recovers',
      (tester) async {
    await size(tester, const Size(390, 700));
    final service = _TaskFixture([task(1, title: '已加载的开发任务')]);
    await tester.pumpWidget(tasksHost(service));
    await tester.pumpAndSettle();
    service.pending = Completer<List<Task>>();
    await tester.tap(find.byTooltip('刷新任务列表'));
    await tester.pump();
    expect(find.text('已加载的开发任务'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    service.pending!.completeError(StateError('网络连接超时'));
    await tester.pumpAndSettle();
    expect(find.text('已保留上次加载的内容'), findsOneWidget);
    expect(find.text('已加载的开发任务'), findsOneWidget);
    service.pending = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('已保留上次加载的内容'), findsNothing);
    expect(find.text('已加载的开发任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture complex mobile states with isolated content',
      (tester) async {
    await size(tester, const Size(390, 640));
    for (final config in [
      ('empty-dark', true),
      ('retained-error-light', false)
    ]) {
      final key = GlobalKey();
      final body = config.$2
          ? EmptyStateView(
              icon: Icons.search_off_rounded,
              title: '当前筛选下暂无任务',
              message: '其他任务记录仍然保留，可以更换关键词或清除筛选。',
              actionLabel: '清除筛选',
              onAction: () {})
          : AsyncStateView(
              loading: false,
              error: 'SocketException: Failed host lookup: example.test',
              retainContentOnError: true,
              onRetry: () {},
              child: ListView(children: const [
                ListTile(
                    leading: Icon(Icons.schedule),
                    title: Text('文档索引任务'),
                    subtitle: Text('进行中 · 当前显示上次加载的结果')),
                ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text('代码审查任务'),
                    subtitle: Text('等待审批 · 仍需明确授权')),
              ]));
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: host(
              Scaffold(appBar: AppBar(title: const Text('任务状态')), body: body),
              dark: config.$2)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('artifacts/ui-all-pages/edge-${config.$1}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
