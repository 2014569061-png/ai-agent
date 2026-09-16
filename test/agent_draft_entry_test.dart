import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/agent_draft.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/agents/agent_editor_page.dart';
import 'package:mobile_agent/presentation/agents/agents_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「对话式创建 Agent」的入口与预填守护。
///
/// 这一层的问题 analyze 抓不到（编译期完全合法）：入口卡片没接上路由、弹窗打不开、
/// 草稿没真的预填进编辑器，都只在 pump 之后才暴露。项目此前也吃过「页面在、入口断」
/// 的亏（见 CHANGELOG 中三个孤儿页的说明），所以新入口同样要留冒烟守护。
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

  Future<void> seedAgent(String name) async {
    final now = DateTime.now();
    await db.saveAgent(Agent(
      id: 'agent-$name',
      name: name,
      systemPrompt: '系统提示词',
      modelProfileId: 'default',
      enabledToolsJson: '[]',
      temperature: 0.7,
      maxTokens: 1024,
      maxSteps: 4,
      topP: 1.0,
      updatedAt: now,
    ));
  }

  group('AgentsPage 描述生成入口', () {
    testWidgets('空库时把描述生成作为首要动作', (tester) async {
      await tester.pumpWidget(wrap(const AgentsPage()));
      await tester.pumpAndSettle();

      expect(find.text('还没有 Agent'), findsOneWidget);
      expect(find.text('描述目标，让 AI 生成'), findsOneWidget);
    });

    testWidgets('已有 Agent 时列表首项仍是描述生成入口', (tester) async {
      await seedAgent('代码审计专家');

      await tester.pumpWidget(wrap(const AgentsPage()));
      await tester.pumpAndSettle();

      expect(find.text('用一句话描述，让 AI 生成'), findsOneWidget);
      expect(find.text('代码审计专家'), findsOneWidget);
    });

    testWidgets('点击入口能打开描述弹窗', (tester) async {
      await tester.pumpWidget(wrap(const AgentsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('描述目标，让 AI 生成'));
      await tester.pumpAndSettle();

      expect(find.text('用一句话描述这个智能体'), findsOneWidget);
      expect(find.text('生成草稿'), findsOneWidget);
      // 弹窗必须如实说明「不落库、不授权」，否则用户会以为生成即生效。
      expect(
        find.text('生成结果只作为编辑器的预填内容，不会自动保存，也不会授予任何权限。'),
        findsOneWidget,
      );
    });

    testWidgets('目标为空时只提示、不关闭弹窗', (tester) async {
      await tester.pumpWidget(wrap(const AgentsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('描述目标，让 AI 生成'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('生成草稿'));
      await tester.pumpAndSettle();

      expect(find.text('先写一句你要它做什么'), findsOneWidget);
      // 弹窗仍在：不该把用户直接丢回列表。
      expect(find.text('用一句话描述这个智能体'), findsOneWidget);
    });
  });

  group('AgentEditorPage 草稿预填', () {
    testWidgets('草稿预填名称与指令，并提示需确认与未默认勾选的工具', (tester) async {
      const draft = AgentDraft(
        goal: '帮我审代码',
        name: '代码审查员',
        systemPrompt: '你是「代码审查员」。关注空指针与边界条件。',
        grantedTools: {'read_file'},
        pendingTools: ['terminal'],
        notes: ['以下工具高于安全级，未默认勾选，请自行确认：terminal'],
      );

      await tester.pumpWidget(wrap(const AgentEditorPage(draft: draft)));
      await tester.pump();

      final nameField = tester.widget<TextField>(find.byType(TextField).first);
      expect(nameField.controller?.text, '代码审查员');

      final promptField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(promptField.controller?.text, contains('关注空指针与边界条件'));

      expect(find.text('AI 已按你的描述预填'), findsOneWidget);
      expect(find.textContaining('terminal'), findsWidgets);
      expect(find.text('保存前你可以修改任何内容；只有点了保存才会写入。'), findsOneWidget);
    });

    testWidgets('没有草稿时不显示 AI 预填提示', (tester) async {
      await tester.pumpWidget(wrap(const AgentEditorPage()));
      await tester.pump();

      expect(find.text('AI 已按你的描述预填'), findsNothing);
      expect(find.text('已用本地模板预填'), findsNothing);
    });
  });

  group('从描述生成到保存的完整链路', () {
    /// 骨架屏用的是 `repeat(reverse: true)` 的无限动画，处于加载态时 pumpAndSettle
    /// 可能一直不收敛。这里限时等待，超时退化为固定次数 pump，避免测试挂死。
    Future<void> settle(WidgetTester tester) async {
      try {
        await tester.pumpAndSettle(const Duration(milliseconds: 50),
            EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      } catch (_) {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
    }

    testWidgets('未配置模型时用本地草稿跑通生成、编辑与保存，并保持最小权限',
        (tester) async {
      await tester.pumpWidget(wrap(const AgentsPage()));
      await settle(tester);

      await tester.tap(find.text('描述目标，让 AI 生成'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '帮我审空指针');
      await tester.tap(find.text('生成草稿'));
      await settle(tester);

      // 测试环境没有配置模型：生成服务应回退成本地草稿，并把编辑器打开。
      expect(find.text('已用本地模板预填'), findsOneWidget);
      // 高于安全级的工具必须显式告知用户，而不是悄悄不勾。
      expect(find.textContaining('http_request'), findsWidgets);

      await tester.enterText(find.byType(TextField).first, '空指针审查员');
      await tester.tap(find.text('保存智能体'));
      await settle(tester);
      // 保存成功会弹 3 秒的 toast；不等它到期，测试结束时会因 pending timer 失败。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));

      final agents = await db.allAgents();
      expect(agents, hasLength(1));
      expect(agents.single.name, '空指针审查员');

      final granted = (jsonDecode(agents.single.enabledToolsJson) as List)
          .cast<String>()
          .toSet();
      // 兜底草稿只授予安全级工具。http_request 属高风险、web_search 需逐次确认，
      // 都不能因为「这是 AI 生成的」而自动进入授权范围。
      expect(granted, {'calculator', 'get_time', 'json_query'});
      expect(granted, isNot(contains('http_request')));
      expect(granted, isNot(contains('web_search')));

      // 保存后返回列表，新 Agent 必须出现——验证 pop(true) → 刷新的接线。
      expect(find.text('空指针审查员'), findsOneWidget);
    });
  });
}
