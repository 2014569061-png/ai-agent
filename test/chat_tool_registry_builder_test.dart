import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_tool_registry_builder.dart';
import 'package:mobile_agent/application/browser_session_service.dart';
import 'package:mobile_agent/application/android_accessibility_session_service.dart';
import 'package:mobile_agent/domain/browser_session.dart';
import 'package:mobile_agent/infrastructure/tools/android_accessibility_bridge.dart';
import 'package:mobile_agent/application/run_tool_settings.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tool_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory workspace;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
    workspace = await Directory.systemTemp.createTemp('run-tool-registry-');
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await workspace.delete(recursive: true);
  });

  Future<ToolRegistry> build({
    Set<String> enabled = const {},
    ToolSettings settings = const ToolSettings(),
    BrowserSessionService? browser,
    AndroidAccessibilitySessionService? accessibility,
    String? conversationId,
  }) =>
      buildChatToolRegistry(
        enabledTools: enabled,
        tavilyKey: '',
        config: const ProviderConfig(
            baseUrl: 'https://unused.invalid/v1', model: 'test', apiKey: ''),
        subAgentRisk: ToolRisk.requiresConfirmation,
        settings: settings,
        browser: browser,
        accessibility: accessibility,
        conversationId: conversationId,
        workspacePath: workspace.path,
        database: () => throw StateError('No database required for this run'),
        onRunSubAgent: (_, __, ___) async => 'subtask',
        onPlanUpdated: (_) async {},
      );

  test('global switches remove workspace and network capabilities', () async {
    final registry = await build(
      enabled: {'calculator', 'web_search'},
      settings: const ToolSettings(workspaceFiles: false),
    );
    expect(registry.find('calculator'), isNotNull);
    expect(registry.find('web_search'), isNull);
    expect(registry.find('read_file'), isNull);
    expect(registry.find('terminal'), isNull);
    expect(registry.find('manage_plan'), isNotNull);
  });

  test('browser capability is limited to an explicitly opened Android owner',
      () async {
    final browser = BrowserSessionService(_BrowserTransport());
    addTearDown(browser.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
        (await build(browser: browser, conversationId: 'owner'))
            .find('browser'),
        isNull);
    await browser.open('owner');
    expect(
        (await build(browser: browser, conversationId: 'owner'))
            .find('browser'),
        isNotNull);
    expect(
        (await build(browser: browser, conversationId: 'other'))
            .find('browser'),
        isNull);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
        (await build(browser: browser, conversationId: 'owner'))
            .find('browser'),
        isNull);
    await browser.close();
  });

  test(
      'accessibility observation is registered only for its active Android owner',
      () async {
    final accessibility = AndroidAccessibilitySessionService(
      _AccessibilityBridge(),
    );
    addTearDown(accessibility.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      (await build(
        accessibility: accessibility,
        conversationId: 'owner',
      ))
          .find('android_accessibility_observe'),
      isNull,
    );
    await accessibility.beginSession('owner');
    expect(
      (await build(
        accessibility: accessibility,
        conversationId: 'owner',
      ))
          .find('android_accessibility_observe'),
      isNotNull,
    );
    expect(
      (await build(
        accessibility: accessibility,
        conversationId: 'other',
      ))
          .find('android_accessibility_observe'),
      isNull,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      (await build(
        accessibility: accessibility,
        conversationId: 'owner',
      ))
          .find('android_accessibility_observe'),
      isNull,
    );
    await accessibility.endSession();
  });

  test('missing optional skills database retains the remaining tools',
      () async {
    final registry = await build(enabled: {'skills_read', 'calculator'});
    expect(registry.find('skills_read'), isNull);
    expect(registry.find('calculator'), isNotNull);
    expect(registry.find('read_file'), isNotNull);
    expect(registry.find('sub_agent')?.manifest.risk,
        ToolRisk.requiresConfirmation);
  });

  test(
      'assembled file tools share read-before-write and reject external changes',
      () async {
    final file = File('${workspace.path}/source.txt');
    await file.writeAsString('before');
    final registry = await build(settings: const ToolSettings(terminal: false));
    final edit = registry.find('edit_file')!;
    final arguments = {
      'path': 'source.txt',
      'targetContent': 'before',
      'replacementContent': 'after',
    };
    expect((await edit.execute(arguments)).code, ToolCodes.readRequired);
    expect(
        (await registry.find('read_file')!.execute({'path': 'source.txt'})).ok,
        isTrue);
    expect((await edit.execute(arguments)).ok, isTrue);
    expect(await file.readAsString(), 'after');
    await registry.find('read_file')!.execute({'path': 'source.txt'});
    await file.writeAsString('external change');
    expect(
        (await edit.execute({
          ...arguments,
          'targetContent': 'after',
        }))
            .code,
        ToolCodes.revisionConflict);
    expect(await file.readAsString(), 'external change');
    expect(registry.find('terminal'), isNull);
  });

  test('read-only workspace sets cannot expose writes or terminal', () {
    final names = workspaceToolSet(
      workspacePath: workspace.path,
      allowWrites: false,
    ).map((tool) => tool.manifest.name);
    expect(
        names,
        unorderedEquals([
          'read_file',
          'repo_map',
          'list_directory',
          'search_files',
        ]));
  });

  test('separate switches override the legacy combined permission', () async {
    SharedPreferences.setMockInitialValues({
      'settings.tool.terminal_file': true,
      'settings.tool.workspace_files': false,
      'settings.tool.terminal': false,
    });
    final settings = await ToolSettings.load(webBrowsing: true);
    expect(settings.workspaceFiles, isFalse);
    expect(settings.terminal, isFalse);
    expect(settings.webBrowsing, isTrue);
    final registry = await build(settings: settings);
    expect(registry.find('read_file'), isNull);
    expect(registry.find('terminal'), isNull);
  });
}

class _BrowserTransport implements BrowserTransport {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> invoke(
          String method, Map<String, dynamic> args) async =>
      method == 'open'
          ? {'sessionId': 'fixture', 'epoch': 1, 'mode': 'user'}
          : {};
}

class _AccessibilityBridge extends AndroidAccessibilityBridge {
  @override
  Future<Map<String, dynamic>> beginSession(String ownerId) async =>
      {'ok': true, 'sessionId': 'accessibility-session'};

  @override
  Future<Map<String, dynamic>> endSession(String? ownerId) async =>
      {'ok': true};
}
