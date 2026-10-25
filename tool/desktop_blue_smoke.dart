// Native acceptance harness. Uses an isolated repository, in-memory database
// and mock UI preferences; never reads accounts or sends model requests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/desktop_device_service.dart';
import 'package:mobile_agent/application/desktop_git_service.dart';
import 'package:mobile_agent/application/desktop_preview_service.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/navigation/app_shell.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

late String smokeRoot;
const smokeHtml = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<style>body{margin:0;padding:20px;background:#f3f6fc;font:14px system-ui;color:#172b4d}
h1{font-size:20px}article{background:white;padding:20px;margin:12px 0;border:1px solid #dfe7f2;border-radius:8px}
progress{width:100%;accent-color:#2563eb}small{color:#64748b}</style>
<h1>验收演示网页</h1><small>NEXUS · 实际 HTML 预览</small>
<article><b>首页视觉优化</b><p>统一蓝白主题与任务卡片</p><progress value="68" max="100"></progress></article>
<article><b>整理项目文档</b><p>开发约定与项目结构已整理</p></article></html>''';

class SmokeChat extends ChatController {
  @override
  ChatState build() => ChatState(
      loading: false,
      providerConfigured: true,
      currentProjectId: 'smoke-project',
      currentWorkspacePath: smokeRoot,
      currentProjectName: '隔离验收项目',
      conversationId: 'smoke-chat',
      conversationTitle: '首页蓝白主题',
      activeModel: '验收模式（不调用模型）',
      mode: ChatMode.agent,
      messages: [
        ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('统一蓝白配色，并优化任务卡片。')]),
        ChatMessage(role: MessageRole.assistant, parts: const [
          MessagePart.text('这里使用隔离的验收项目。右侧差异来自实际 Git 文件，预览读取真实 HTML。')
        ]),
      ],
      planState: const PlanState(status: 'executing', steps: [
        PlanStep(id: '1', description: '统一颜色与字体', status: 'completed'),
        PlanStep(id: '2', description: '优化任务卡片', status: 'completed'),
        PlanStep(id: '3', description: '验证响应式布局', status: 'running'),
      ]));
}

class SmokeDevices extends DesktopDevicesController {
  @override
  Future<DesktopDeviceSnapshot> build() async => const DesktopDeviceSnapshot();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This executable is an acceptance test, with isolated preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'chat.provider_hint_dismissed': true,
    'desktop.layout.version': 2,
    'desktop.side.width': 560.0,
    'desktop.terminal.open': true
  });
  smokeRoot =
      (await Directory.systemTemp.createTemp('nexus-blue-native-')).path;
  Future<void> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: smokeRoot);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
  }

  await git(['init', '-q', '--initial-branch=ui/blue-white']);
  await git(['config', 'user.name', 'NEXUS Acceptance']);
  await git(['config', 'user.email', 'acceptance@example.invalid']);
  final file = File(p.join(smokeRoot, 'app_theme.dart'));
  await file.writeAsString(
      'class AppColors {\n  static const primary = 0xFF23856D;\n}\n');
  await File(p.join(smokeRoot, 'index.html')).writeAsString(smokeHtml);
  await git(['add', '--', 'app_theme.dart', 'index.html']);
  await git(['commit', '-qm', 'isolated acceptance fixture']);
  await file.writeAsString(
      'class AppColors {\n  static const primary = 0xFF2563EB;\n'
      '  static const surface = 0xFFFFFFFF;\n  static const background = 0xFFF3F6FC;\n}\n');
  final database = AppDatabase(NativeDatabase.memory());
  final now = DateTime.now();
  await database.into(database.projects).insert(ProjectsCompanion.insert(
      id: 'smoke-project',
      name: '隔离验收项目',
      canonicalRootPath: smokeRoot,
      createdAt: now,
      updatedAt: now));
  await database.into(database.conversations).insert(
      ConversationsCompanion.insert(
          id: 'smoke-chat',
          title: const Value('首页蓝白主题'),
          projectId: const Value('smoke-project'),
          createdAt: now,
          updatedAt: now));
  runApp(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => database),
        chatControllerProvider.overrideWith(SmokeChat.new),
        desktopDevicesProvider.overrideWith(SmokeDevices.new),
      ],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DesktopTheme.apply(ThemeData(useMaterial3: true)),
          home: const Stack(children: [
            DesktopShell(),
            Positioned(
                right: 0,
                bottom: 0,
                width: 2,
                height: 2,
                child: _NativeProbe()),
          ]))));
}

class _NativeProbe extends StatefulWidget {
  const _NativeProbe();
  @override
  State<_NativeProbe> createState() => _NativeProbeState();
}

class _NativeProbeState extends State<_NativeProbe> {
  final _controller = WebviewController();
  final _server = DesktopPreviewServer();
  late final AppLifecycleListener _lifecycle;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      debugPrint('Native acceptance: releasing probe on close');
      setState(() => _closing = true);
      await WidgetsBinding.instance.endOfFrame;
      await _controller.dispose();
      debugPrint('Native acceptance: probe released');
      await _server.stop();
      return AppExitResponse.exit;
    });
    unawaited(_verify());
  }

  Future<void> _verify() async {
    final report = <String, dynamic>{'isolated': true, 'workspace': smokeRoot};
    try {
      report['webviewVersion'] = await WebviewController.getWebViewVersion();
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      if (mounted) setState(() {});
      final url = await _server.start(smokeRoot, 'index.html');
      final loaded = _controller.loadingState
          .firstWhere((state) => state == LoadingState.navigationCompleted);
      await _controller.loadUrl('$url');
      await loaded.timeout(const Duration(seconds: 15));
      report['heading'] = await _controller
          .executeScript("document.querySelector('h1').textContent");
      final git = const DesktopGitService();
      final snapshot = await git.inspect(smokeRoot);
      await git.stage(snapshot, snapshot.files.single);
      final staged = await git.inspect(smokeRoot);
      report['staged'] = staged.files.single.staged;
      await git.unstage(staged, staged.files.single);
      report['unstaged'] = (await git.inspect(smokeRoot)).files.single.unstaged;
      await Future<void>.delayed(const Duration(seconds: 1));
      var opened = false;
      var terminalStarted = false;
      void visit(Element element) {
        final widget = element.widget;
        if (!opened &&
            widget is TextButton &&
            widget.child is Text &&
            (widget.child as Text).data == '预览项目') {
          widget.onPressed?.call();
          opened = true;
        }
        if (!terminalStarted &&
            widget is TextField &&
            widget.decoration?.hintText == '例如 git status') {
          widget.controller!.text = 'git diff --stat';
          widget.onSubmitted?.call(widget.controller!.text);
          terminalStarted = true;
        }
        element.visitChildElements(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildElements(visit);
      report['previewActionInvoked'] = opened;
      String? terminalOutput;
      void readOutput(Element element) {
        final widget = element.widget;
        if (widget is SelectableText &&
            widget.data?.contains('[退出码 0]') == true) {
          terminalOutput = widget.data;
        }
        element.visitChildElements(readOutput);
      }

      for (var attempt = 0; attempt < 40 && terminalOutput == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        WidgetsBinding.instance.rootElement?.visitChildElements(readOutput);
      }
      report['terminalOutput'] = terminalOutput;
      report['passed'] = report['heading'] == '验收演示网页' &&
          report['staged'] == true &&
          report['unstaged'] == true &&
          opened &&
          terminalOutput?.contains('app_theme.dart') == true;
    } catch (error, stack) {
      report['passed'] = false;
      report['error'] = '$error';
      report['stack'] = '$stack';
    }
    await File('artifacts/desktop/blue-native-probe.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_controller.dispose());
    unawaited(_server.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_closing &&
          _controller.value.isInitialized
      ? Webview(_controller,
          permissionRequested: (_, __, ___) => WebviewPermissionDecision.deny)
      : const SizedBox.shrink();
}
