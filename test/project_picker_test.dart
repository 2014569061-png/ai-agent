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

class _UnexpectedDirectPicker extends FilePicker {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
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
    FilePicker.platform = _UnexpectedDirectPicker();

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
