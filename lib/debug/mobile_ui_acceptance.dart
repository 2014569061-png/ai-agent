/// Explicit, debug-only UI fixtures for live Android acceptance.
/// Uses an isolated in-memory database and an owned temporary directory.
/// No model calls, user database writes, or real approvals are performed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/artifact_service.dart';
import '../application/error_humanizer.dart';
import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/result_card.dart';
import '../presentation/chat/widgets/result_card_view.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/command_tool.dart';
import '../infrastructure/terminal/termux_ssh_credentials.dart';
import '../presentation/chat/widgets/chat_message_list.dart';
import '../presentation/chat/widgets/floating_capsule_input.dart';
import '../presentation/chat/widgets/tool_approval_sheet.dart';
import '../presentation/projects/project_home_page.dart';
import '../presentation/theme/app_theme.dart';
import '../presentation/theme/app_palette.dart';
import '../presentation/widgets/nexus_page_header.dart';
import '../presentation/widgets/nexus_sheet.dart';
import '../presentation/workspace/terminal_sheet.dart';
import '../presentation/workspace/workspace_editor_page.dart';
import '../presentation/terminal/terminal_page.dart';

const _projectId = 'isolated-mobile-ui-acceptance';
const _editorName = 'README-mobile-ui-acceptance.md';
final _hostKey = GlobalKey<_FixtureHostState>();
GlobalKey<_ComplexChatState>? _chatKey;
AppDatabase? _database;
Directory? _root;
Route<void>? _outerRoute;
NavigatorState? _outerNavigator;
final _frames = <FrameTiming>[];
int _retryCount = 0;
int _approvalCount = 0;
bool _recording = false;

bool verifyDebugOnly() => kDebugMode;

// Separate from the isolated fixture: observe the real navigation without
// opening fixtures, sending messages or touching the user's database.
final _motionFrames = <FrameTiming>[];
Timer? _motionCaptureTimer;

void _recordMotionFrames(List<FrameTiming> frames) {
  _motionFrames.addAll(frames);
  if (_motionFrames.length > 1024) {
    _motionFrames.removeRange(0, _motionFrames.length - 1024);
  }
}

String startMobileMotionTimings() {
  if (!kDebugMode) return 'disabled';
  if (_motionCaptureTimer != null) {
    WidgetsBinding.instance.removeTimingsCallback(_recordMotionFrames);
  }
  _motionCaptureTimer?.cancel();
  _motionFrames.clear();
  WidgetsBinding.instance.addTimingsCallback(_recordMotionFrames);
  // A disconnected diagnostic client must not leave a collector running.
  _motionCaptureTimer = Timer(const Duration(seconds: 20), () {
    WidgetsBinding.instance.removeTimingsCallback(_recordMotionFrames);
    _motionCaptureTimer = null;
  });
  return 'debug-motion-sampling';
}

String finishMobileMotionTimings() {
  if (!kDebugMode) return 'disabled';
  if (_motionCaptureTimer != null) {
    WidgetsBinding.instance.removeTimingsCallback(_recordMotionFrames);
  }
  _motionCaptureTimer?.cancel();
  _motionCaptureTimer = null;
  return jsonEncode({
    'mode': 'debug',
    'displayHz': WidgetsBinding
        .instance.platformDispatcher.views.first.display.refreshRate,
    'columns': ['frame', 'buildUs', 'rasterUs', 'totalUs', 'vsyncStartUs'],
    'frames': [
      for (final frame in _motionFrames)
        [
          frame.frameNumber,
          frame.buildDuration.inMicroseconds,
          frame.rasterDuration.inMicroseconds,
          frame.totalSpan.inMicroseconds,
          frame.timestampInMicroseconds(FramePhase.vsyncStart),
        ],
    ],
  });
}

void _recordFrames(List<FrameTiming> frames) {
  _frames.addAll(frames);
  if (_frames.length > 1024) _frames.removeRange(0, _frames.length - 1024);
}

NavigatorState _findRootNavigator() {
  NavigatorState? navigator;
  void visit(Element element) {
    if (navigator != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      navigator = element.state as NavigatorState;
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return navigator ?? (throw StateError('No active app navigator.'));
}

Future<String> openMobileProjectFixture() async {
  if (!kDebugMode) return 'disabled';
  await closeMobileUiFixture();
  _outerNavigator = _findRootNavigator();
  final root =
      _root = await Directory.systemTemp.createTemp('mobile-ui-acceptance-');
  final database = _database = AppDatabase(NativeDatabase.memory());
  final now = DateTime.now();
  try {
    await File('${root.path}/index.html').writeAsString(
        '<!doctype html><meta charset="utf-8"><title>Isolated UI fixture</title><h1>移动端预览验收样例</h1>');
    await File('${root.path}/$_editorName').writeAsString(
        '# 隔离编辑器验收样例\n\nOnly this temporary file may be edited during live acceptance.\n');
    await File('${root.path}/文件名非常长_用于验证文件树省略与完整路径提示_mobile_acceptance.txt')
        .writeAsString('Isolated long filename fixture.');
    await File('${root.path}/large-mobile-ui-acceptance.txt').writeAsString(
        List.filled(20000,
                'Large file acceptance fixture with a deliberately long line.')
            .join('\n'));
    await database.insertProject(ProjectsCompanion.insert(
      id: _projectId,
      name: '验收样例 · 超长项目名称与任务产物布局回归',
      canonicalRootPath: root.path,
      createdAt: now,
      updatedAt: now,
    ));
    const statuses = [
      'running',
      'waiting_approval',
      'completed',
      'failed',
      'queued'
    ];
    for (var i = 0; i < statuses.length; i++) {
      await database.into(database.tasks).insert(TasksCompanion.insert(
            id: 'isolated-task-$i',
            conversationId: '',
            projectId: const Value(_projectId),
            status: Value(statuses[i]),
            requestJson: jsonEncode({
              'title': '隔离样例 ${i + 1} · 需要检查长名称、状态标签与完整操作的移动端开发任务',
              'prompt': '仅进行 UI 布局验收，不执行真实 Agent 或外部请求。',
              'model':
                  'organization/deepseek-mobile-acceptance-long-model-name',
              'workspacePath': root.path,
            }),
            progressJson: Value(jsonEncode({'summary': '这是隔离样例，不代表真实执行结果。'})),
            createdAt: now.subtract(Duration(minutes: i)),
            updatedAt: now.subtract(Duration(minutes: i)),
          ));
    }
    final artifacts = <String, String>{
      'index.html': 'web',
      '多按钮与长名称产物布局检查_mobile_acceptance_report.html': 'web',
      '仅用于失败状态检查_不可安装_mobile_acceptance.apk': 'apk',
    };
    var i = 0;
    for (final entry in artifacts.entries) {
      final file = File('${root.path}/${entry.key}');
      if (!await file.exists()) {
        await file.writeAsString(entry.value == 'apk'
            ? ''
            : '<!doctype html><h1>Isolated fixture</h1>');
      }
      final bytes = await file.readAsBytes();
      await database.saveArtifactRecord({
        'id': 'isolated-artifact-${i++}',
        'projectId': _projectId,
        'taskId': 'isolated-task-2',
        'runId': '',
        'kind': entry.value,
        'relativePath': entry.key,
        'hash': ArtifactService.hashBytes(bytes),
        'bytes': bytes.length,
        'createdAt': now.toIso8601String(),
        'inspectionJson': {
          'fixture': true,
          'manual': true,
          'installable': false
        },
      });
    }
    _frames.clear();
    _retryCount = 0;
    _approvalCount = 0;
    WidgetsBinding.instance.addTimingsCallback(_recordFrames);
    _recording = true;
    final route = _outerRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'isolated-mobile-ui-acceptance'),
      builder: (_) => ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => database)],
        child: _FixtureHost(key: _hostKey),
      ),
    );
    unawaited(_outerNavigator!.push(route));
    await WidgetsBinding.instance.endOfFrame;
    return mobileUiFixtureStatus();
  } catch (_) {
    await closeMobileUiFixture();
    rethrow;
  }
}

String setMobileFixtureDark() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState?.setDark(true);
  return 'dark';
}

String setMobileFixtureLight() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState?.setDark(false);
  return 'light';
}

String showMobileProjectFixture() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState!.navigatorKey.currentState!
      .popUntil((route) => route.isFirst);
  return 'isolated-project-visible';
}

String openMobileEditorFixture() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState!.open(WorkspaceEditorPage(
    workspacePath: _root!.path,
    relativePath: _editorName,
  ));
  return 'isolated-editor-opened';
}

String openMobileLargeFileFixture() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState!.open(WorkspaceEditorPage(
    workspacePath: _root!.path,
    relativePath: 'large-mobile-ui-acceptance.txt',
  ));
  return 'isolated-large-file-opened';
}

String resetMobileFixtureTimings() {
  if (!kDebugMode) return 'disabled';
  _frames.clear();
  return 'timings-reset';
}

Future<String> openMobileChatFixture() async {
  if (!kDebugMode) return 'disabled';
  if (_database == null) await openMobileProjectFixture();
  _chatKey = GlobalKey<_ComplexChatState>();
  _hostKey.currentState!.open(_ComplexChat(key: _chatKey));
  await WidgetsBinding.instance.endOfFrame;
  return mobileUiFixtureStatus();
}

Future<String> openMobileResultFixture() async {
  if (!kDebugMode) return 'disabled';
  if (_database == null) await openMobileProjectFixture();
  _hostKey.currentState!.open(Scaffold(
    appBar: const NexusPageHeader(title: '隔离样例 · 成果状态'),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      for (final status in [
        ResultCardStatus.active,
        ResultCardStatus.changed,
        ResultCardStatus.unavailable
      ])
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ResultCardView(
              card: ResultCard(
                  id: 'isolated-result-${status.name}',
                  kind: ResultCardKind.file,
                  resourceType: 'artifact',
                  resourceId: 'isolated-long-resource-identifier',
                  resourceVersion: 1,
                  title: '项目分析报告与后续改进建议.md',
                  summary: '已整理项目结构与待处理事项。',
                  status: status),
              onAction: (_) {},
              onRefresh: () {},
            )),
    ]),
  ));
  return 'isolated-result-opened';
}

Future<String> openMobileApprovalFixture() async {
  if (!kDebugMode) return 'disabled';
  final context = _hostKey.currentState!.navigatorKey.currentState!.context;
  unawaited(showNexusSheet<dynamic>(
    context: context,
    barrierLabel: '关闭审批弹窗',
    builder: (_) => ToolApprovalSheet(
      call: ToolCall(id: 'isolated-approval', name: 'edit_file', arguments: {
        'path': '${_root!.path}/$_editorName',
        'description': '仅用于长参数审批布局验收，不会执行任何文件修改。',
      }),
      risk: ToolRisk.requiresConfirmation,
      allowSessionTrust: false,
    ),
  ).then((decision) {
    if (decision != null) _approvalCount++;
  }));
  return 'isolated-approval-opened';
}

String unfocusMobileFixtureInputs() {
  if (!kDebugMode) return 'disabled';
  FocusManager.instance.primaryFocus?.unfocus();
  return 'fixture-input-unfocused';
}

String openMobileSshFailureFixture() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState!.open(const TerminalPage(
      initialConfig: SSHTerminalConfig(
    host: '127.0.0.1',
    port: 1,
    username: 'mobile_ui_fixture',
    label: '隔离样例 · 本机关闭端口',
  )));
  return 'loopback-ssh-failure-fixture';
}

String openMobileSshDisconnectedFixture() {
  if (!kDebugMode) return 'disabled';
  _hostKey.currentState!.open(const TerminalPage(
      autoConnect: false,
      initialConfig: SSHTerminalConfig(
        host: '127.0.0.1',
        port: 1,
        username: 'mobile_ui_fixture',
        label: '隔离样例 · 未连接',
      )));
  return 'ssh-disconnected-fixture';
}

Future<String> openMobileTerminalFixture() async {
  if (!kDebugMode) return 'disabled';
  if (_database == null) await openMobileProjectFixture();
  final service = TerminalCommandService(workspacePath: _root!.path);
  await service.startJob(
    command:
        r'i=0; while [ "$i" -lt 160 ]; do printf "mobile UI acceptance output line %s with a deliberately long log entry\n" "$i"; i=$((i+1)); done; printf "controlled failure exit 7\n"; exit 7',
    workingDirectory: _root!.path,
  );
  _hostKey.currentState!.open(Scaffold(
    appBar: const NexusPageHeader(title: '隔离终端样例'),
    body: TerminalSheet(
        workspacePath: _root!.path, sharedService: service, embedded: true),
  ));
  return 'isolated-terminal-opened';
}

String scrollMobileChatToEnd() {
  if (!kDebugMode) return 'disabled';
  _chatKey?.currentState?.scrollToEnd();
  return 'scrolled';
}

String startMobileChatStreamingFixture() {
  if (!kDebugMode) return 'disabled';
  _chatKey?.currentState?.setRunning(true);
  return 'local-streaming-state';
}

String mobileUiFixtureStatus() {
  if (!kDebugMode) return 'disabled';
  double percentile(List<int> values) {
    if (values.isEmpty) return 0;
    values.sort();
    return values[((values.length - 1) * .95).floor()] / 1000;
  }

  final editor = _root == null ? null : File('${_root!.path}/$_editorName');
  return jsonEncode({
    'source': 'isolated-memory-fixture',
    'active': _database != null,
    'mounted': _hostKey.currentState?.mounted == true,
    'workspace': _root?.path,
    'theme': _hostKey.currentState?.dark == true ? 'dark' : 'light',
    'chatMessages': _chatKey?.currentState?.messages.length ?? 0,
    'retries': _retryCount,
    'approvals': _approvalCount,
    'editorProbeSaved': editor != null &&
        editor.existsSync() &&
        editor.readAsStringSync().contains('mcp_ui_keyboard_probe'),
    'frames': _frames.length,
    'buildP95Ms':
        percentile(_frames.map((f) => f.buildDuration.inMicroseconds).toList()),
    'rasterP95Ms': percentile(
        _frames.map((f) => f.rasterDuration.inMicroseconds).toList()),
  });
}

Future<String> closeMobileUiFixture() async {
  if (!kDebugMode) return 'disabled';
  if (_outerRoute?.isActive == true) {
    _outerNavigator!.popUntil((route) => identical(route, _outerRoute));
    _outerNavigator!.pop();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  _outerRoute = null;
  if (_recording) WidgetsBinding.instance.removeTimingsCallback(_recordFrames);
  _recording = false;
  final database = _database;
  _database = null;
  await database?.close();
  final root = _root;
  _root = null;
  if (root != null &&
      root.parent.path == Directory.systemTemp.path &&
      root.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('mobile-ui-acceptance-') &&
      await root.exists()) {
    await root.delete(recursive: true);
  }
  return 'isolated-fixture-closed';
}

class _FixtureHost extends StatefulWidget {
  const _FixtureHost({super.key});
  @override
  State<_FixtureHost> createState() => _FixtureHostState();
}

class _FixtureHostState extends State<_FixtureHost> {
  final navigatorKey = GlobalKey<NavigatorState>();
  bool dark = false;
  void setDark(bool value) => setState(() => dark = value);
  void open(Widget page) => navigatorKey.currentState!.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => page), (route) => route.isFirst);
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppPalette.darkCanvas
              : AppPalette.lightCanvas,
          child: child!,
        ),
        home: const ProjectHomePage(projectId: _projectId),
      );
}

class _ComplexChat extends StatefulWidget {
  const _ComplexChat({super.key});
  @override
  State<_ComplexChat> createState() => _ComplexChatState();
}

class _ComplexChatState extends State<_ComplexChat> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  ChatMode mode = ChatMode.agent;
  bool running = false;
  late final List<ChatMessage> messages;
  @override
  void initState() {
    super.initState();
    final code = List.generate(
            90, (i) => 'final example$i = "long mobile code example $i";')
        .join('\n');
    messages = [
      for (var i = 0; i < 120; i++)
        ChatMessage(
          id: 'isolated-message-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          parts: [MessagePart.text('隔离长会话消息 $i · 保留上下文与滚动位置的验收样例。')],
        ),
      ChatMessage(role: MessageRole.assistant, parts: [
        MessagePart.text(
            '长代码块样例：\n```dart\n$code\n${List.filled(260, "x").join()}\n```')
      ]),
      ChatMessage(role: MessageRole.assistant, parts: const [
        MessagePart.text('工具卡片样例')
      ], toolCalls: [
        ToolCall(
            id: 'isolated-tool',
            name: 'read_file',
            arguments: {'path': '${_root!.path}/$_editorName', 'limit': 200}),
      ]),
      ChatMessage(role: MessageRole.tool, toolCallId: 'isolated-tool', parts: [
        MessagePart.text(
            jsonEncode({'ok': false, 'error': '本地样例：读取失败，保留长参数与恢复提示。'}))
      ]),
      ChatMessage(role: MessageRole.user, parts: [
        MessagePart.file(
            '${_root!.path}/文件名非常长_用于验证文件树省略与完整路径提示_mobile_acceptance.txt',
            mimeType: 'text/plain')
      ]),
      ChatMessage(
          role: MessageRole.assistant,
          modelName: 'organization/mobile-acceptance-very-long-model-name',
          parts: [MessagePart.text(formatErrorForMessage('timeout'))]),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToEnd());
  }

  void scrollToEnd() {
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  }

  void setRunning(bool value) => setState(() => running = value);
  void retry() {
    _retryCount++;
    setState(() => messages[messages.length - 1] = ChatMessage(
          role: MessageRole.assistant,
          parts: const [MessagePart.text('本地重试回调已响应，未调用模型。')],
        ));
  }

  @override
  void dispose() {
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: NexusPageHeader(title: '隔离样例 · 复杂聊天', actions: [
          const IconButton(
              tooltip: '审批样例',
              onPressed: openMobileApprovalFixture,
              icon: Icon(Icons.verified_user_outlined)),
          IconButton(
              tooltip: '回到最新',
              onPressed: scrollToEnd,
              icon: const Icon(Icons.vertical_align_bottom)),
        ]),
        body: ChatMessageList(
            messages: messages,
            controller: scroll,
            running: running,
            onLongPress: (_) {},
            onRegenerate: retry,
            onStop: () => setRunning(false),
            onEditPrompt: () {},
            onSwitchModel: () {},
            sessionKey: 'isolated-mobile-chat'),
        bottomNavigationBar: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .45),
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingCapsuleInput(
                controller: controller,
                isRunning: running,
                modeLabel: switch (mode) {
                  ChatMode.chat => '聊天',
                  ChatMode.agent => 'Agent',
                  ChatMode.plan => '计划',
                },
                onSend: () {
                  controller.clear();
                },
                onStop: () => setRunning(false),
                onAttachmentMenu: openMobileApprovalFixture,
                onModeTap: () => setState(() {
                  mode = ChatMode.values[(mode.index + 1) % ChatMode.values.length];
                }),
                onApprovalModeTap: openMobileApprovalFixture),
          ])),
        ),
      );
}
