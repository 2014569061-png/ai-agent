import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/knowledge_service.dart';
import 'package:mobile_agent/application/mcp_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/mcp/mcp_server_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/widgets/desktop_resource_view.dart';
import 'package:mobile_agent/presentation/agents/agents_page.dart';
import 'package:mobile_agent/presentation/knowledge/knowledge_page.dart';
import 'package:mobile_agent/presentation/memory/memory_page.dart';
import 'package:mobile_agent/presentation/mcp/mcp_servers_page.dart';
import 'package:mobile_agent/presentation/settings/provider_list_page.dart';
import 'package:mobile_agent/presentation/settings/provider_detail_page.dart';
import 'package:mobile_agent/presentation/settings/model_list_page.dart';
import 'package:mobile_agent/presentation/settings/provider_presets.dart';

class _SecureStorage extends FlutterSecureStoragePlatform {
  final _values = <String, String>{};
  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _values[key];
  @override
  Future<void> write(
      {required String key,
      required String value,
      required Map<String, String> options}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(
      {required String key, required Map<String, String> options}) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _values.containsKey(key);
  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      Map.of(_values);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}

void main() {
  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = _SecureStorage();
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });
  Widget host(Widget child, {bool dark = false}) => ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              DesktopTheme.apply(dark ? ThemeData.dark() : ThemeData.light()),
          home: child));
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> seed() async {
    final now = DateTime(2026, 10, 16, 12);
    await db.saveAgent(Agent(
        id: 'review',
        name: '代码审查助手',
        systemPrompt: '检查真实错误，不修改代码。',
        modelProfileId: 'default',
        enabledToolsJson: '[]',
        temperature: .3,
        maxTokens: 2048,
        maxSteps: 8,
        topP: 1,
        updatedAt: now));
    await db.saveAgent(Agent(
        id: 'writer',
        name: '技术写作助手',
        systemPrompt: '组织清晰的说明文档。',
        modelProfileId: 'default',
        enabledToolsJson: '[]',
        temperature: .7,
        maxTokens: 4096,
        maxSteps: 12,
        topP: 1,
        updatedAt: now));
    await KnowledgeService().ingest(
        db: db,
        name: '架构说明.md',
        sourceType: 'file',
        content: '项目采用 Flutter 组件和 Riverpod 状态管理。');
    await KnowledgeService().ingest(
        db: db, name: '发布清单', sourceType: 'paste', content: '发布前检查测试、签名与版本号。');
    for (final manual in [true, false]) {
      await db.saveMemory(Memory(
          id: manual ? 'manual' : 'auto',
          content: manual ? '偏好简洁、可验证的技术说明。' : '主要使用 Flutter 开发桌面应用。',
          category: manual ? '偏好' : '事实',
          sourceConversationId: null,
          sourceType: manual ? 'manual' : 'auto',
          enabled: true,
          importance: manual ? 5 : 2,
          createdAt: now,
          updatedAt: now));
    }
  }

  Future<McpService> mcp() async {
    final service = McpService(database: Future.value(db));
    await service.save(const McpServerConfig(
        id: 'docs',
        name: '文档工具（测试配置）',
        kind: McpServerKind.http,
        url: 'https://example.com/mcp?token=do-not-display',
        enabled: true));
    return service;
  }

  test('endpoint summaries remove user credentials, queries and fragments', () {
    final label = desktopEndpointLabel(
        'https://user:password@example.com:8443/mcp?token=secret#private');
    expect(label, 'https://example.com:8443/mcp');
    expect(desktopEndpointLabel('not a URL'), '未设置有效地址');
  });

  testWidgets(
      'resource search, filters, sort and reset compose without mutating source',
      (tester) async {
    await size(tester, const Size(1100, 850));
    final items = ['Zeta active', 'Alpha active', 'Beta stopped'];
    await tester.pumpWidget(host(DesktopResourceView<String>(
        title: '资源测试',
        description: '本地数据',
        icon: Icons.folder_outlined,
        items: items,
        searchText: (value) => value,
        itemBuilder: (_, value) => Text(value, key: ValueKey(value)),
        emptyTitle: '空',
        emptyMessage: '没有资源',
        filters: [
          DesktopResourceFilter('启用', (value) => value.contains('active'))
        ],
        sorts: [
          DesktopResourceSort('名称 A–Z', (a, b) => a.compareTo(b))
        ])));
    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();
    expect(find.text('Beta stopped'), findsNothing);
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名称 A–Z').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Alpha active')).dy,
        lessThan(tester.getTopLeft(find.text('Zeta active')).dy));
    await tester.enterText(
        find.byKey(const ValueKey('desktop-resource-search')), 'no matches');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的资源'), findsOneWidget);
    await tester.tap(find.text('重置筛选'));
    await tester.pumpAndSettle();
    expect(find.text('Beta stopped'), findsOneWidget);
    expect(items, ['Zeta active', 'Alpha active', 'Beta stopped']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and failure do not masquerade as an empty resource list',
      (tester) async {
    await size(tester, const Size(900, 750));
    Widget view({bool loading = false, Object? error}) =>
        DesktopResourceView<String>(
            title: '读取状态',
            description: '本地数据',
            icon: Icons.folder,
            items: const [],
            searchText: (value) => value,
            itemBuilder: (_, value) => Text(value),
            emptyTitle: '空列表',
            emptyMessage: '没有资源',
            loading: loading,
            error: error,
            onReload: () {});
    await tester.pumpWidget(host(view(loading: true)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('空列表'), findsNothing);
    await tester.pumpWidget(host(view(error: StateError('fixture failure'))));
    await tester.pumpAndSettle();
    expect(find.text('资源读取失败'), findsOneWidget);
    expect(find.text('空列表'), findsNothing);
  });

  testWidgets('resource cards and toolbars scroll at 480px and 2x text',
      (tester) async {
    await size(tester, const Size(480, 720));
    await tester.pumpWidget(host(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: DesktopResourceView<String>(
            title: '窄窗口资源',
            description: '长说明在窄窗口和大字体下自然换行。',
            icon: Icons.folder,
            items: const ['配置'],
            searchText: (value) => value,
            emptyTitle: '空',
            emptyMessage: '没有资源',
            actions: [
              FilledButton(onPressed: () {}, child: const Text('添加资源'))
            ],
            itemBuilder: (_, value) => DesktopResourceCard(
                    title: '可读的长配置名称与状态',
                    icon: Icons.api,
                    metadata: const [
                      '本地配置',
                      '未测试连接'
                    ],
                    actions: [
                      OutlinedButton(
                          onPressed: () {}, child: const Text('编辑配置'))
                    ])))));
    await tester.scrollUntilVisible(find.text('编辑配置'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Agent desktop search reads actual database without granting tools',
      (tester) async {
    await seed();
    await size(tester, const Size(1200, 850));
    await tester.pumpWidget(host(const AgentsPage()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('desktop-resource-search')), '审查');
    await tester.pumpAndSettle();
    expect(find.text('代码审查助手'), findsOneWidget);
    expect(find.text('技术写作助手'), findsNothing);
    expect(
        (await db.allAgents()).every((agent) => agent.enabledToolsJson == '[]'),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('knowledge desktop filters source and preserves stored documents',
      (tester) async {
    await seed();
    await size(tester, const Size(1200, 900));
    await tester.pumpWidget(host(const KnowledgePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '文件导入'));
    await tester.pumpAndSettle();
    expect(find.text('架构说明.md'), findsOneWidget);
    expect(find.text('发布清单'), findsNothing);
    expect(await db.allKnowledgeDocs(), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('memory importance filter and cancelled delete preserve records',
      (tester) async {
    await seed();
    await size(tester, const Size(1200, 900));
    await tester.pumpWidget(host(const MemoryPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '高重要度'));
    await tester.pumpAndSettle();
    expect(find.text('偏好简洁、可验证的技术说明。'), findsOneWidget);
    expect(find.text('主要使用 Flutter 开发桌面应用。'), findsNothing);
    await tester.ensureVisible(find.text('删除'));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await db.allMemories(), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MCP configuration state is not connectivity and toggle persists',
      (tester) async {
    final service = await mcp();
    await size(tester, const Size(1200, 900));
    await tester.pumpWidget(host(McpServersPage(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('已启用配置'), findsOneWidget);
    expect(find.text('尚未测试连接'), findsOneWidget);
    expect(find.textContaining('do-not-display'), findsNothing);
    await tester.ensureVisible(find.text('停用配置'));
    await tester.tap(find.text('停用配置'));
    await tester.pumpAndSettle();
    expect((await service.loadAll()).single.enabled, isFalse);
    expect(find.text('已停用配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'provider desktop hides credentials and separates templates from connections',
      (tester) async {
    await ProviderConfigStore().save(const ProviderConfig(
        id: 'fixture',
        name: '测试服务商',
        baseUrl: 'https://user:password@example.com/v1?token=private',
        model: 'fixture-model',
        apiKey: 'private-key'));
    await size(tester, const Size(1200, 900));
    await tester.pumpWidget(host(const ProviderListPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '已配置'));
    await tester.pumpAndSettle();
    expect(find.text('测试服务商'), findsOneWidget);
    expect(find.text('已填写密钥 · 连接需测试'), findsOneWidget);
    expect(find.textContaining('private-key'), findsNothing);
    expect(find.textContaining('password'), findsNothing);
    expect(find.text('https://example.com/v1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new provider key is described as unsaved until explicit save',
      (tester) async {
    await size(tester, const Size(1200, 900));
    await tester.pumpWidget(host(const ProviderDetailPage()));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'API Key *');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'not-saved-key');
    await tester.pumpAndSettle();
    expect(find.text('已填写；保存后才写入本地安全存储'), findsOneWidget);
    expect(find.text('有尚未保存的更改'), findsOneWidget);
    expect(await ProviderConfigStore().loadAll(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop model selection returns the real ID without saving config',
      (tester) async {
    await size(tester, const Size(1200, 900));
    final preset = providerPresets.first;
    final model = preset.models.first;
    String? selected;
    await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
            body: FilledButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                          builder: (_) => ModelListPage(
                              config: ProviderConfig(
                                  name: '测试服务',
                                  baseUrl: preset.baseUrl,
                                  model: '',
                                  apiKey: '',
                                  type: preset.type),
                              preset: preset)));
                },
                child: const Text('打开模型列表'))))));
    await tester.tap(find.text('打开模型列表'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('desktop-resource-search')), model.id);
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('desktop-model-${model.id}'));
    await tester.ensureVisible(card);
    await tester.tap(find.descendant(of: card, matching: find.text('选择此模型')));
    await tester.pumpAndSettle();
    expect(selected, model.id);
    expect(await ProviderConfigStore().loadAll(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture deep desktop resource pages with isolated fixtures',
      (tester) async {
    await seed();
    final service = await mcp();
    await ProviderConfigStore().save(const ProviderConfig(
        id: 'fixture',
        name: '示例服务商（测试配置）',
        baseUrl: 'https://example.com/v1',
        model: 'fixture-model',
        apiKey: 'fixture-key'));
    await size(tester, const Size(1440, 900));
    await tester.runAsync(() async {
      for (final entry in [
        ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        ),
        ('Inter', 'assets/fonts/Inter-Regular.ttf'),
      ]) {
        final file = File(entry.$2);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          await (FontLoader(entry.$1)
                ..addFont(Future.value(bytes.buffer.asByteData())))
              .load();
        }
      }
    });
    for (final page in <(String, Widget)>[
      ('agents-light', const AgentsPage()),
      ('knowledge-light', const KnowledgePage()),
      ('memory-light', const MemoryPage()),
      ('mcp-dark', McpServersPage(service: service)),
      ('providers-light', const ProviderListPage()),
      ('provider-editor-dark', const ProviderDetailPage()),
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(host(RepaintBoundary(key: key, child: page.$2),
          dark: page.$1.endsWith('dark')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('artifacts/desktop/deep-${page.$1}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
