import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 把 Override 从主入口移到了 misc.dart。
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/tool_trust_store.dart';
import 'package:mobile_agent/presentation/settings/settings_page.dart';
import 'package:mobile_agent/presentation/settings/tool_list_page.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/presentation/widgets/nexus_switch.dart';

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

  Widget createWidgetUnderTest(Widget child,
      {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('SettingsPage renders phone root with reachable grouped settings',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createWidgetUnderTest(const SettingsPage()));
    await tester.pumpAndSettle();

    // The tab root has a large title and no misleading back action.
    expect(find.text('我的'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);

    // 2. Sections: 服务与数据, 应用, 关于
    expect(find.text('服务与数据'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);

    // 3. Main card entries
    expect(find.text('模型服务'), findsWidgets);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('外观'), findsWidgets);
    expect(find.text('字体大小'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('关于'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('服务协议'), findsOneWidget);
    expect(find.text('帮助与反馈'), findsOneWidget);
    expect(find.text('清除本地凭证'), findsOneWidget);

    // 4. 设置页不再显示底部备案与合规声明块
    expect(find.textContaining('备案号'), findsNothing);
    expect(find.textContaining('内容由 AI 生成'), findsNothing);
  });

  testWidgets('清除本地凭证先展示影响范围与确认操作', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createWidgetUnderTest(const SettingsPage()));
    await tester.pumpAndSettle();

    final clearCredentials = find.text('清除本地凭证');
    await tester.tap(clearCredentials);
    await tester.pumpAndSettle();

    expect(find.text('清除本地凭证？'), findsOneWidget);
    expect(find.textContaining('不会删除聊天记录'), findsOneWidget);
    expect(find.text('清除凭证'), findsOneWidget);
  });

  testWidgets('窄屏大字体下长服务商名称不挤坏设置行', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createWidgetUnderTest(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 800))
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: SettingsPage(
          loadSettings: () async => const SettingsSnapshot(
            activeProvider: ProviderConfig(
              baseUrl: 'https://example.com',
              model: 'demo',
              apiKey: 'test',
              name: '一个很长很长的服务商名称用于检查窄屏布局',
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('模型服务'), findsWidgets);
    expect(tester.takeException(), isNull);
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

    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('模型服务'), findsWidgets);
    await tester.scrollUntilVisible(find.text('语言'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
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

  testWidgets(
      'ToolListPage exposes independent workspace and terminal controls',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(const ToolListPage()));
    await tester.pumpAndSettle();

    expect(find.text('文件读写'), findsOneWidget);
    expect(find.text('终端执行'), findsOneWidget);
    Finder control(String title) => find.descendant(
        of: find.ancestor(
            of: find.text(title), matching: find.byType(SettingsTile)),
        matching: find.byType(NexusSwitch));
    final workspace = control('文件读写');
    final terminal = control('终端执行');
    expect(tester.widget<NexusSwitch>(workspace).value, isTrue);
    expect(tester.widget<NexusSwitch>(terminal).value, isTrue);
    await tester.ensureVisible(workspace);
    await tester.tap(workspace);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.tool.workspace_files'), isFalse);
    expect(tester.widget<NexusSwitch>(terminal).onChanged, isNull);
    expect(tester.widget<NexusSwitch>(terminal).value, isTrue);
    await tester.ensureVisible(workspace);
    await tester.tap(workspace);
    await tester.pumpAndSettle();
    expect(tester.widget<NexusSwitch>(terminal).onChanged, isNotNull);
    await tester.ensureVisible(terminal);
    await tester.tap(terminal);
    await tester.pumpAndSettle();
    expect(prefs.getBool('settings.tool.workspace_files'), isTrue);
    expect(prefs.getBool('settings.tool.terminal'), isFalse);
    await tester.ensureVisible(find.text('自动验证与修复'));
    await tester.tap(find.text('自动验证与修复'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('开发任务完成后自动验证'), 150,
        scrollable: find.byType(Scrollable).first);
    final verification = control('开发任务完成后自动验证');
    expect(tester.widget<NexusSwitch>(verification).onChanged, isNull);
    await tester.scrollUntilVisible(find.text('验证失败后尝试修复'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<NexusSwitch>(control('验证失败后尝试修复')).onChanged, isNull);
  });

  testWidgets('ToolListPage renders filter chips and list of tools',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(const ToolListPage()));
    await tester.pumpAndSettle();

    expect(find.text('受控工具清单'), findsOneWidget);
    await tester.tap(find.textContaining('风险筛选 ·'));
    await tester.pumpAndSettle();
    for (final (key, label) in [
      ('all', '全部'),
      ('safe', '安全 (Safe)'),
      ('requiresConfirmation', '需确认'),
      ('dangerous', '高危'),
      ('sensitive', '敏感工具'),
    ]) {
      final pill = find.byKey(Key('tool-filter-$key'));
      expect(pill, findsOneWidget);
      expect(find.descendant(of: pill, matching: find.text(label)),
          findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('tool-filter-all')));
    await tester.pumpAndSettle();
    // Lazy rows must be scrolled into view rather than assumed to fit the first screen.
    final scrollable = find.byType(Scrollable).first;
    for (final title in ['网页搜索 (Web Search)', '数学计算器 (Calculator)']) {
      await tester.scrollUntilVisible(find.text(title), 200,
          scrollable: scrollable);
      expect(find.text(title), findsOneWidget);
    }
    // 筛选胶囊仍可切换：高危筛选下不再出现安全工具。
    await tester.scrollUntilVisible(find.textContaining('风险筛选 ·'), -160,
        scrollable: scrollable);
    await tester.tap(find.textContaining('风险筛选 ·'));
    await tester.pumpAndSettle();
    final dangerous = find.byKey(const Key('tool-filter-dangerous'));
    await tester.tap(dangerous);
    await tester.pumpAndSettle();
    expect(find.text('数学计算器 (Calculator)'), findsNothing);
  });

  testWidgets('ToolListPage 没有免审批项时明确说明，而不是留一片空白', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(const ToolListPage()));
    await tester.pumpAndSettle();

    expect(find.text('免审批范围'), findsOneWidget);
    expect(find.text('当前没有工具处于免审批状态'), findsOneWidget);
    // 清单为空时不该出现「撤销全部」——没有东西可撤。
    expect(find.text('撤销全部'), findsNothing);
  });

  testWidgets('ToolListPage 列出会话级免审批并可逐个撤销', (tester) async {
    final store = ToolTrustStore();
    await store.init();
    store.allowSession('terminal');

    await tester.pumpWidget(createWidgetUnderTest(
      const ToolListPage(),
      overrides: [toolTrustStoreProvider.overrideWith((ref) async => store)],
    ));
    await tester.pumpAndSettle();

    expect(store.sessionAllowed, contains('terminal'));
    expect(find.text('本会话免审批 · 退出应用后失效'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(store.sessionAllowed, isEmpty);
    expect(find.text('本会话免审批 · 退出应用后失效'), findsNothing);
    expect(find.text('当前没有工具处于免审批状态'), findsOneWidget);
  });

  testWidgets('ToolListPage 列出持久「始终允许」并可撤销', (tester) async {
    final store = ToolTrustStore();
    await store.init();
    await store.allowAlways('edit_file');

    await tester.pumpWidget(createWidgetUnderTest(
      const ToolListPage(),
      overrides: [toolTrustStoreProvider.overrideWith((ref) async => store)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('始终允许 · 重启后仍免审批'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    // 撤销必须同时落到内存与持久化，否则重启后会「复活」。
    expect(store.alwaysAllowed, isEmpty);
    final reloaded = ToolTrustStore();
    await reloaded.init();
    expect(reloaded.alwaysAllowed, isEmpty);
    expect(find.text('始终允许 · 重启后仍免审批'), findsNothing);
  });

  testWidgets('ToolListPage「撤销全部」同时清掉会话级与持久级', (tester) async {
    final store = ToolTrustStore();
    await store.init();
    store.allowSession('terminal');
    await store.allowAlways('edit_file');

    await tester.pumpWidget(createWidgetUnderTest(
      const ToolListPage(),
      overrides: [toolTrustStoreProvider.overrideWith((ref) async => store)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('撤销全部'), findsOneWidget);

    await tester.ensureVisible(find.text('撤销全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销全部'));
    await tester.pumpAndSettle();

    expect(store.sessionAllowed, isEmpty);
    expect(store.alwaysAllowed, isEmpty);
    await tester.scrollUntilVisible(find.text('当前没有工具处于免审批状态'), -200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('当前没有工具处于免审批状态'), findsOneWidget);
  });

  testWidgets('SettingsPage filters items when searching keywords',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createWidgetUnderTest(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'MCP');
    await tester.pumpAndSettle();

    expect(find.text('扩展与环境'), findsOneWidget);
    expect(find.text('账号管理'), findsNothing);
    expect(find.text('语言'), findsNothing);

    await tester.enterText(find.byType(TextField), '模型服务');
    await tester.pumpAndSettle();

    expect(find.text('模型服务'), findsWidgets);
    expect(find.text('未找到相关设置'), findsNothing);

    // Empty result for unknown keyword
    await tester.enterText(find.byType(TextField), '不存在的条目xyz');
    await tester.pumpAndSettle();

    expect(find.text('未找到相关设置'), findsOneWidget);
    expect(find.text('扩展与环境'), findsNothing);
  });
}
