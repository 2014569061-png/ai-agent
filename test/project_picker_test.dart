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

  @override
  ChatState build() => const ChatState(loading: false);

  @override
  Future<String?> pickWorkspace() async {
    pickCalls++;
    return selectedPath;
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

    await tester.tap(find.text('导入目录'));
    await tester.pump(const Duration(seconds: 1));

    expect(controller.pickCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
