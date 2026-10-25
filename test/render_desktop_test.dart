import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/desktop_device_service.dart';
import 'package:mobile_agent/application/desktop_git_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/presentation/navigation/app_shell.dart';
import 'package:mobile_agent/presentation/navigation/desktop_devices_dialog.dart';
import 'package:mobile_agent/presentation/settings/settings_page.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

class _FakeConfigStore extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o',
        apiKey: 'demo',
      );

  @override
  Future<String> readToolKey(String name) async => '';
}

class _PreviewChatController extends ChatController {
  @override
  ChatState build() => const ChatState(
      loading: false,
      providerConfigured: true,
      activeModel: '测试模型',
      currentProjectName: '桌面 UI 验收',
      currentWorkspacePath: 'D:/workspace/ui-preview');

  void showSampleConversation() {
    state = state.copyWith(conversationTitle: '界面验收示例', messages: [
      ChatMessage(
          role: MessageRole.user,
          parts: const [MessagePart.text('请分析工作区布局并提出改进建议。')]),
      ChatMessage(role: MessageRole.assistant, parts: const [
        MessagePart.text('这是隔离的界面测试数据。\n\n已检查导航、输入区和上下文面板。接下来可以选择项目，开始实际工作。')
      ]),
    ]);
  }
}

class _PreviewDevices extends DesktopDevicesController {
  @override
  Future<DesktopDeviceSnapshot> build() async => const DesktopDeviceSnapshot(
        adbPath: 'C:\\Android\\Sdk\\platform-tools\\adb.exe',
        scrcpyPath: 'C:\\tools\\scrcpy\\scrcpy.exe',
        selectedSerial: 'Pixel_8_Pro',
        devices: [
          DesktopDevice('Pixel_8_Pro', 'device', 'Pixel 8 Pro (USB 调试已连接)'),
        ],
      );
}

class _PreviewGit extends DesktopGitService {
  @override
  Future<DesktopGitSnapshot> inspect(String workspace) async =>
      DesktopGitSnapshot(
          root: workspace,
          branch: 'ui/blue-white',
          files: const [DesktopGitFile('app_theme.dart', ' ', 'M')]);

  @override
  Future<String> diff(DesktopGitSnapshot snapshot, DesktopGitFile file,
          {bool staged = false}) async =>
      '--- a/app_theme.dart\n+++ b/app_theme.dart\n@@ -1,3 +1,5 @@\n'
      ' class AppColors {\n-  static const primary = 0xFF23856D;\n'
      '+  static const primary = 0xFF2563EB;\n'
      '+  static const surface = 0xFFFFFFFF;\n'
      '+  static const background = 0xFFF3F6FC;\n }';
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String filePath,
) async {
  // Theme changes can start nested button/text transitions on the next frame.
  await tester.pump(const Duration(milliseconds: 500));
  final renderError = tester.takeException();

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    image.dispose();
  });
  expect(renderError, isNull, reason: filePath);
}

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final fontConfigs = [
      ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
      ('Consolas', 'C:/Windows/Fonts/consola.ttf'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
      ('Inter', 'assets/fonts/Inter-Regular.ttf'),
    ];
    for (final (family, path) in fontConfigs) {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        final loader = FontLoader(family)
          ..addFont(Future.value(bytes.buffer.asByteData()));
        await loader.load();
      }
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'chat.provider_hint_dismissed': true,
    });
  });

  testWidgets('Capture Desktop UI Screenshots for Handoff Verification',
      (tester) async {
    await _loadFonts(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        chatControllerProvider.overrideWith(_PreviewChatController.new),
        providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
        desktopDevicesProvider.overrideWith(_PreviewDevices.new),
        desktopGitServiceProvider.overrideWithValue(_PreviewGit()),
      ],
    );
    addTearDown(container.dispose);

    final darkTheme = DesktopTheme.apply(
        ThemeData(brightness: Brightness.dark, useMaterial3: true));
    final lightTheme = DesktopTheme.apply(
        ThemeData(brightness: Brightness.light, useMaterial3: true));

    final chatController = container.read(chatControllerProvider.notifier)
        as _PreviewChatController;

    // 1. Dark Mode 1440x900 Empty Welcome
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: darkTheme,
            home: RepaintBoundary(key: key, child: const DesktopShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1440x900-dark-empty.png',
      );
    }

    // 2. Light Mode 1440x900 Empty Welcome
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            home: RepaintBoundary(key: key, child: const DesktopShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1440x900-light-empty.png',
      );
    }

    // Isolated fixtures only; visual verification never calls a model API.
    chatController.showSampleConversation();

    // 3. Dark Mode 1440x900 Active Chat
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: darkTheme,
            home: RepaintBoundary(key: key, child: const DesktopShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1440x900-dark-chat.png',
      );
    }

    // 4. Light Mode 1440x900 Active Chat
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            home: RepaintBoundary(key: key, child: const DesktopShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1440x900-light-chat.png',
      );
    }

    // 5. 1280x800 Dark Mode Responsive
    {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: darkTheme,
            home: RepaintBoundary(key: key, child: const DesktopShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1280x800-dark.png',
      );
    }

    // 6. 900x640 Dark Mode (Minimum desktop width, context panel collapses)
    {
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: darkTheme,
            home: RepaintBoundary(key: key, child: const DesktopShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-900x640-dark.png',
      );
    }

    // 7. Text Scale 1.5x at 1440x900
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.5),
              size: Size(1440, 900),
            ),
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              debugShowCheckedModeBanner: false,
              theme: darkTheme,
              home: RepaintBoundary(key: key, child: const DesktopShell()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1440x900-textscale-1.5.png',
      );
    }

    // 8. Text Scale 2.0x at 1440x900
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2.0),
              size: Size(1440, 900),
            ),
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2.0)),
                  child: child!),
              debugShowCheckedModeBanner: false,
              theme: darkTheme,
              home: RepaintBoundary(key: key, child: const DesktopShell()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-1440x900-textscale-2.0.png',
      );
    }

    // 9. Settings Page on Desktop
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: darkTheme,
            home: RepaintBoundary(
              key: key,
              child: const Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-settings-dark.png',
      );
    }

    // 10. Devices Dialog on Desktop
    {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: darkTheme,
            home: RepaintBoundary(
              key: key,
              child:
                  const Scaffold(body: Center(child: DesktopDevicesDialog())),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(
        tester,
        key,
        'artifacts/desktop/desktop-devices-dark.png',
      );
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    expect(tester.takeException(), isNull);
  });
}
