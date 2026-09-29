// 阶段 1 接线：真实 ChatController 发送消息时双写会话日志，并与 Messages
// 表做影子比对（非 system 消息的角色与文本顺序一致）。
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/application/session_log/session_log_settings.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';

void main() {
  test('chat runs dual-write a session log that matches the messages table',
      () async {
    expect(SessionLogSettings.dualWrite, isTrue,
        reason: '测试运行在 debug 模式，双写默认开启');
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      providerConfigStoreProvider.overrideWith((ref) => _FakeConfigStore()),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();

    Future<ToolApproval> allow(ToolCall call, ToolRisk risk, bool s) async =>
        ToolApproval.allowOnce;
    await controller.send(text: '第一问', attachments: const [], approveTool: allow);
    await controller.send(text: '第二问', attachments: const [], approveTool: allow);
    // 日志写入在后台队列中完成。
    await pumpEventQueue(times: 50);

    final state = container.read(chatControllerProvider);
    final conversationId = state.conversationId!;
    final log = SessionLogReader(
        await DriftSessionEventStore(db).events(conversationId));

    final types = log.events.map((e) => e.type).toList();
    expect(types.where((t) => t == SessionEventType.turnStart), hasLength(2));
    expect(types.where((t) => t == SessionEventType.turnEnd), hasLength(2));
    expect(log.lastTurnStatus, 'completed');
    expect(log.unsealedRuns, isEmpty);

    // 影子比对：日志推导的历史（去掉 system）与 Messages 表一致。
    List<String> view(Iterable<ChatMessage> messages) => [
          for (final m in messages)
            if (m.role != MessageRole.system) '${m.role.name}:${m.text}',
        ];
    final stored = await db.messagesFor(conversationId);
    expect(view(log.deriveMessages()!),
        [for (final m in stored) '${m.role}:${m.content}']);
    expect(view(log.deriveMessages()!), view(state.messages));

    // 第一问与第一次回复在第二次运行中复用，不重复写入。
    final userMessages = log.events.where((e) =>
        e.type == SessionEventType.message && e.payload['role'] == 'user');
    expect(userMessages, hasLength(2));
  });
}

class _FakeConfigStore extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
      baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', apiKey: '');

  @override
  Future<String> readToolKey(String name) async => '';
}
