import 'package:mobile_agent/application/mcp_service.dart';
import 'package:mobile_agent/presentation/widgets/nexus_background.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/domain/provider_config.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/mobile_theme.dart';
import 'package:mobile_agent/presentation/agents/agent_editor_page.dart';
import 'package:mobile_agent/presentation/agents/agents_page.dart';
import 'package:mobile_agent/presentation/artifacts/artifact_center_page.dart';
import 'package:mobile_agent/presentation/artifacts/research_artifacts_page.dart';
import 'package:mobile_agent/presentation/audit/audit_log_page.dart';
import 'package:mobile_agent/presentation/browser/browser_page.dart';
import 'package:mobile_agent/presentation/chat/chat_page.dart';
import 'package:mobile_agent/presentation/dashboard/cost_ledger_page.dart';
import 'package:mobile_agent/presentation/dashboard/dashboard_page.dart';
import 'package:mobile_agent/presentation/diagnostics/log_viewer_page.dart';
import 'package:mobile_agent/presentation/diagnostics/operational_metrics_page.dart';
import 'package:mobile_agent/presentation/diagnostics/run_analysis_page.dart';
import 'package:mobile_agent/presentation/feedback/feedback_page.dart';
import 'package:mobile_agent/presentation/history/history_page.dart';
import 'package:mobile_agent/presentation/jobs/jobs_inbox_page.dart';
import 'package:mobile_agent/presentation/knowledge/knowledge_page.dart';
import 'package:mobile_agent/presentation/mcp/mcp_servers_page.dart';
import 'package:mobile_agent/presentation/memory/memory_page.dart';
import 'package:mobile_agent/presentation/onboarding/onboarding_page.dart';
import 'package:mobile_agent/presentation/plugins/plugins_page.dart';
import 'package:mobile_agent/presentation/plugins/skill_market_page.dart';
import 'package:mobile_agent/presentation/projects/project_change_set_page.dart';
import 'package:mobile_agent/presentation/projects/project_git_page.dart';
import 'package:mobile_agent/presentation/projects/project_home_page.dart';
import 'package:mobile_agent/presentation/projects/project_picker_page.dart';
import 'package:mobile_agent/presentation/projects/remote_execution_page.dart';
import 'package:mobile_agent/presentation/projects/static_web_delivery_page.dart';
import 'package:mobile_agent/presentation/prompts/prompt_library_page.dart';
import 'package:mobile_agent/presentation/scheduled/scheduled_tasks_page.dart';
import 'package:mobile_agent/presentation/search/global_search_page.dart';
import 'package:mobile_agent/presentation/settings/appearance_theme_page.dart';
import 'package:mobile_agent/presentation/settings/data_backup_page.dart';
import 'package:mobile_agent/presentation/settings/data_management_page.dart';
import 'package:mobile_agent/presentation/settings/default_assistant_page.dart';
import 'package:mobile_agent/presentation/settings/device_automation_page.dart';
import 'package:mobile_agent/presentation/settings/device_backups_page.dart';
import 'package:mobile_agent/presentation/settings/device_capabilities_page.dart';
import 'package:mobile_agent/presentation/settings/extensions_page.dart';
import 'package:mobile_agent/presentation/settings/language_page.dart';
import 'package:mobile_agent/presentation/settings/linux_environment_page.dart';
import 'package:mobile_agent/presentation/settings/model_list_page.dart';
import 'package:mobile_agent/presentation/settings/personal_context_page.dart';
import 'package:mobile_agent/presentation/settings/provider_detail_page.dart';
import 'package:mobile_agent/presentation/settings/provider_list_page.dart';
import 'package:mobile_agent/presentation/settings/provider_template_import_page.dart';
import 'package:mobile_agent/presentation/settings/settings_page.dart';
import 'package:mobile_agent/presentation/settings/system_editors_page.dart';
import 'package:mobile_agent/presentation/settings/tool_list_page.dart';
import 'package:mobile_agent/presentation/settings/workspace_files_page.dart';
import 'package:mobile_agent/presentation/tasks/development_tasks_page.dart';
import 'package:mobile_agent/presentation/tasks/task_details_page.dart';
import 'package:mobile_agent/presentation/terminal/terminal_page.dart';
import 'package:mobile_agent/presentation/vault/vault_page.dart';
import 'package:mobile_agent/presentation/workbench/session_workbench_page.dart';
import 'package:mobile_agent/presentation/workflows/mobile_workflows_page.dart';
import 'package:mobile_agent/presentation/workspace/development_workbench_page.dart';
import 'package:mobile_agent/presentation/workspace/workspace_editor_page.dart';

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

class _GalleryChat extends ChatController {
  @override
  ChatState build() =>
      const ChatState(loading: false, conversationId: 'ui-gallery');
}

// Entry-point rendering uses isolated data and never invokes a model, installs a
// runtime, requests a permission, connects SSH or mutates the user's workspace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory fixture;
  late DevelopmentTaskInfo task;
  late RunRecord run;
  const config =
      ProviderConfig(baseUrl: 'http://127.0.0.1:1', model: '未配置模型', apiKey: '');
  setUpAll(() async {
    for (final entry in [
      ('sans-serif', 'C:/Windows/Fonts/msyh.ttc'),
      ('Inter', 'C:/Windows/Fonts/msyh.ttc'),
      ('monospace', 'C:/Windows/Fonts/msyh.ttc'),
      ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
    ]) {
      final font = File(entry.$2);
      if (font.existsSync()) {
        final data = await font.readAsBytes();
        await (FontLoader(entry.$1)
              ..addFont(Future.value(data.buffer.asByteData())))
            .load();
      }
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('nexus/browser/events'), (_) async => null);

    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    fixture = Directory('local/temp').createTempSync('android-ui-fixture-');
    File('${fixture.path}/README.md')
        .writeAsStringSync('# 界面验收项目\n\n用于检查手机文件编辑器。');
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 10, 21);
    await db.insertProject(ProjectsCompanion.insert(
        id: 'gallery-project',
        name: '界面验收项目',
        canonicalRootPath: fixture.absolute.path,
        createdAt: now,
        updatedAt: now));
    final record = await TaskService()
        .create(db: db, conversationId: '', requestJson: '{}');
    await db.saveTask(record.copyWith(status: 'completed'));
    task = TaskService().describe(record.copyWith(status: 'completed'));
    await db.insertRunRecord(RunRecordsCompanion.insert(
        runId: 'gallery-run',
        conversationId: '',
        startedAt: now,
        status: const Value('success')));
    run = (await db.findRunRecord('gallery-run'))!;
  });
  tearDown(() async {
    await db.close();
    final workspaceTemp = Directory('local/temp').absolute.path;
    if (fixture.absolute.path.startsWith(
        '$workspaceTemp${Platform.pathSeparator}android-ui-fixture-')) {
      await fixture.delete(recursive: true);
    }
  });
  Map<String, Widget Function()> pages() => {
        'agents/agent_editor_page.dart': () => const AgentEditorPage(),
        'agents/agents_page.dart': () => const AgentsPage(),
        'artifacts/artifact_center_page.dart': () => const ArtifactCenterPage(),
        'artifacts/research_artifacts_page.dart': () =>
            const ResearchArtifactsPage(),
        'audit/audit_log_page.dart': () => const AuditLogPage(),
        'browser/browser_page.dart': () => BrowserPage(
            conversationId: 'ui-gallery',
            viewBuilder: (_) => const Center(child: Text('网页内容区域'))),
        'chat/chat_page.dart': () => const ChatPage(),
        'dashboard/cost_ledger_page.dart': () =>
            CostLedgerPage(database: () async => db),
        'dashboard/dashboard_page.dart': () => const DashboardPage(),
        'diagnostics/log_viewer_page.dart': () => const LogViewerPage(),
        'diagnostics/operational_metrics_page.dart': () =>
            OperationalMetricsPage(database: () async => db),
        'diagnostics/run_analysis_page.dart': () => const RunAnalysisPage(),
        'feedback/feedback_page.dart': () => const FeedbackPage(),
        'history/history_page.dart': () =>
            HistoryPage(loadDatabase: () async => db),
        'jobs/jobs_inbox_page.dart': () => const JobsInboxPage(),
        'knowledge/knowledge_page.dart': () => const KnowledgePage(),
        'mcp/mcp_servers_page.dart': () =>
            McpServersPage(service: McpService(database: Future.value(db))),
        'memory/memory_page.dart': () => const MemoryPage(),
        'onboarding/onboarding_page.dart': () => const OnboardingPage(),
        'plugins/plugins_page.dart': () => const PluginsPage(),
        'plugins/skill_market_page.dart': () => const SkillMarketPage(),
        'projects/project_change_set_page.dart': () => ProjectChangeSetPage(
            projectId: 'gallery-project', workspacePath: fixture.path),
        'projects/project_git_page.dart': () =>
            ProjectGitPage(workspacePath: fixture.path),
        'projects/project_home_page.dart': () =>
            const ProjectHomePage(projectId: 'gallery-project'),
        'projects/project_picker_page.dart': () => const ProjectPickerPage(),
        'projects/remote_execution_page.dart': () =>
            const RemoteExecutionPage(),
        'projects/static_web_delivery_page.dart': () => StaticWebDeliveryPage(
            projectId: 'gallery-project',
            workspacePath: fixture.path,
            projectName: '界面验收项目'),
        'prompts/prompt_library_page.dart': () =>
            PromptLibraryPage(database: () async => db),
        'scheduled/scheduled_tasks_page.dart': () => const ScheduledTasksPage(),
        'search/global_search_page.dart': () => const GlobalSearchPage(),
        'settings/appearance_theme_page.dart': () =>
            const AppearanceThemePage(),
        'settings/data_backup_page.dart': () => const DataBackupPage(),
        'settings/data_management_page.dart': () => const DataManagementPage(),
        'settings/default_assistant_page.dart': () =>
            const DefaultAssistantPage(),
        'settings/device_automation_page.dart': () =>
            const DeviceAutomationPage(),
        'settings/device_backups_page.dart': () => const DeviceBackupsPage(),
        'settings/device_capabilities_page.dart': () =>
            const DeviceCapabilitiesPage(),
        'settings/extensions_page.dart': () => const ExtensionsPage(),
        'settings/language_page.dart': () => const LanguagePage(),
        'settings/linux_environment_page.dart': () =>
            const LinuxEnvironmentPage(),
        'settings/model_list_page.dart': () =>
            const ModelListPage(config: config),
        'settings/personal_context_page.dart': () =>
            const PersonalContextPage(),
        'settings/provider_detail_page.dart': () => const ProviderDetailPage(),
        'settings/provider_list_page.dart': () => const ProviderListPage(),
        'settings/provider_template_import_page.dart': () =>
            const ProviderTemplateImportPage(),
        'settings/settings_page.dart': () => const SettingsPage(),
        'settings/system_editors_page.dart': () => const SystemEditorsPage(),
        'settings/tool_list_page.dart': () => const ToolListPage(),
        'settings/workspace_files_page.dart': () => const WorkspaceFilesPage(),
        'tasks/development_tasks_page.dart': () => const DevelopmentTasksPage(),
        'tasks/task_details_page.dart': () => TaskDetailsPage(task: task),
        'terminal/terminal_page.dart': () =>
            const TerminalPage(autoConnect: false),
        'vault/vault_page.dart': () => const VaultPage(),
        'workbench/session_workbench_page.dart': () =>
            const SessionWorkbenchPage(),
        'workflows/mobile_workflows_page.dart': () =>
            const MobileWorkflowsPage(),
        'workspace/development_workbench_page.dart': () =>
            DevelopmentWorkbenchPage(
                workspacePath: fixture.path, projectId: 'gallery-project'),
        'workspace/workspace_editor_page.dart': () => WorkspaceEditorPage(
            workspacePath: fixture.path, relativePath: 'README.md'),
        'diagnostics/run-detail': () => RunDetailPage(run: run),
      };
  test('gallery covers every Android page source', () {
    final registered = pages().keys.toSet();
    final files = Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('page.dart') &&
            !f.path.endsWith('desktop_settings_page.dart'));
    for (final f in files) {
      final name = f.path.replaceAll('\\', '/').split('lib/presentation/').last;
      expect(registered, contains(name),
          reason: 'Add the Android page to the rendering inventory: $name');
    }
  });
  testWidgets('prompt library offers retry after a failed read and recovers',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      theme: MobileTheme.apply(AppTheme.light()),
      home: PromptLibraryPage(database: () async {
        if (attempts++ == 0) throw StateError('fixture database unavailable');
        return db;
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('加载未成功'), findsOneWidget);
    expect(find.text('暂无提示词'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无提示词'), findsOneWidget);
    expect(attempts, 2);
  });
  // Use two configurations to catch clipped controls and titles, rather than
  // relying solely on the presence of a theme wrapper in the source code.
  for (final name in [...pages().keys]) {
    for (final large in [false, true]) {
      testWidgets('$name ${large ? 'narrow large text' : 'phone'}',
          (tester) async {
        tester.view.physicalSize = Size(large ? 360 : 411, 891);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            chatControllerProvider.overrideWith(_GalleryChat.new)
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: MobileTheme.apply(AppTheme.light()),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(large ? 1.6 : 1),
                  disableAnimations: true),
              child: RepaintBoundary(
                  key: key, child: NexusBackground(child: child!)),
            ),
            home: pages()[name]!(),
          ),
        ));
        for (var frame = 0; frame < 8; frame++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull, reason: name);
        if (const bool.fromEnvironment('NEXUS_UI_GALLERY')) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('local/temp/android-ui-gallery')
              ..createSync(recursive: true);
            final filename = name.replaceAll('/', '-').replaceAll('.dart', '');
            await File('${dir.path}/$filename${large ? '-large' : ''}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 12));
        expect(tester.takeException(), isNull, reason: 'dispose $name');
      });
    }
  }
}
