import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/audit_service.dart';
import 'package:mobile_agent/application/knowledge_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/scheduled_task_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/audit/audit_log_page.dart';
import 'package:mobile_agent/presentation/knowledge/knowledge_page.dart';
import 'package:mobile_agent/presentation/l10n/app_strings.dart';
import 'package:mobile_agent/presentation/scheduled/scheduled_tasks_page.dart';
import 'package:mobile_agent/presentation/settings/data_management_page.dart';
import 'package:mobile_agent/presentation/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 三个曾"断线孤儿页"（定时任务/知识库/审计日志）的冒烟守护：
/// 页面必须能在内存库上渲染，且设置页入口必须真的能把它们推入路由。
/// 这类问题 analyze 抓不到（编译期完全合法），只能靠 pump 页面验证。
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
    SharedPreferences.setMockInitialValues({
      'settings.llm.deep_reasoning': true,
      'settings.tool.web_browsing': true,
      'settings.tool.terminal_file': true,
      'settings.language': 'system',
      'knowledge_enabled': true,
      'audit_enabled': true,
    });
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: MaterialApp(home: child),
    );
  }

  group('KnowledgePage', () {
    testWidgets('空库渲染空态', (tester) async {
      await tester.pumpWidget(wrap(const KnowledgePage()));
      await tester.pumpAndSettle();

      expect(find.text('知识库'), findsOneWidget);
      expect(find.text('文档切片检索与 RAG 管理'), findsOneWidget);
      expect(find.text('知识库为空'), findsOneWidget);
    });

    testWidgets('列出已入库文档', (tester) async {
      await KnowledgeService().ingest(
        db: db,
        name: '接入说明',
        sourceType: 'paste',
        content: '这是用于冒烟测试的知识内容，验证入库后能在页面列表中渲染。',
      );

      await tester.pumpWidget(wrap(const KnowledgePage()));
      await tester.pumpAndSettle();

      expect(find.text('接入说明'), findsOneWidget);
      expect(find.text('知识库为空'), findsNothing);
    });
  });

  group('ScheduledTasksPage', () {
    testWidgets('空库渲染空态与新建入口', (tester) async {
      await tester.pumpWidget(wrap(const ScheduledTasksPage()));
      await tester.pumpAndSettle();

      expect(find.text('定时任务'), findsOneWidget);
      expect(find.text('自动化循环计划与后台执行'), findsOneWidget);
      expect(find.text('无定时任务'), findsOneWidget);
      expect(find.byTooltip('新建定时任务'), findsOneWidget);
    });

    testWidgets('列出已创建任务并显示启用状态', (tester) async {
      await ScheduledTaskService().create(
        db: db,
        name: '晨间摘要',
        prompt: '总结今日要闻，用 3 条要点输出',
        schedule: const ScheduleSpec(hour: 9, minute: 0),
      );

      await tester.pumpWidget(wrap(const ScheduledTasksPage()));
      await tester.pumpAndSettle();

      expect(find.text('晨间摘要'), findsOneWidget);
      expect(find.text('已启用'), findsOneWidget);
      expect(find.text('无定时任务'), findsNothing);
    });
  });

  group('AuditLogPage', () {
    testWidgets('空库渲染空态与总开关', (tester) async {
      await tester.pumpWidget(wrap(const AuditLogPage()));
      await tester.pumpAndSettle();

      expect(find.text('审计日志'), findsOneWidget);
      expect(find.text('启用审计'), findsOneWidget);
      expect(find.text('暂无审计记录'), findsOneWidget);
    });

    testWidgets('展示已写入的审批授予记录', (tester) async {
      await AuditService().log(
        db,
        type: 'tool_grant',
        detail: 'terminal',
        decision: 'allowAlways',
        risk: 'requiresConfirmation',
      );

      await tester.pumpWidget(wrap(const AuditLogPage()));
      await tester.pumpAndSettle();

      expect(find.text('tool_grant · terminal'), findsOneWidget);
      expect(find.text('暂无审计记录'), findsNothing);
    });
  });

  group('SettingsPage 入口接线', () {
    testWidgets('通过数据管理入口行都能推入对应页面', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 点击「数据管理」卡片行
      await tester.tap(find.text('数据管理'));
      await tester.pumpAndSettle();
      expect(find.text('数据管理'), findsWidgets);

      // 知识库入口
      await tester.tap(find.text(AppStrings.knowledgeSectionTitle));
      await tester.pumpAndSettle();
      expect(find.text('文档切片检索与 RAG 管理'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      // 审计日志入口
      await tester.tap(find.text(AppStrings.auditLogEntry));
      await tester.pumpAndSettle();
      expect(find.text('启用审计'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      // 定时任务入口
      await tester.tap(find.text(AppStrings.scheduledTasksEntry));
      await tester.pumpAndSettle();
      expect(find.text('自动化循环计划与后台执行'), findsOneWidget);
    });

    testWidgets('DataManagementPage 独立渲染各项统计与数据入口', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: const MaterialApp(home: DataManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上下文与知识库'), findsOneWidget);
      expect(find.text('自动化与审计'), findsOneWidget);
      expect(find.text('备份与还原'), findsOneWidget);
      expect(find.text(AppStrings.knowledgeSectionTitle), findsOneWidget);
      expect(find.text(AppStrings.memorySectionTitle), findsOneWidget);
      expect(find.text(AppStrings.scheduledTasksEntry), findsOneWidget);
      expect(find.text(AppStrings.auditLogEntry), findsOneWidget);
    });
  });
}
