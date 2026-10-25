import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/development_target.dart';
import '../application/artifact_service.dart';
import '../application/chat_controller.dart';
import '../application/device_action_runner.dart';
import '../application/providers.dart';
import '../application/dashboard_service.dart';
import '../application/jobs/job_board_providers.dart';
import '../application/reminder_service.dart';
import '../application/mobile_workflow_service.dart';
import '../application/research_artifact_service.dart';
import '../domain/research_artifact.dart';
import '../domain/models.dart';
import '../domain/session_metrics.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/provider_config.dart';
import '../presentation/agents/agent_editor_page.dart';
import '../presentation/agents/agents_page.dart';
import '../presentation/artifacts/artifact_center_page.dart';
import '../presentation/artifacts/research_artifacts_page.dart';
import '../presentation/audit/audit_log_page.dart';
import '../presentation/branches/branch_tree_sheet.dart';
import '../presentation/chat/widgets/environment_sheet.dart';
import '../presentation/chat/widgets/input_tool_grid_sheet.dart';
import '../presentation/chat/widgets/session_metrics_sheet.dart';
import '../presentation/chat/widgets/tool_approval_sheet.dart';
import '../presentation/dashboard/dashboard_page.dart';
import '../presentation/dashboard/cost_ledger_page.dart';
import '../infrastructure/database/cost_budget_ledger.dart';
import '../infrastructure/providers/cost_budget_policy.dart';
import '../presentation/dashboard/dashboard_provider.dart';
import '../presentation/diagnostics/log_viewer_page.dart';
import '../presentation/diagnostics/run_analysis_page.dart';
import '../presentation/diagnostics/operational_metrics_page.dart';
import '../presentation/feedback/feedback_page.dart';
import '../presentation/history/history_page.dart';
import '../presentation/jobs/jobs_inbox_page.dart';
import '../presentation/knowledge/knowledge_page.dart';
import '../presentation/memory/memory_page.dart';
import '../presentation/mcp/mcp_servers_page.dart';
import '../presentation/onboarding/onboarding_page.dart';
import '../presentation/plugins/plugins_page.dart';
import '../presentation/plugins/skill_market_page.dart';
import '../presentation/presets/run_presets_sheet.dart';
import '../presentation/projects/project_change_set_page.dart';
import '../presentation/projects/project_git_page.dart';
import '../presentation/projects/project_home_page.dart';
import '../presentation/projects/project_picker_page.dart';
import '../presentation/projects/remote_execution_page.dart';
import '../presentation/prompts/prompt_library_page.dart';
import '../presentation/scheduled/scheduled_tasks_page.dart';
import '../presentation/search/global_search_page.dart';
import '../presentation/settings/appearance_theme_page.dart';
import '../presentation/settings/data_backup_page.dart';
import '../presentation/settings/data_management_page.dart';
import '../presentation/settings/default_assistant_page.dart';
import '../presentation/settings/device_action_confirm_sheet.dart';
import '../presentation/settings/device_automation_page.dart';
import '../presentation/settings/device_backups_page.dart';
import '../presentation/settings/device_capabilities_page.dart';
import '../presentation/settings/extensions_page.dart';
import '../presentation/settings/language_page.dart';
import '../presentation/settings/linux_environment_page.dart';
import '../presentation/settings/model_list_page.dart';
import '../presentation/settings/personal_context_page.dart';
import '../presentation/settings/provider_detail_page.dart';
import '../presentation/settings/provider_list_page.dart';
import '../presentation/settings/provider_template_import_page.dart';
import '../presentation/settings/settings_page.dart';
import '../presentation/settings/system_editors_page.dart';
import '../presentation/settings/tool_list_page.dart';
import '../presentation/settings/workspace_files_page.dart';
import '../presentation/tasks/development_tasks_page.dart';
import '../presentation/tasks/task_details_page.dart';
import '../presentation/theme/app_palette.dart';
import '../presentation/theme/app_theme.dart';
import '../presentation/terminal/terminal_page.dart';
import '../presentation/vault/vault_page.dart';
import '../presentation/widgets/confirm_action.dart';
import '../presentation/widgets/nexus_action_sheet.dart';
import '../presentation/widgets/nexus_sheet.dart';
import '../presentation/workbench/session_workbench_page.dart';
import '../presentation/workflows/mobile_workflows_page.dart';
import '../presentation/workspace/development_workbench_page.dart';
import '../presentation/workspace/file_tree_sheet.dart';
import '../presentation/workspace/workspace_editor_page.dart';
import '../presentation/projects/static_web_delivery_page.dart';

bool _pageCoverageRegistered = false;
void registerPageCoverageChecks() {
  if (!kDebugMode || _pageCoverageRegistered) return;
  _pageCoverageRegistered = true;
  registerExtension(
      'ext.nexus.pageCoverageUi',
      (m, args) async =>
          ServiceExtensionResponse.result(jsonEncode(await _handle(args))));
}

Directory? _root;
AppDatabase? _db;
String _workspacePath = '';
Route<void>? _route;
NavigatorState? _navigator;
FlutterExceptionHandler? _prevOnError;
final _errors = <String>[];
final _hostKey = GlobalKey<_PageCoverageHostState>();
final _innerNavKey = GlobalKey<NavigatorState>();
BuildContext? _sheetContext;
Map<String, String> _lastCoverageRequest = {};
String _coverageStage = 'idle';

const _sheets = <String>[
  'confirm_danger_dialog',
  'action_sheet',
  'tool_approval_sheet',
  'device_action_confirm_sheet',
  'session_metrics_sheet',
  'input_tool_grid_sheet',
  'environment_setup_sheet',
  'file_tree_sheet',
  'run_presets_sheet',
  'branch_tree_sheet',
  'reminder_create_dialog',
  'workflow_run_confirmation',
  'cost_budget_dialog',
];

const _pages = <String>[
  'agent_editor',
  'agents',
  'audit_log',
  'dashboard',
  'cost_ledger',
  'operational_metrics',
  'log_viewer',
  'run_analysis',
  'feedback',
  'mcp_servers',
  'onboarding',
  'plugins',
  'skill_market',
  'project_change_set',
  'project_git',
  'project_home',
  'static_web_delivery',
  'project_picker',
  'remote_execution',
  'prompt_library',
  'scheduled_tasks',
  'appearance_theme',
  'data_backup',
  'data_management',
  'device_automation',
  'device_backups',
  'device_capabilities',
  'extensions',
  'language',
  'linux_environment',
  'model_list',
  'provider_detail',
  'provider_list',
  'provider_template_import',
  'settings',
  'tool_list',
  'workspace_files',
  'development_tasks',
  'task_details',
  'terminal',
  'vault',
  'session_workbench',
  'development_workbench',
  'workspace_editor',
  'personal_context',
  'system_editors',
  'global_search',
  'history',
  'jobs_inbox',
  'knowledge',
  'memory',
  'default_assistant',
  'artifact_center',
  'mobile_workflows',
  'research_artifacts',
];

Widget _buildPage(String key) {
  final now = DateTime.utc(2026, 10, 19, 12);
  final syntheticTask = DevelopmentTaskInfo(
    id: 'ta1',
    conversationId: 'a',
    projectId: 'project-p',
    type: 'implement',
    status: 'completed',
    prompt: '检查移动端 360dp 窄屏与大字号布局自适应',
    title: '实现并验证：移动端页面大字号与窄屏走查',
    sourceType: 'manual',
    workspacePath: _workspacePath,
    model: 'fixture-only',
    summary: '合成任务摘要，不触发真实模型调用。',
    runId: 'run-a1',
    createdAt: now,
    updatedAt: now,
    resumeCount: 0,
  );
  const config = ProviderConfig(
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    apiKey: '',
  );
  return switch (key) {
    'agent_editor' => const AgentEditorPage(),
    'agents' => const AgentsPage(),
    'audit_log' => const AuditLogPage(),
    'dashboard' => const DashboardPage(initialDeveloperMode: true),
    'cost_ledger' => CostLedgerPage(database: () async => _db!),
    'operational_metrics' => OperationalMetricsPage(
        database: () async => _db!, initialEnvironment: 'fixture'),
    'research_artifacts' => const ResearchArtifactsPage(readOnly: true),
    'log_viewer' => const LogViewerPage(),
    'run_analysis' => const RunAnalysisPage(),
    'feedback' => const FeedbackPage(),
    'mcp_servers' => const McpServersPage(),
    'onboarding' => const OnboardingPage(),
    'plugins' => const PluginsPage(),
    'skill_market' => const SkillMarketPage(),
    'project_change_set' => ProjectChangeSetPage(
        projectId: 'project-p', workspacePath: _workspacePath),
    'project_git' => ProjectGitPage(workspacePath: _workspacePath),
    'project_home' => const ProjectHomePage(projectId: 'project-p'),
    'static_web_delivery' => StaticWebDeliveryPage(
        projectId: 'project-p',
        workspacePath: _workspacePath,
        projectName: '隔离网页开发验收',
        artifacts: ArtifactService(
            rootDirectory: () async =>
                Directory(p.join(_root!.path, 'web-artifacts')))),
    'project_picker' => const ProjectPickerPage(),
    'remote_execution' => const RemoteExecutionPage(),
    'prompt_library' => const PromptLibraryPage(),
    'scheduled_tasks' => const ScheduledTasksPage(),
    'appearance_theme' => const AppearanceThemePage(),
    'data_backup' => const DataBackupPage(),
    'data_management' => const DataManagementPage(),
    'device_automation' => const DeviceAutomationPage(),
    'device_backups' => const DeviceBackupsPage(),
    'device_capabilities' => const DeviceCapabilitiesPage(),
    'extensions' => const ExtensionsPage(),
    'language' => const LanguagePage(),
    'linux_environment' => const LinuxEnvironmentPage(
        preferencesTimeout: Duration(milliseconds: 200),
        environmentCheckTimeout: Duration(milliseconds: 300)),
    'model_list' => const ModelListPage(config: config),
    'provider_detail' => const ProviderDetailPage(),
    'provider_list' => const ProviderListPage(),
    'provider_template_import' => const ProviderTemplateImportPage(),
    'settings' => const SettingsPage(),
    'tool_list' => const ToolListPage(),
    'workspace_files' => const WorkspaceFilesPage(),
    'development_tasks' => const DevelopmentTasksPage(),
    'task_details' => TaskDetailsPage(task: syntheticTask),
    'terminal' => const TerminalPage(autoConnect: false),
    'vault' => const VaultPage(),
    'session_workbench' => const SessionWorkbenchPage(),
    'development_workbench' => DevelopmentWorkbenchPage(
        workspacePath: _workspacePath, projectId: 'project-p'),
    'workspace_editor' => WorkspaceEditorPage(
        workspacePath: _workspacePath,
        relativePath: 'sample.txt',
        projectId: 'project-p'),
    'personal_context' => const PersonalContextPage(),
    'system_editors' => const SystemEditorsPage(),
    'global_search' => const GlobalSearchPage(),
    'history' => const HistoryPage(),
    'jobs_inbox' => const JobsInboxPage(),
    'knowledge' => const KnowledgePage(),
    'memory' => const MemoryPage(),
    'default_assistant' => const DefaultAssistantPage(),
    'artifact_center' => const ArtifactCenterPage(readOnly: true),
    'mobile_workflows' => const MobileWorkflowsPage(),
    _ => throw ArgumentError('Unknown page key: $key'),
  };
}

Future<void> _popInnerSheets() async {
  final nav = _innerNavKey.currentState;
  if (nav == null) return;
  try {
    _coverageStage = 'pop_route';
    if (nav.canPop()) nav.pop();
    _coverageStage = 'unfocus';
    FocusManager.instance.primaryFocus?.unfocus();
    _coverageStage = 'pop_wait';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _coverageStage = 'pop_complete';
  } catch (error, stack) {
    _errors.add('Fixture popup cleanup failed: $error\n$stack');
  }
}

void _triggerSheet(BuildContext ctx, String key) {
  switch (key) {
    case 'confirm_danger_dialog':
      unawaited(showConfirmAction(
        ctx,
        title: '彻底清理本地索引？',
        message: '此操作将移除缓存索引，不会删除原始会话记录。',
        confirmLabel: '确认清理',
        isDanger: true,
        requiredKeyword: 'CLEAN',
        bulletItems: const [
          '清理范围：全文检索倒排索引与临时分块',
          '可恢复性：下次打开搜索时自动后台重建',
        ],
      ));
    case 'action_sheet':
      unawaited(showNexusActionSheet<String>(
        context: ctx,
        title: '思考与执行模式',
        subtitle: '标准适合普通对话；深度适合复杂任务；自动按任务调整',
        items: const [
          ActionSheetItem.section('推理档位'),
          ActionSheetItem(
            icon: Icons.bolt_outlined,
            title: '标准模式',
            subtitle: '响应更快，适合日常问答与快速修改',
            value: 'standard',
            selected: true,
          ),
          ActionSheetItem(
            icon: Icons.psychology_outlined,
            title: '深度思考',
            subtitle: '多步推理与自检，适合复杂架构与排障',
            value: 'deep',
          ),
          ActionSheetItem(
            icon: Icons.delete_outline,
            title: '重置当前偏好',
            value: 'reset',
            destructive: true,
          ),
        ],
      ));
    case 'tool_approval_sheet':
      unawaited(showNexusSheet<ToolApproval>(
        context: ctx,
        builder: (_) => const ToolApprovalSheet(
          call: ToolCall(
            id: 'tc-cov-1',
            name: 'bash',
            arguments: {
              'command': 'flutter analyze --no-pub && git status --short',
              'TargetFile': 'lib/presentation/chat/chat_page.dart',
            },
          ),
          risk: ToolRisk.dangerous,
          allowSessionTrust: true,
          allowPersistentTrust: true,
        ),
      ));
    case 'device_action_confirm_sheet':
      unawaited(showDeviceActionConfirmSheet(
        ctx,
        title: '恢复 com.example.app 的应用数据',
        subtitle: '预览 2 分钟内有效；执行结果会写入审计日志。',
        actions: [
          PreparedDeviceAction(
            description: '恢复应用配置与数据库',
            arguments: const {'packageName': 'com.example.app'},
            planId: 'plan-cov-1',
            preview: const {
              'riskClass': 'dangerous',
              'reversible': false,
              'target': 'com.example.app',
              'scope': 'config + databases',
              'impact': '覆盖当前应用私有目录中的同名配置',
              'command':
                  'tar -xzf backup-cov.tar.gz -C /data/data/com.example.app',
            },
          ),
        ],
      ));
    case 'session_metrics_sheet':
      unawaited(showSessionMetricsSheet(
        ctx,
        metrics: const SessionMetrics(
          rounds: 4,
          steps: 6,
          llmTime: Duration(seconds: 8),
          toolTime: Duration(milliseconds: 950),
          avgTtft: Duration(milliseconds: 420),
          tokensPerSecond: 48.5,
          cacheHitRate: 0.62,
          promptTokens: 6400,
          completionTokens: 1280,
        ),
        liveContextTokens: 7680,
        contextLimit: 128000,
        runLabel: '空闲 · 结果见消息',
      ));
    case 'input_tool_grid_sheet':
      unawaited(InputToolGridSheet.show(
        ctx,
        onCommandMenu: () {},
        onMcpMenu: () {},
        onTerminalPreview: () {},
        onEnvSetup: () {},
        onOpenDashboard: () {},
        onOpenWorkbench: () {},
        planModeEnabled: true,
        onPlanModeToggle: () {},
        approvalMode: ApprovalMode.ask,
        onApprovalModeTap: () {},
      ));
    case 'reminder_create_dialog':
      _tapFixtureButton(const ValueKey('create-quick-reminder'));
    case 'workflow_run_confirmation':
      _tapFixtureButton(const ValueKey('workflow-confirm-run-wf-daily-brief'));
    case 'cost_budget_dialog':
      _tapFixtureButton(const ValueKey('dashboard-cost-budget-settings'));
    case 'environment_setup_sheet':
      unawaited(showNexusSheet<void>(
        context: ctx,
        builder: (_) =>
            const EnvironmentSheet(target: DevelopmentTarget.flutterAndroid),
      ));
    case 'file_tree_sheet':
      unawaited(showNexusSheet<void>(
        context: ctx,
        builder: (_) => FileTreeSheet(workspacePath: _workspacePath),
      ));
    case 'run_presets_sheet':
      unawaited(showRunPresetsSheet(ctx));
    case 'branch_tree_sheet':
      unawaited(showBranchTreeSheet(
        ctx,
        currentConversationId: 'a',
        onSelect: (_) {},
      ));
    default:
      throw ArgumentError('Unknown sheet key: $key');
  }
}

void _tapFixtureButton(Key key) {
  VoidCallback? action;
  void visit(Element element) {
    final widget = element.widget;
    if (widget.key == key && widget is ButtonStyleButton) {
      action = widget.onPressed;
    }
    if (widget.key == key && widget is IconButton) action = widget.onPressed;
    element.visitChildElements(visit);
  }

  _innerNavKey.currentContext!.visitChildElements(visit);
  if (action == null) throw StateError('Fixture button is not available');
  action!();
}

Future<Map<String, dynamic>> _handle(Map<String, String> args) async {
  final mode = args['mode'] ?? 'list';
  if (mode == 'progress') {
    return {'lastRequest': _lastCoverageRequest, 'stage': _coverageStage};
  }
  _lastCoverageRequest = Map.of(args);
  if (mode == 'list') {
    return {
      'fixtureOnly': true,
      'modelCalls': 0,
      'pages': _pages,
      'sheets': _sheets,
    };
  }
  if (mode == 'open') {
    if (_route != null) throw StateError('Close owned fixture first');
    NavigatorState? navigator;
    void visit(Element e) {
      if (navigator != null) return;
      if (e is StatefulElement && e.state is NavigatorState) {
        navigator = e.state as NavigatorState;
      } else {
        e.visitChildElements(visit);
      }
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    if (navigator == null) throw StateError('No navigator');
    _root = await Directory.systemTemp.createTemp('nexus-page-coverage-');
    final ws = await Directory(p.join(_root!.path, 'workspace')).create();
    _workspacePath = ws.path;
    await File(p.join(_workspacePath, 'sample.txt'))
        .writeAsString('SAMPLE_WORKSPACE_FILE\nline 2\n');
    await File(p.join(_workspacePath, 'index.html')).writeAsString(
        '<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<link rel="stylesheet" href="styles.css"><h1>手机网页开发验收</h1>'
        '<p>网页预览已在本机运行，无需 Python 或 Linux。</p>'
        '<button onclick="this.textContent=\'交互通过\'">点击验证交互</button></html>');
    await File(p.join(_workspacePath, 'styles.css')).writeAsString(
        'body {font-family:sans-serif; padding:24px; background:#f5f8ff;} '
        'h1 {color:#2455b2;} button {padding:14px;}');
    final db = _db =
        AppDatabase(NativeDatabase(File(p.join(_root!.path, 'db.sqlite'))));
    final now = DateTime.utc(2026, 10, 19, 12);
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: 'project-p',
          name: '合成工程 Project-P',
          canonicalRootPath: _workspacePath,
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.conversations).insert(ConversationsCompanion.insert(
          id: 'a',
          title: const Value('合成会话 A'),
          projectId: const Value('project-p'),
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'ta1',
          conversationId: 'a',
          projectId: const Value('project-p'),
          requestJson: '{"prompt":"检查窄屏与大字号布局"}',
          createdAt: now,
          updatedAt: now,
        ));
    final reminderService = ReminderService(db, delivery: null);
    for (var i = 0; i < 4; i++) {
      await reminderService.create(
          id: 'fixture-rem-$i',
          title: '隔离验收提醒事项 $i · 核对项目交付与资料归档进展',
          scheduledAtUtc: now.add(Duration(hours: i + 1)),
          now: now);
    }
    await MobileWorkflowService(db, reminderDelivery: null).runWorkflow(
        workflowId: 'wf-daily-brief',
        inputs: {'topic': '隔离验收工作流执行轨迹'},
        dryRun: true,
        now: now);
    await ResearchArtifactService(db).create(
        topic: '隔离验收研究成果与引用来源',
        summary: '核对来源时效性',
        claims: [
          ResearchClaim(id: 'fixture-claim', statement: '待补充来源', citations: [
            EvidenceCitation(
              id: 'fixture-citation',
              sourceTitle: '合成来源',
              sourceUri: 'https://example.invalid/source',
              excerpt: '仅用于界面布局',
              capturedAt: now,
              verifiedAt: now.subtract(const Duration(days: 30)),
            )
          ])
        ],
        now: now);
    const costPolicy = CostBudgetPolicy(
        dailyLimitCents: 999999,
        monthlyLimitCents: 9999999,
        hardStopEnabled: false);
    final costs = CostBudgetLedger(db);
    final pendingCost = await costs.reserve(costPolicy, 30,
        now: now,
        runId: 'fixture-cost-run',
        requestId: 'fixture-cost-request',
        providerId: 'isolated-fixture',
        model: 'fixture-model');
    await costs.markPending(pendingCost.id!, 'missing_usage');
    final settledCost = await costs.reserve(costPolicy, 40,
        now: now, runId: 'fixture-cost-run', requestId: 'fixture-cost-settled');
    await costs.settle(settledCost.id!, 10,
        promptTokens: 7, completionTokens: 3);
    final unknownCost = await costs.reserve(costPolicy, 0,
        now: now, requestId: 'fixture-cost-unknown', priced: false);
    await costs.markPending(unknownCost.id!, 'unpriced');
    final reviewedCost = await costs.reserve(costPolicy, 50, now: now);
    await costs.markPending(reviewedCost.id!, 'missing_usage');
    await costs.reconcile(reviewedCost.id!, 20,
        expectedRevision: 0, reference: 'synthetic fixture only', now: now);
    // Synthetic timings are tagged separately and can never sign off performance.
    final traceAt = DateTime.now().subtract(const Duration(minutes: 5));
    for (var i = 0; i < 21; i++) {
      final id = 'fixture-trace-model-$i',
          run = 'fixture-trace-run-$i',
          request = 'fixture-trace-request-$i';
      final started = traceAt.add(Duration(milliseconds: i * 100));
      final meta = {
        'traceSchema': 1,
        'traceId': run,
        'spanId': id,
        'parentSpanId': null,
        'logicalRequestId': request,
        'environment': 'fixture',
        'purpose': i == 20 ? 'summary' : 'inference',
        'timingSource': 'synthetic',
        'firstTokenMs': 5,
        'firstTextMs': 10
      };
      await db.insertRunEvent(RunEventsCompanion.insert(
          eventId: id,
          runId: run,
          sequenceNo: 1,
          type: 'model_attempt',
          status: i == 3 ? 'failed' : 'success',
          name: 'synthetic_model',
          startedAt: started,
          endedAt: Value(started.add(Duration(milliseconds: 40 + i))),
          durationMs: Value(40 + i),
          metadataJson: Value(jsonEncode(meta))));
      if (i == 0) {
        await db.insertRunEvent(RunEventsCompanion.insert(
            eventId: 'fixture-trace-tool',
            runId: run,
            sequenceNo: 2,
            type: 'tool_call',
            status: 'success',
            name: 'synthetic_tool',
            startedAt: started,
            endedAt: Value(started.add(const Duration(milliseconds: 30))),
            durationMs: const Value(30),
            metadataJson: Value(jsonEncode({
              ...meta,
              'spanId': 'fixture-trace-tool',
              'parentSpanId': id
            }))));
        await db.insertRunEvent(RunEventsCompanion.insert(
            eventId: 'fixture-trace-open',
            runId: run,
            sequenceNo: 3,
            type: 'tool_call',
            status: 'started',
            name: 'synthetic_incomplete_tool',
            startedAt: started,
            metadataJson: Value(jsonEncode({
              ...meta,
              'spanId': 'fixture-trace-open',
              'parentSpanId': id
            }))));
        await db.insertRunEvent(RunEventsCompanion.insert(
            eventId: 'fixture-trace-health',
            runId: run,
            sequenceNo: 4,
            type: 'telemetry_health',
            status: 'failed',
            name: 'synthetic_degradation',
            startedAt: started,
            metadataJson: Value(jsonEncode({
              ...meta,
              'writeFailures': 0,
              'droppedWrites': 1,
              'metadataDrops': 0
            }))));
      }
    }
    _errors.clear();
    _prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _errors.add(details.toString());
      _prevOnError?.call(details);
    };
    final route = _route = MaterialPageRoute<void>(
      builder: (_) => ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          chatControllerProvider.overrideWith(_CoverageChatController.new),
          dashboardSummaryProvider
              .overrideWith((ref) => DashboardService().loadSummary(db: db)),
          jobBoardProvider.overrideWith((ref) async => JobBoard(db)),
          inboxUnreadProvider
              .overrideWith((ref) async => JobBoard(db).unreadCount()),
        ],
        child: _PageCoverageHost(key: _hostKey),
      ),
    );
    _navigator = navigator;
    unawaited(navigator!.push(route));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return {'fixtureOnly': true, 'modelCalls': 0, 'opened': true};
  }
  if (mode == 'web_delivery_save') {
    if (_db == null || _root == null) {
      throw StateError('Open the isolated fixture first');
    }
    _tapFixtureButton(const ValueKey('web-save-delivery'));
    var artifacts = <ProjectArtifact>[];
    final service = ArtifactService(
        rootDirectory: () async =>
            Directory(p.join(_root!.path, 'web-artifacts')));
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      artifacts = await service.list(_db!, projectId: 'project-p');
      if (artifacts.isNotEmpty) break;
    }
    final copied = artifacts.isEmpty
        ? null
        : await service.verifiedPayload(artifacts.last);
    final entries = copied == null
        ? <String>[]
        : ZipDecoder()
            .decodeBytes(await copied.readAsBytes())
            .files
            .map((file) => file.name)
            .toList();
    return {
      'fixtureOnly': true,
      'modelCalls': 0,
      'saved': copied != null && await copied.exists(),
      'artifactCount': artifacts.length,
      'archiveEntries': entries,
      'uiErrors': _errors.length,
      'errors': List<String>.of(_errors)
    };
  }
  if (mode == 'web_delivery_preview') {
    if (_db == null || _root == null) {
      throw StateError('Open the isolated fixture first');
    }
    _tapFixtureButton(const ValueKey('web-open-preview'));
    await Future<void>.delayed(const Duration(seconds: 1));
    return {
      'fixtureOnly': true,
      'modelCalls': 0,
      'uiErrors': _errors.length,
      'errors': List<String>.of(_errors)
    };
  }
  if (mode == 'show') {
    _errors.clear();
    final page = args['page'] ?? 'settings';
    final width = double.tryParse(args['width'] ?? '360') ?? 360.0;
    final height = double.tryParse(args['height'] ?? '0') ?? 0.0;
    final scale = double.tryParse(args['scale'] ?? '1.6') ?? 1.6;
    final dark = args['dark'] == 'true';
    final waitMs = int.tryParse(args['waitMs'] ?? '220') ?? 220;
    await _popInnerSheets();
    _hostKey.currentState!.showPage(
      page,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await Future<void>.delayed(Duration(milliseconds: waitMs));
    return {
      'fixtureOnly': true,
      'modelCalls': 0,
      'page': page,
      'width': width,
      'height': height,
      'scale': scale,
      'dark': dark,
      'uiErrors': _errors.length,
      'errors': List<String>.of(_errors),
    };
  }
  if (mode == 'sheet') {
    _errors.clear();
    _coverageStage = 'prepare_sheet';
    final sheet = args['sheet'] ?? 'confirm_danger_dialog';
    final width = double.tryParse(args['width'] ?? '360') ?? 360.0;
    final height = double.tryParse(args['height'] ?? '0') ?? 0.0;
    final scale = double.tryParse(args['scale'] ?? '1.6') ?? 1.6;
    final dark = args['dark'] == 'true';
    final waitMs = int.tryParse(args['waitMs'] ?? '280') ?? 280;
    await _popInnerSheets();
    _coverageStage = 'previous_sheet_closed';
    await Future<void>.delayed(const Duration(milliseconds: 60));
    _hostKey.currentState!.showPage(
      switch (sheet) {
        'reminder_create_dialog' => 'scheduled_tasks',
        'workflow_run_confirmation' => 'mobile_workflows',
        'cost_budget_dialog' => 'dashboard',
        _ => 'settings',
      },
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    _coverageStage = 'page_changed';
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _coverageStage = 'trigger_sheet';
    _triggerSheet(_sheetContext!, sheet);
    _coverageStage = 'wait_sheet';
    await Future<void>.delayed(Duration(milliseconds: waitMs));
    _coverageStage = 'sheet_ready';
    if (_innerNavKey.currentState?.canPop() != true) {
      _errors.add('弹窗未显示在隔离导航中');
    }
    return {
      'fixtureOnly': true,
      'modelCalls': 0,
      'sheet': sheet,
      'width': width,
      'height': height,
      'scale': scale,
      'dark': dark,
      'uiErrors': _errors.length,
      'errors': List<String>.of(_errors),
    };
  }
  if (mode == 'pop_sheet') {
    await _popInnerSheets();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return {'fixtureOnly': true, 'modelCalls': 0, 'popped': true};
  }
  if (mode == 'close') {
    await _popInnerSheets();
    if (_route?.isActive == true && _route?.isCurrent != true) {
      _navigator?.popUntil((route) => identical(route, _route));
    }
    if (_route?.isActive == true) _navigator?.removeRoute(_route!);
    _route = null;
    FlutterError.onError = _prevOnError;
    _prevOnError = null;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _db?.close();
    _db = null;
    if (_root != null && await _root!.exists()) {
      await _root!.delete(recursive: true);
    }
    _root = null;
    _navigator = null;
    return {'fixtureOnly': true, 'modelCalls': 0, 'closed': true};
  }
  throw ArgumentError('Unsupported mode: $mode');
}

class _PageCoverageHost extends StatefulWidget {
  const _PageCoverageHost({super.key});
  @override
  State<_PageCoverageHost> createState() => _PageCoverageHostState();
}

class _PageCoverageHostState extends State<_PageCoverageHost> {
  String _page = 'settings';
  double _width = 360.0;
  double _height = 0.0;
  double _scale = 1.6;
  bool _dark = false;

  void showPage(
    String page, {
    required double width,
    required double height,
    required double scale,
    required bool dark,
  }) {
    setState(() {
      _page = page;
      _width = width;
      _height = height;
      _scale = scale;
      _dark = dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final resolvedHeight = _height > 0 ? _height : mq.size.height;
    final themeData = _dark ? AppTheme.dark() : AppTheme.light();
    final bgColor = _dark ? AppPalette.darkCanvas : AppPalette.lightCanvas;
    return Theme(
      data: themeData,
      child: ColoredBox(
        color: bgColor,
        child: MediaQuery(
          data: mq.copyWith(
            size: Size(_width, resolvedHeight),
            textScaler: TextScaler.linear(_scale),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: _width,
              height: resolvedHeight,
              child: Navigator(
                key: _innerNavKey,
                pages: [
                  MaterialPage<void>(
                    key: const ValueKey('page-coverage-inner-root'),
                    child: Builder(
                      builder: (ctx) {
                        _sheetContext = ctx;
                        return _buildPage(_page);
                      },
                    ),
                  ),
                ],
                onDidRemovePage: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Never initialize or inherit the real conversation while inspecting fixtures.
class _CoverageChatController extends ChatController {
  @override
  ChatState build() => const ChatState();
}
