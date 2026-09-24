import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/tool_trust_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('会话级授权可读、可撤，且顺序稳定', () async {
    final store = ToolTrustStore();
    await store.init();

    expect(store.sessionAllowed, isEmpty);

    store.allowSession('terminal');
    store.allowSession('edit_file');
    store.allowSession('write_file');

    // 顺序稳定：界面与测试都不该依赖 Set 的插入顺序。
    expect(store.sessionAllowed, ['edit_file', 'terminal', 'write_file']);

    store.revokeSession('terminal');
    expect(store.sessionAllowed, ['edit_file', 'write_file']);

    store.clearSession();
    expect(store.sessionAllowed, isEmpty);
  });

  test('「始终允许」清单可读、可撤，并真正持久化', () async {
    final store = ToolTrustStore();
    await store.init();

    await store.allowAlways('edit_file');
    await store.allowAlways('write_file');
    expect(store.alwaysAllowed, ['edit_file', 'write_file']);

    await store.removeAlways('edit_file');
    expect(store.alwaysAllowed, ['write_file']);

    // 换一个实例从 prefs 读回：撤销若只改了内存，重启后授权会「复活」。
    final reloaded = ToolTrustStore();
    await reloaded.init();
    expect(reloaded.alwaysAllowed, ['write_file']);
  });

  test('会话级授权重启后不保留', () async {
    final store = ToolTrustStore();
    await store.init();
    store.allowSession('terminal');
    expect(store.isTrusted('terminal', ToolRisk.requiresConfirmation), isTrue);

    final reloaded = ToolTrustStore();
    await reloaded.init();
    expect(reloaded.sessionAllowed, isEmpty);
    expect(reloaded.isTrusted('terminal', ToolRisk.requiresConfirmation),
        isFalse);
  });

  test('危险级工具永不因清单条目被放行', () async {
    final store = ToolTrustStore();
    await store.init();
    await store.allowAlways('delete_file');
    store.allowSession('delete_file');

    // 即使清单里存在条目（例如旧版本或异常写入留下的），危险级也必须拦住。
    expect(store.isTrusted('delete_file', ToolRisk.dangerous), isFalse);
  });

  test('未授权时需确认级工具不被放行，安全级直接放行', () async {
    final store = ToolTrustStore();
    await store.init();

    expect(store.isTrusted('terminal', ToolRisk.requiresConfirmation), isFalse);

    store.allowSession('terminal');
    expect(store.isTrusted('terminal', ToolRisk.requiresConfirmation), isTrue);

    expect(store.isTrusted('read_file', ToolRisk.safe), isTrue);
  });
}
