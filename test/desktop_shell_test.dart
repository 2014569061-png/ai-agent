import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/desktop_device_service.dart';
import 'package:mobile_agent/application/desktop_git_service.dart';
import 'package:mobile_agent/application/desktop_workbench_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/navigation/app_shell.dart';
import 'package:mobile_agent/presentation/navigation/desktop_command_center.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'desktop_workspace_interaction_test.dart'
    show
        WorkspaceFixtureChat,
        WorkspaceFixtureDevices,
        WorkspaceFixtureGit,
        WorkspaceFixtureFiles;

void main() {
  test('wide short phone landscape keeps the mobile shell', () {
    expect(DesktopShell.usesDesktopLayoutFor(const Size(914, 411)), isFalse);
    expect(DesktopShell.usesDesktopLayoutFor(const Size(900, 640)), isTrue);
  });

  late ProviderContainer container;
  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'chat.provider_hint_dismissed': true});
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      chatControllerProvider.overrideWith(WorkspaceFixtureChat.new),
      desktopDevicesProvider.overrideWith(WorkspaceFixtureDevices.new),
      desktopGitServiceProvider.overrideWithValue(WorkspaceFixtureGit()),
      desktopWorkspaceFilesProvider.overrideWithValue(WorkspaceFixtureFiles()),
    ]);
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: DesktopTheme.apply(ThemeData.light()),
            home: const DesktopShell())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets(
      'Ctrl+K opens the actual command center and applies review layout',
      (tester) async {
    await show(tester);
    await shortcut(tester, LogicalKeyboardKey.keyK);
    expect(find.byType(DesktopCommandCenter), findsOneWidget);
    final field = find.descendant(
        of: find.byType(DesktopCommandCenter),
        matching: find.byType(TextField));
    await tester.enterText(field, '审查布局');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DesktopCommandCenter), findsNothing);
    expect(find.byKey(const ValueKey('desktop-side-resize')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('desktop.side.open'),
        true);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  });
  testWidgets('new installation starts in focus layout and Ctrl+P opens search',
      (tester) async {
    await show(tester);
    expect(find.byKey(const ValueKey('desktop-side-resize')), findsNothing);
    await shortcut(tester, LogicalKeyboardKey.keyP);
    expect(find.byType(DesktopCommandCenter), findsOneWidget);
    expect(
        tester
            .widget<DesktopCommandCenter>(find.byType(DesktopCommandCenter))
            .actions,
        isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  });
}
