import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/project_service.dart';
import 'package:mobile_agent/application/project_settings.dart';
import 'package:mobile_agent/application/project_template_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/motion/nexus_page_route_factory.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/confirm_action.dart';
import 'package:mobile_agent/presentation/projects/storage_access_flow.dart';
import 'package:mobile_agent/presentation/widgets/glass_surface.dart';
import 'package:mobile_agent/presentation/widgets/nexus_background.dart';
import 'package:mobile_agent/presentation/widgets/nexus_sheet.dart';
import 'package:mobile_agent/presentation/widgets/nexus_surface.dart';

/// 三个线上缺陷的回归测试。
///
/// 1. 「从模板新建」弹出占满整屏的白底对话框。
/// 2. 导入本地目录时报「目录不可写」，导入无法完成。
/// 3. 页面切换瞬间两层画面重叠并掉帧。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- Bug 1

  group('Bug1 对话框不应撑满整屏', () {
    Future<void> openDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNexusDialog<String>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('新建 静态网页'),
                      content: const TextField(
                        autofocus: true,
                        decoration: InputDecoration(labelText: '项目名称'),
                      ),
                      actions: [
                        TextButton(onPressed: () {}, child: const Text('取消')),
                        FilledButton(onPressed: () {}, child: const Text('创建')),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    for (final (label, intensity) in const [
      ('平面档', 0.0),
      ('磨砂档', 0.45),
      ('液态档', 0.85),
    ]) {
      testWidgets('$label：AlertDialog 外不再套会撑满的玻璃外壳', (tester) async {
        AppAppearanceController.glassIntensity.value = intensity;
        addTearDown(() => AppAppearanceController.glassIntensity.value = 0.8);

        await openDialog(tester);

        // 对话框仍然渲染出来了。
        expect(find.text('新建 静态网页'), findsOneWidget);

        // 关键回归点：AlertDialog 内部走的是 Dialog，其布局根是一个一定会撑满
        // 可用空间的 Align。只要有人再把 AlertDialog 包进有可见背景的外壳，
        // 外壳就会被顶成整屏——这里把这条约束钉死。
        expect(
          find.byType(GlassSurface),
          findsNothing,
          reason: '对话框不应再被 GlassSurface 外壳包裹（会被撑成整屏）',
        );
        expect(
          find.byType(NexusSurface),
          findsNothing,
          reason: '对话框不应再被 NexusSurface 外壳包裹（会被撑成整屏）',
        );

        // 卡片本身要紧凑：内容只有标题 + 一个输入框 + 两个按钮。
        // 修复前可见面板被 Dialog 的 Align 顶成 344.7×794.9（屏高 - 56），
        // 修复后应为 280×201 左右。
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final card = tester.getRect(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
                matchRoot: false,
              )
              .first,
        );
        expect(
          card.height,
          lessThan(screen.height * 0.45),
          reason: '卡片高度应由内容决定，不该接近整屏',
        );
        expect(
          card.width,
          lessThan(screen.width * 0.9),
          reason: '卡片宽度应按内容收缩，不该占满屏幕宽度',
        );
      });
    }

    testWidgets('裸内容（selfContained: false）仍拿到卡片背景，且外壳贴合内容',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // 先固定到平面档：外壳的实现随强度档切换，这里只要确认它存在且贴合内容。
      AppAppearanceController.glassIntensity.value = 0.0;
      addTearDown(() => AppAppearanceController.glassIntensity.value = 0.8);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNexusDialog<void>(
                    context: context,
                    selfContained: false,
                    builder: (_) => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('用一句话描述这个智能体')],
                      ),
                    ),
                  ),
                  child: const Text('open-bare'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-bare'));
      await tester.pumpAndSettle();

      expect(find.text('用一句话描述这个智能体'), findsOneWidget);
      // 裸内容没有 Dialog 外壳，外壳尺寸就是内容尺寸——不能撑满。
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final shells = find.byType(NexusSurface).evaluate().toList();
      expect(shells, isNotEmpty, reason: '裸内容必须由外壳提供卡片背景');
      final shellRect = tester.getRect(find.byType(NexusSurface).first);
      expect(shellRect.height, lessThan(screen.height * 0.4));
      expect(shellRect.width, lessThan(screen.width * 0.9));
    });

    testWidgets('含 Expanded 的确认框仍然正常渲染（外壳移除不能破坏它）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showConfirmAction(
                    context,
                    title: '删除项目',
                    message: '这个操作不可撤销。',
                    bulletItems: const ['会删除工作区文件', '会清除会话绑定'],
                  ),
                  child: const Text('open-confirm'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-confirm'));
      await tester.pumpAndSettle();

      expect(find.text('删除项目'), findsOneWidget);
      expect(find.text('这个操作不可撤销。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------- Bug 2

  group('Bug2 目录导入不再被写入探测闸住', () {
    late Directory temp;
    late AppDatabase db;
    late ProjectService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('nexus-bugfix-');
      db = AppDatabase(NativeDatabase.memory());
      service = ProjectService(db: db);
    });

    tearDown(() async {
      await db.close();
      if (temp.existsSync()) {
        await temp.delete(recursive: true);
      }
    });

    test('目录只读时仍然完成导入，并把可写性记为 false', () async {
      final directory = Directory(p.join(temp.path, 'readonly'));
      await directory.create();
      await File(p.join(directory.path, 'index.html')).writeAsString('<html/>');
      // 用同名目录占位，让写入探测必然失败（文件无法覆盖目录）。
      // 这精确模拟 Android 分区存储下「可读、不可写」的授权目录。
      await Directory(p.join(directory.path, '.nexus-write-probe')).create();

      final project = await service.importDirectory(
        ImportDirectoryRequest(directoryPath: directory.path, name: 'readonly'),
      );

      expect(project.canonicalRootPath, contains('readonly'));
      expect(await service.list(), hasLength(1));
      expect(
        ProjectSettings.decode(project.settingsJson).directoryWritable,
        isFalse,
        reason: '写入探测失败必须被记录下来，供界面提示用户补权限',
      );
    });

    test('目录可写时导入后标记为可写', () async {
      final directory = Directory(p.join(temp.path, 'writable'));
      await directory.create();
      final project = await service.importDirectory(
        ImportDirectoryRequest(directoryPath: directory.path, name: 'writable'),
      );
      expect(
        ProjectSettings.decode(project.settingsJson).directoryWritable,
        isTrue,
      );
    });

    test('目录不存在时仍然明确报错', () async {
      expect(
        () => service.importDirectory(
          ImportDirectoryRequest(directoryPath: p.join(temp.path, 'nope')),
        ),
        throwsA(isA<ProjectException>()),
      );
    });

    test('可写性字段的序列化兼容旧记录', () {
      expect(const ProjectSettings().directoryWritable, isTrue);
      expect(ProjectSettings.decode('{}').directoryWritable, isTrue);
      expect(
        ProjectSettings.decode('{"directoryWritable":false}').directoryWritable,
        isFalse,
      );
      expect(
        const ProjectSettings(directoryWritable: false)
            .copyWith(goal: 'x')
            .directoryWritable,
        isFalse,
        reason: 'copyWith 不能把只读状态重置回可写',
      );
    });
  });

  // ---------------------------------------------------------------- Bug 3

  group('Bug3 页面转场不应出现两层画面重叠', () {
    testWidgets('进入方向：下层路由停止绘制，本页仍然绘制', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      );

      final route = NexusPageRoute.workspace(
        builder: (_) => const Scaffold(body: Center(child: Text('detail'))),
      );
      navigatorKey.currentState!.push(route);

      // 转场进行中取样：这是「两个画面重叠」出现的时间窗口。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        route.overlayEntries.first.opaque,
        isTrue,
        reason: '进入方向必须让下层路由立刻停止绘制；'
            '否则两层页面会画在同一个 backdrop 上，玻璃面板还会采样到下层文字',
      );
      expect(
        route.overlayEntries.last.opaque,
        isFalse,
        reason: '本页自身必须保持绘制，否则新页面根本看不见',
      );

      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('反转方向：同样压制下层，避免返回首帧重光栅化整棵下层页面',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      );

      final route = NexusPageRoute.detail(
        builder: (_) => const Scaffold(body: Center(child: Text('detail'))),
      );
      navigatorKey.currentState!.push(route);
      await tester.pumpAndSettle();
      expect(route.overlayEntries.first.opaque, isTrue);

      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        route.overlayEntries.first.opaque,
        isTrue,
        reason: '返回期间也必须压住下层。下层在整个 push 期间没被绘制过，'
            '第一帧恢复就要重新光栅化整棵页面（聊天页 = 全屏背景图 + 消息列表 + '
            '两处玻璃面板），而这一帧还压着上层退出动画的绘制，必然掉帧。'
            '视觉上下层本来就不可见：上层自带不透明画布底，位移只有 8~16dp。',
      );

      await tester.pumpAndSettle();
      // 反向保护：压制只属于「转场期间」，不能把下层永久冻住。
      expect(find.text('home'), findsOneWidget);
      expect(find.text('detail'), findsNothing);
    });

    testWidgets('页面自带不透明画布底，转场期间物理遮挡下层', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      );

      final route = NexusPageRoute.workspace(
        builder: (_) => const Scaffold(body: Center(child: Text('detail'))),
      );
      navigatorKey.currentState!.push(route);

      // 转场进行中就必须带上不透明底。只靠「让下层停止绘制」是不够的：
      // pop 时下层必须继续绘制（否则下层会到转场结束才出现），
      // 那时页面若没有自己的底，两层内容一定同框。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byType(NexusBackground),
        findsOneWidget,
        reason: '新页面在转场第一帧就该有不透明画布底',
      );

      await tester.pumpAndSettle();
      expect(find.byType(NexusBackground), findsOneWidget);
    });
  });

  // --------------------------------------------------- 导入目录的授权引导

  group('导入目录的授权引导', () {
    testWidgets('非 Android 平台直接放行，不弹引导框', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      // 桌面 / Web 不需要 MANAGE_EXTERNAL_STORAGE，不该打断用户。
      expect(await ensureAllFilesAccess(capturedContext), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
