import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:mobile_agent/presentation/l10n/app_strings.dart';
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
      'settings.language': 'system',
    });
  });

  Widget createWidgetUnderTest(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('SettingsPage renders hero header, search and available sections',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createWidgetUnderTest(const SettingsPage()));
    await tester.pumpAndSettle();

    // 1. Hero Header
    expect(find.text(AppStrings.settings), findsOneWidget);
    expect(find.text(AppStrings.settingsHeroSubtitle), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);

    // 2. Search bar
    expect(find.byType(TextField), findsOneWidget);

    // 3. First sections visible on screen
    expect(find.text(AppStrings.llmProviderSection), findsOneWidget);
    expect(find.text(AppStrings.contextExtensionSection), findsOneWidget);

    // Scroll until each section is visible
    final mainScrollable = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.text(AppStrings.toolsSectionTitle),
      200,
      scrollable: mainScrollable,
    );
    expect(find.text(AppStrings.toolsSectionTitle), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(AppStrings.generalSection),
      200,
      scrollable: mainScrollable,
    );
    expect(find.text(AppStrings.generalSection), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(AppStrings.permissionsSection),
      200,
      scrollable: mainScrollable,
    );
    expect(find.text(AppStrings.permissionsSection), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(AppStrings.aboutSection),
      200,
      scrollable: mainScrollable,
    );
    expect(find.text(AppStrings.aboutSection), findsOneWidget);
    expect(find.text(AppStrings.appVersionName), findsNothing);
    expect(find.text(AppStrings.sourceCode), findsNothing);
    expect(find.text(AppStrings.openSourceLicenses), findsNothing);
  });

  testWidgets('SettingsPage search filters items', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(const SettingsPage()));
    await tester.pumpAndSettle();

    // Enter query
    await tester.enterText(find.byType(TextField), 'Linux');
    await tester.pumpAndSettle();

    // Should show search result containing Linux
    expect(find.text('Linux 工具环境'), findsOneWidget);
    expect(find.text(AppStrings.llmProviderSection), findsNothing);
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
