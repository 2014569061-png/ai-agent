import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:mobile_agent/presentation/chat/widgets/capsule_top_bar.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/settings/provider_list_page.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/empty_state_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};
  @override
  Future<void> write(
          {required String key,
          required String value,
          required Map<String, String> options}) async =>
      _store[key] = value;
  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _store[key];
  @override
  Future<void> delete(
          {required String key, required Map<String, String> options}) async =>
      _store.remove(key);
  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _store.containsKey(key);
  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      Map.of(_store);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _store.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  group('EmptyStateView regression tests', () {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets(
          'EmptyStateView regular renders without overflow at textScale $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(360, 800))
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: EmptyStateView(
                  icon: Icons.cloud_outlined,
                  title: '暂无数据',
                  message: '这里是一段很长很长的说明文案，用于验证大字号下是否会发生溢出或文字截断现象。',
                  actionLabel: '重试操作',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('暂无数据'), findsOneWidget);
      });

      testWidgets(
          'EmptyStateView compact renders without overflow at textScale $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(360, 800))
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: EmptyStateView.compact(
                  icon: Icons.cloud_outlined,
                  title: '还没有服务商',
                  message: '从上方选择一个服务商开始配置',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('还没有服务商'), findsOneWidget);
      });
    }
  });

  group('ProviderListPage empty state layout tests', () {
    for (final size in [const Size(360, 800), const Size(390, 844)]) {
      testWidgets(
          'ProviderListPage empty state has no overflow at ${size.width}x${size.height} with textScale 1.3',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(size: size).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: const ProviderListPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('模型提供商'), findsOneWidget);
      });
    }
  });

  group('Touch target size regression tests (>= 48x48)', () {
    testWidgets(
        'CapsuleTopBar drawer and new chat buttons have at least 48x48 touch targets',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CapsuleTopBar(
              onMenu: () {},
              onNewChat: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final drawerFinder = find.bySemanticsLabel('打开会话列表');
      final newChatFinder = find.bySemanticsLabel('新建对话');

      expect(drawerFinder, findsOneWidget);
      expect(newChatFinder, findsOneWidget);

      final drawerSize = tester.getSize(drawerFinder);
      final newChatSize = tester.getSize(newChatFinder);

      expect(drawerSize.width, greaterThanOrEqualTo(48.0));
      expect(drawerSize.height, greaterThanOrEqualTo(48.0));
      expect(newChatSize.width, greaterThanOrEqualTo(48.0));
      expect(newChatSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
        'FloatingCapsuleInput attachment and send buttons have at least 48x48 touch targets',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: FloatingCapsuleInput(
              controller: controller,
              isRunning: false,
              onSend: () {},
              onStop: () {},
              onAttachmentMenu: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final attachFinder = find.bySemanticsLabel('添加附件或更多工具');
      expect(attachFinder, findsOneWidget);
      final attachSize = tester.getSize(attachFinder);
      expect(attachSize.width, greaterThanOrEqualTo(48.0));
      expect(attachSize.height, greaterThanOrEqualTo(48.0));

      controller.text = '测试消息';
      await tester.pumpAndSettle();

      final sendFinder = find.bySemanticsLabel('发送');
      expect(sendFinder, findsOneWidget);
      final sendSize = tester.getSize(sendFinder);
      expect(sendSize.width, greaterThanOrEqualTo(48.0));
      expect(sendSize.height, greaterThanOrEqualTo(48.0));
    });
  });
}
