import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:mobile_agent/presentation/settings/settings_page.dart';
import 'package:mobile_agent/presentation/settings/tool_list_page.dart';
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
    SharedPreferences.setMockInitialValues({
      'settings.llm.deep_reasoning': true,
      'settings.tool.web_browsing': true,
      'settings.tool.device_direct': true,
      'settings.tool.sensitive_read': false,
      'settings.tool.sensitive_action': false,
      'settings.tool.terminal_file': true,
      'settings.language': 'zh',
      'settings.font_scale': 1.0,
    });
  });

  Widget createWidgetUnderTest(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('SettingsPage renders minimalist DeepSeek layout and cards',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createWidgetUnderTest(const SettingsPage()));
    await tester.pumpAndSettle();

    // 1. Top bar: back button & centered title
    expect(find.text('设置'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    // 2. Sections: 账户, 应用, 关于
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    // 3. Main card entries
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('服务协议'), findsOneWidget);
    expect(find.text('帮助与反馈'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);

    // 4. 设置页不再显示底部备案与合规声明块
    expect(find.textContaining('备案号'), findsNothing);
    expect(find.textContaining('内容由 AI 生成'), findsNothing);
  });

  testWidgets('SettingsPage exposes loading state while settings are loading',
      (tester) async {
    final loading = Completer<SettingsSnapshot>();
    await tester.pumpWidget(
      createWidgetUnderTest(
        SettingsPage(loadSettings: () => loading.future),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loading.complete(const SettingsSnapshot.empty());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'SettingsPage shows an empty provider state without hiding actions',
      (tester) async {
    await tester.pumpWidget(
      createWidgetUnderTest(
        SettingsPage(loadSettings: () async => const SettingsSnapshot.empty()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未配置服务商'), findsOneWidget);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
  });

  testWidgets('SettingsPage exposes a retryable error state', (tester) async {
    await tester.pumpWidget(
      createWidgetUnderTest(
        SettingsPage(
          loadSettings: () async => throw StateError('settings unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('加载未成功'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('ToolListPage renders filter chips and list of tools',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(const ToolListPage()));
    await tester.pumpAndSettle();

    expect(find.text('受控工具清单'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '安全 (Safe)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '需确认'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '高危'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '敏感工具'), findsOneWidget);

    // Should find web search and http request
    expect(find.text('网页搜索 (Web Search)'), findsOneWidget);
    expect(find.text('数学计算器 (Calculator)'), findsOneWidget);
  });
}
