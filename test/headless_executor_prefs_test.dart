import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/headless_executor.dart';
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
}
