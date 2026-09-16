import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/share/deep_link_service.dart';
import 'package:mobile_agent/presentation/agents/agents_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系统级入口（长按图标的应用快捷方式 / `nexus://` 深链）的守护。
///
/// 原生 XML（shortcuts.xml）无法在 Flutter 单测里验证，但「深链解析」与
/// 「落到页面后是否真的打开目标入口」这两段可以——而这两段正是最容易改坏的部分：
/// 新增一个 host 忘了在 `_consumeDeepLink` 里消费，症状就是快捷方式点了毫无反应，
/// analyze 完全看不出来。
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

  group('DeepLinkService 解析', () {
    final service = DeepLinkService.instance;

    setUp(service.reset);

    test('nexus://new-agent 置位入口标记，且 drain 是消费型', () {
      service.handleUri(Uri.parse('nexus://new-agent'));

      expect(service.drainNewAgent(), isTrue);
      // 第二次必须为 false：同一次快捷方式不能反复弹窗。
      expect(service.drainNewAgent(), isFalse);
    });

    test('三个入口互不串扰', () {
      service.handleUri(Uri.parse('nexus://memory'));

      expect(service.drainNewAgent(), isFalse);
      expect(service.drainMemory(), isTrue);
      expect(service.drainPrompt(), isNull);
    });

    test('new-chat 仍然按提示词预填，不受新入口影响', () {
      service.handleUri(Uri.parse('nexus://new-chat?prompt=帮我写周报'));

      expect(service.drainPrompt(), '帮我写周报');
      expect(service.drainNewAgent(), isFalse);
    });

    test('非 nexus scheme 一律忽略', () {
      service.handleUri(Uri.parse('https://example.com/new-agent'));

      expect(service.drainNewAgent(), isFalse);
      expect(service.drainPrompt(), isNull);
    });
  });

  group('系统级入口落到页面', () {
    late AppDatabase db;

    setUp(() {
      FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
    });

    Widget wrap(Widget child) => ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: MaterialApp(home: child),
        );

    testWidgets('autoDescribe 进入即弹出描述输入', (tester) async {
      await tester.pumpWidget(wrap(const AgentsPage(autoDescribe: true)));
      await tester.pumpAndSettle();

      expect(find.text('用一句话描述这个智能体'), findsOneWidget);
      expect(find.text('生成草稿'), findsOneWidget);
    });

    testWidgets('默认进入不自动弹窗', (tester) async {
      await tester.pumpWidget(wrap(const AgentsPage()));
      await tester.pumpAndSettle();

      expect(find.text('用一句话描述这个智能体'), findsNothing);
    });
  });
}
