import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/projects/project_picker_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChatController extends ChatController {
  _FakeChatController(this.selectedPath);

  final String selectedPath;
  var pickCalls = 0;
  String? openedProject;

  @override
  ChatState build() => const ChatState(loading: false);

  @override
  Future<String?> pickWorkspace() async {
    pickCalls++;
    return selectedPath;
  }

  @override
  Future<void> openProject(Project project) async {
    openedProject = project.id;
  }
}

/// 守住「目录导入必须走 WorkspaceService 的权限感知流程」：任何直接从
/// `FilePicker` 走捷径的实现都会在这里抛错。
///
/// file_picker 13 的 `FilePicker` 是不可继承的静态外观，注入点改为
/// `FilePickerPlatform.instance`。
class _UnexpectedDirectPicker extends FilePickerPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    throw StateError(
        'ProjectPickerPage bypassed WorkspaceService.pickDirectory');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('template picker presents scannable project choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          chatControllerProvider.overrideWith(() => _FakeChatController('')),
        ],
        child: const MaterialApp(home: ProjectPickerPage()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('添加项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从模板新建'));
    await tester.pumpAndSettle();

    expect(find.text('选择项目模板'), findsOneWidget);
    expect(find.textContaining('自动生成基础文件'), findsOneWidget);
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    expect(find.byIcon(Icons.javascript_rounded), findsOneWidget);
    expect(find.byIcon(Icons.android_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('静态网页'));
    await tester.pumpAndSettle();
    expect(find.text('新建 静态网页'), findsOneWidget);

    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '');
    await tester.pump();
    var createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '创建'),
    );
    expect(createButton.onPressed, isNull);

    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '我的网页');
    await tester.pump();
    createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '创建'),
    );
    expect(createButton.onPressed, isNotNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'selecting a project in the workspace root calls the shell without popping it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final chat = _FakeChatController('');
    addTearDown(db.close);
    final now = DateTime.now();
    await db.insertProject(ProjectsCompanion.insert(
        id: 'root-project',
        name: '手机项目',
        canonicalRootPath: Directory('assets').absolute.path,
        createdAt: now,
        updatedAt: now));
    var selections = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          chatControllerProvider.overrideWith(() => chat),
        ],
        child: MaterialApp(
            home: ProjectPickerPage(onProjectSelected: () => selections++))));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('手机项目'));
    await tester.pumpAndSettle();
    expect(selections, 1);
    expect(chat.openedProject, 'root-project');
    expect(find.byType(ProjectPickerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory import uses the permission-aware workspace flow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory = Directory('assets').absolute;
    final db = AppDatabase(NativeDatabase.memory());
    late _FakeChatController controller;
    FilePickerPlatform.instance = _UnexpectedDirectPicker();

    addTearDown(() async {
      await db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          chatControllerProvider.overrideWith(() {
            controller = _FakeChatController(directory.path);
            return controller;
          }),
        ],
        child: const MaterialApp(home: ProjectPickerPage()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('添加项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入目录'));
    await tester.pump(const Duration(seconds: 1));

    expect(controller.pickCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
