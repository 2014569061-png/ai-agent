import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/isolated_edit_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

/// `HeadlessExecutor` 的健壮性护栏。
///
/// 背景（本轮实测踩到的缺陷）：`headless_executor.dart` 在构造工具注册表时直接
/// `await SharedPreferences.getInstance()`，没有 try/catch。单测或插件缺失环境下
/// 该调用抛 `MissingPluginException`，把**整轮后台执行**判为失败 —— 而紧邻的
/// 注释「单测或旧数据库不可用时不阻断其余只读工具」说明作者本意是单测友好。
///
/// 本文件**故意不**调用 `SharedPreferences.setMockInitialValues`：这里要的就是
/// prefs 不可用的环境，用来验证兜底确实生效。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isolated edit assembly has guarded files but no commands or delegation',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final workspace =
        await Directory.systemTemp.createTemp('nexus-isolated-tools-');
    addTearDown(() => workspace.delete(recursive: true));
    final assembled = await HeadlessExecutor.assembleTools(
      db: db,
      config: const ProviderConfig(
          baseUrl: 'https://unused.invalid/v1', model: 'demo', apiKey: ''),
      workspacePath: workspace.path,
      allowedToolNames: IsolatedEditService.tools,
      loadExternalTools: false,
    );
    addTearDown(assembled.mcpProvider.dispose);
    for (final name in IsolatedEditService.tools) {
      expect(assembled.registry.find(name), isNotNull, reason: name);
    }
    for (final name in [
      'terminal',
      'http_request',
      'sub_agent',
      'sub_agent_edit',
      'delete_file',
      'move_file'
    ]) {
      expect(assembled.registry.find(name), isNull, reason: name);
    }
    await File('${workspace.path}/a.txt').writeAsString('old');
    final result = await assembled.registry
        .findExecutor('write_file')!
        .execute({'path': 'a.txt', 'content': 'new'});
    expect(result.ok, isFalse,
        reason: 'isolated tools still require read-before-write');
  });

  test('SharedPreferences 不可用时 HeadlessExecutor 仍能完整跑完一轮', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // apiKey 为空 + 非本地 baseUrl ⇒ isConfigured=false ⇒ 走 DemoProvider，
    // 不产生任何网络请求。注意不能用 127.0.0.1：`ProviderConfig.isConfigured`
    // 对本地地址（Ollama / LM Studio）即使无 Key 也判定为已配置。
    final result = await HeadlessExecutor.runDetailed(
      db: db,
      config: const ProviderConfig(
          baseUrl: 'https://unused.invalid/v1',
          model: 'demo-model',
          apiKey: ''),
      prompt: '你好',
    );

    expect(result.succeeded, isTrue,
        reason: 'status=${result.status} error=${result.error} '
            'text=${result.text}');
    expect(result.text, isNotEmpty);
  });

  test('implement-and-verify headless runs register write and terminal tools',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final workspace = await Directory.systemTemp.createTemp('nexus-headless-');
    addTearDown(() => workspace.delete(recursive: true));

    final assembled = await HeadlessExecutor.assembleTools(
      db: db,
      config: const ProviderConfig(
          baseUrl: 'https://unused.invalid/v1',
          model: 'demo-model',
          apiKey: ''),
      taskType: 'implement_and_verify',
      workspacePath: workspace.path,
    );
    addTearDown(assembled.mcpProvider.dispose);

    expect(assembled.registry.find('edit_file'), isNotNull);
    expect(assembled.registry.find('apply_patch'), isNotNull);
    expect(assembled.registry.find('repo_map'), isNotNull);
    expect(assembled.registry.find('write_file'), isNotNull);
    expect(assembled.registry.find('terminal'), isNotNull);
  });

  test('read-only collaboration headless runs keep workspace tools read-only',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final workspace = await Directory.systemTemp.createTemp('nexus-headless-');
    addTearDown(() => workspace.delete(recursive: true));

    final assembled = await HeadlessExecutor.assembleTools(
      db: db,
      config: const ProviderConfig(
          baseUrl: 'https://unused.invalid/v1',
          model: 'demo-model',
          apiKey: ''),
      taskType: 'code_review',
      workspacePath: workspace.path,
      allowedToolNames: const [
        'read_file',
        'list_directory',
        'search_files',
        'repo_map'
      ],
    );
    addTearDown(assembled.mcpProvider.dispose);

    expect(assembled.registry.find('read_file'), isNotNull);
    expect(assembled.registry.find('edit_file'), isNull);
    expect(assembled.registry.find('apply_patch'), isNull);
    expect(assembled.registry.find('repo_map'), isNotNull);
    expect(assembled.registry.find('terminal'), isNull);
  });
}
