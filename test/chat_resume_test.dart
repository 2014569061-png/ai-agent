import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 断点恢复（C2）与预算续跑的护栏测试。
///
/// 背景：`resumeTask` / `resumeFromBudgetPause` 是 README 对外宣传的核心能力，
/// 但在本次补测之前整个 `test/` 目录对它们 0 命中 —— 一旦有人改动 run 代次、
/// checkpoint 去重或预算续跑逻辑，回归不会有任何提示。
///
/// 这里不引入任何测试专用后门：所有用例都走真实调用链，用本地 `HttpServer`
/// 模拟 OpenAI 兼容上游（与 `sse_stream_test.dart` 同一手法），因此「恢复时到底
/// 发了什么请求、带的是原始 prompt 还是保存的上下文」都是可断言的客观事实。
void main() {
  // resumeTask 走 HeadlessExecutor 链路，其中会触达 platform channel（缓存目录
  // 等），必须先初始化 Flutter 测试绑定；否则任务会以
  // "Binding has not yet been initialized" 失败（且不发任何请求）。
  TestWidgetsFlutterBinding.ensureInitialized();
  // 绑定初始化时会装上 HttpOverrides（让所有 HTTP 请求返回 400），而本文件
  // 的假上游就是本机真实 socket —— 置空才能在保留绑定的同时打通回环网络。
  // 依据：flutter_test 的 setupHttpOverrides() 在 initInstances 中只赋值一次。
  HttpOverrides.global = null;
  // HeadlessExecutor 在构造工具注册表时会直接读 SharedPreferences
  // （headless_executor.dart:194，未包 try/catch），测试环境必须给出内存实现，
  // 否则恢复路径会以 MissingPluginException 整轮失败。
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('recoverableTasks 把 running 与 paused 任务都当作可恢复候选', () async {
    final env = await _Env.boot();
    final service = TaskService();
    final running = await service.create(
      db: env.db,
      conversationId: 'c1',
      requestJson: jsonEncode({'prompt': '运行中'}),
    );
    final paused = await service.create(
      db: env.db,
      conversationId: 'c1',
      requestJson: jsonEncode({'prompt': '预算暂停'}),
    );
    await service.updateStatus(env.db, paused.id, 'paused');
    final completed = await service.create(
      db: env.db,
      conversationId: 'c1',
      requestJson: jsonEncode({'prompt': '已完成'}),
    );
    await service.updateStatus(env.db, completed.id, 'completed');

    final tasks = await env.controller.recoverableTasks();

    // 2026-09-12 决策：paused（预算暂停）任务也必须有恢复入口，
    // 否则用户没有任何途径发现它们（resumeTask 本就接受 paused）。
    expect(tasks.map((task) => task.id), containsAll([running.id, paused.id]));
    expect(tasks.map((task) => task.id), isNot(contains(completed.id)));
  });

  test('resumeTask 对已应用过的 checkpoint 只清理、不重复写回会话', () async {
    // 上游处于「记录但绝不回应」模式：任何到达的请求都说明该路径不该发网络。
    final upstream = await _FakeUpstream.start(_UpstreamMode.never);
    final env = await _Env.boot(upstream: upstream);
    final conversation = await _seedConversation(env.db, 'c1', '历史会话');
    final service = TaskService();
    final task = await service.create(
      db: env.db,
      conversationId: conversation.id,
      requestJson: jsonEncode({'prompt': 'ORIGINAL_PROMPT', 'maxSteps': 2}),
    );
    // 终态结果已按 runId 应用过一次 → 恢复入口必须只清 checkpoint 并收敛状态。
    await service.complete(
      env.db,
      task.id,
      status: 'paused',
      summary: '预算暂停',
      runId: 'run-applied',
      checkpoint: {
        'version': 1,
        'runId': 'run-applied',
        'context': encodeChatContextForPersistence([
          ChatMessage(
              role: MessageRole.user,
              parts: [const MessagePart.text('CHECKPOINT')])
        ]),
      },
    );
    await service.markRunApplied(env.db, task.id, 'run-applied');
    final before = env.state.messages.length;

    await env.controller.resumeTask(task.id, approveTool: _allowOnce);

    final reloaded = await env.db.findTask(task.id);
    expect(reloaded!.status, 'completed');
    final progress = await service.progress(env.db, task.id);
    expect(progress.containsKey('checkpoint'), isFalse);
    expect(progress['appliedRunIds'], contains('run-applied'));
    // 零网络、零新消息：同一 runId 的终态结果不得二次投影到会话。
    expect(upstream.requests, isEmpty);
    expect(env.state.messages.length, before);
  });

  test('resumeTask 对不存在或已终态的任务是纯早退', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.never);
    final env = await _Env.boot(upstream: upstream);
    await _seedConversation(env.db, 'c1', '历史会话');
    final service = TaskService();
    final completed = await service.create(
      db: env.db,
      conversationId: 'c1',
      requestJson: jsonEncode({'prompt': '已完成任务'}),
    );
    await service.updateStatus(env.db, completed.id, 'completed');
    final before = env.state.messages.length;

    await env.controller.resumeTask('task-not-exist', approveTool: _allowOnce);
    await env.controller.resumeTask(completed.id, approveTool: _allowOnce);

    expect(upstream.requests, isEmpty);
    expect(env.state.messages.length, before);
    expect(env.state.running, isFalse);
    expect((await env.db.findTask(completed.id))!.resumeCount, 0);
    expect((await env.db.findTask(completed.id))!.status, 'completed');
  });

  test('resumeTask 用保存的 checkpoint 上下文续跑，而非重提交原始 prompt', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.text);
    final env = await _Env.boot(upstream: upstream);
    await _seedConversation(env.db, 'c1', '历史会话');
    final service = TaskService();
    final task = await service.create(
      db: env.db,
      conversationId: 'c1',
      requestJson: jsonEncode({
        'prompt': 'ORIGINAL_PROMPT_SHOULD_NOT_BE_RESUBMITTED',
        'maxSteps': 2,
      }),
    );
    await service.complete(
      env.db,
      task.id,
      status: 'paused',
      summary: '预算暂停',
      runId: 'run-paused',
      checkpoint: {
        'version': 1,
        'runId': 'run-paused',
        'context': encodeChatContextForPersistence([
          ChatMessage(
              role: MessageRole.user,
              parts: [const MessagePart.text('CHECKPOINT_MARKER')]),
          ChatMessage(
              role: MessageRole.assistant,
              parts: [const MessagePart.text('已算到中间结果')]),
        ]),
      },
    );

    await env.controller.resumeTask(task.id, approveTool: _allowOnce);

    // 任务收敛为 completed，且 resumeCount 递增（证明真的走了恢复分支）。
    final reloaded = await env.db.findTask(task.id);
    expect(reloaded!.status, 'completed');
    expect(reloaded.resumeCount, 1);
    // 上游确实被调用了一次，且带的是 checkpoint 上下文 —— 这是「断点续跑」
    // 与「重新提问」的分水岭。
    expect(upstream.requests, hasLength(1));
    final messages = upstream.lastMessages;
    expect(jsonEncode(messages), contains('CHECKPOINT_MARKER'));
    // 会话切回任务所属会话，并把助手结果写回内存状态与数据库。
    expect(env.state.conversationId, 'c1');
    expect(env.state.running, isFalse);
    expect(env.state.messages.last.text, contains('恢复后的回答'));
    final persisted = await env.db.messagesFor('c1');
    expect(persisted.map((row) => row.content).join(), contains('恢复后的回答'));
    // 假上游自身没有出错（否则上面可能是「静默失败」的假绿）。
    expect(upstream.handlerErrors, isEmpty);
  });

  test('resumeFromBudgetPause 从保存的上下文续跑（先真跑一次预算耗尽）', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.toolLoop);
    // maxSteps=1：第一轮必然耗尽预算并进入可恢复的 paused 状态。
    final env = await _Env.boot(upstream: upstream, maxSteps: 1);

    await env.controller
        .send(text: '开始', attachments: const [], approveTool: _allowOnce);

    expect(env.state.paused, isTrue);
    expect(env.state.running, isFalse);
    expect(upstream.requests, hasLength(1));
    // 第一轮请求只有原始 prompt，没有任何工具上下文。
    expect(env.controller.budgetPauseContext, isNotNull);
    expect(env.controller.budgetPauseContext, isNotEmpty);
    expect(jsonEncode(upstream.lastMessages), isNot(contains('"role":"tool"')));

    await env.controller.resumeFromBudgetPause(approveTool: _allowOnce);

    // 续跑发了第二个请求，且这次带着第一轮累积的工具上下文。
    expect(upstream.requests, hasLength(2));
    expect(jsonEncode(upstream.lastMessages), contains('"role":"tool"'));
    expect(env.state.running, isFalse);
    expect(upstream.handlerErrors, isEmpty);
  });

  test('resumeFromBudgetPause 在没有暂停上下文时不产生任何副作用', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.text);
    final env = await _Env.boot(upstream: upstream);
    final before = env.state.messages.length;

    await env.controller.resumeFromBudgetPause(approveTool: _allowOnce);

    expect(upstream.requests, isEmpty);
    expect(env.state.messages.length, before);
    expect(env.state.running, isFalse);
  });

  test('成功跑完一轮会清空续跑上下文，避免用陈旧快照续跑', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.text);
    final env = await _Env.boot(upstream: upstream);

    await env.controller
        .send(text: '你好', attachments: const [], approveTool: _allowOnce);
    expect(upstream.requests, hasLength(1));
    expect(env.controller.budgetPauseContext, isNull);
    final before = env.state.messages.length;

    await env.controller.resumeFromBudgetPause(approveTool: _allowOnce);

    expect(upstream.requests, hasLength(1));
    expect(env.state.messages.length, before);
  });

  test('运行中切换会话不会让旧 run 的结果污染新会话', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.slow);
    final env = await _Env.boot(upstream: upstream);
    await _seedConversation(env.db, 'c1', '会话一');
    final now = DateTime.now();
    await env.db.saveConversation(Conversation(
      id: 'c2',
      title: '会话二',
      agentId: null,
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await env.db.insertMessage(MessagesCompanion.insert(
        id: 'c2-m1',
        conversationId: 'c2',
        role: 'user',
        content: '会话二的内容',
        createdAt: now));

    await env.controller
        .switchConversation((await env.db.findConversation('c1'))!);
    final pending = env.controller
        .send(text: '在会话一里提问', attachments: const [], approveTool: _allowOnce);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(env.state.running, isTrue);

    // 运行中切走：switchConversation 会 invalidate 当前 run（runGeneration++）。
    await env.controller
        .switchConversation((await env.db.findConversation('c2'))!);
    await pending;

    final state = env.state;
    expect(state.conversationId, 'c2');
    expect(state.running, isFalse);
    // 新会话的内存状态与数据库都必须保持原样，不被旧 run 的尾部写入。
    expect(state.messages.map((message) => message.text), ['会话二的内容']);
    final c2Rows = await env.db.messagesFor('c2');
    expect(c2Rows.map((row) => row.content), ['会话二的内容']);
    // 旧会话也不应凭空多出助手回复（该轮已被判定为失效代次）。
    final c1Rows = await env.db.messagesFor('c1');
    expect(c1Rows.where((row) => row.role == 'assistant'), isEmpty);
  });

  test('resumeFromBudgetPause 在运行中不会插队', () async {
    final upstream = await _FakeUpstream.start(_UpstreamMode.toolLoop);
    final env = await _Env.boot(upstream: upstream, maxSteps: 1);
    await env.controller
        .send(text: '开始', attachments: const [], approveTool: _allowOnce);
    expect(env.controller.budgetPauseContext, isNotNull);

    // 让暂停上下文仍在（新一轮已开始但尚未结束），此时恢复必须被 running 拦住。
    upstream.mode = _UpstreamMode.slow;
    final pending = _pendingSend(env);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(env.state.running, isTrue);
    final requestsDuringRun = upstream.requests.length;

    await env.controller.resumeFromBudgetPause(approveTool: _allowOnce);

    expect(upstream.requests.length, requestsDuringRun);
    await pending;
  });
}

Future<void> _pendingSend(_Env env) => env.controller
    .send(text: '第二轮', attachments: const [], approveTool: _allowOnce);

Future<ToolApproval> _allowOnce(ToolCall call, ToolRisk risk) async =>
    ToolApproval.allowOnce;

Future<Conversation> _seedConversation(
    AppDatabase db, String id, String title) async {
  final now = DateTime.now();
  final conversation = Conversation(
    id: id,
    title: title,
    agentId: null,
    isPinned: false,
    isFavorite: false,
    tagsJson: '[]',
    createdAt: now,
    updatedAt: now,
  );
  await db.saveConversation(conversation);
  return conversation;
}

/// 上游回应模式。
enum _UpstreamMode {
  /// 直接回一段文本，一轮即完成。
  text,

  /// 每轮都要求调用 calculator，配合 maxSteps 小值触发预算耗尽。
  toolLoop,

  /// 慢速回应，用于制造「运行中」窗口。
  slow,

  /// 不应被调用的路径：只记录请求，便于断言「零网络」。
  never,
}

/// 本地假上游：记录每次请求体，并按模式返回 OpenAI 兼容 SSE。
class _FakeUpstream {
  _FakeUpstream._(this._server, this.mode);

  final HttpServer _server;
  _UpstreamMode mode;

  /// 收到的请求体（按到达顺序）。
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];

  /// 假上游自身抛出的异常（客户端取消除外），happy-path 用例应断言为空。
  final List<Object> handlerErrors = <Object>[];

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  /// 最近一次请求的 messages 数组，用于断言「发了什么上下文」。
  List<dynamic> get lastMessages {
    final last = requests.last;
    final messages = last['messages'];
    return messages is List ? messages : const [];
  }

  static Future<_FakeUpstream> start(_UpstreamMode mode) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstream = _FakeUpstream._(server, mode);
    server.listen(upstream._handle, onError: (_) {});
    return upstream;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      requests.add(_decode(body));
      request.response.bufferOutput = false;
      // 必须显式声明 charset：text/* 默认 latin-1，写中文会直接抛
      // 「Contains invalid characters」并把流挂在半路。
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      switch (mode) {
        case _UpstreamMode.text:
          await _writeText(request);
        case _UpstreamMode.toolLoop:
          await _writeToolCall(request);
        case _UpstreamMode.slow:
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await _writeText(request);
        case _UpstreamMode.never:
          break;
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.flush();
      await request.response.close();
    } catch (error) {
      // 客户端取消（stop / 代次失效）会中断连接，属预期；其余异常会被
      // 记下来，由 happy-path 用例断言为空 —— 否则假上游出错会被静默吞掉，
      // 表现为「测试莫名超时」。
      handlerErrors.add(error);
    }
  }

  Future<void> _writeText(HttpRequest request) async {
    _chunk(request, _delta({'content': '恢复后的回答'}));
    await request.response.flush();
    _chunk(request, _delta(const {}, finishReason: 'stop'));
    await request.response.flush();
  }

  Future<void> _writeToolCall(HttpRequest request) async {
    _chunk(request, _delta({'content': '处理中'}));
    await request.response.flush();
    _chunk(
        request,
        _delta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call-${requests.length}',
              'type': 'function',
              'function': {
                'name': 'calculator',
                'arguments': '{"a":1,"b":2}',
              },
            }
          ]
        }));
    await request.response.flush();
    _chunk(request, _delta(const {}, finishReason: 'tool_calls'));
    await request.response.flush();
  }

  static void _chunk(HttpRequest request, Map<String, dynamic> payload) {
    request.response.write('data: ${jsonEncode(payload)}\n\n');
  }

  static Map<String, dynamic> _delta(Map<String, dynamic> delta,
          {String? finishReason}) =>
      {
        'choices': [
          {
            'delta': delta,
            if (finishReason != null) 'finish_reason': finishReason,
          }
        ],
      };

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

/// 让 ProviderConfigStore 指向本地假上游。
class _UpstreamConfigStore extends ProviderConfigStore {
  _UpstreamConfigStore(this.baseUrl);

  final String baseUrl;

  @override
  Future<ProviderConfig> load() async => ProviderConfig(
        // baseUrl 为空表示不需要真实上游；apiKey 为空会让控制器回落到
        // DemoProvider，从而保证不产生任何网络请求。
        baseUrl: baseUrl.isEmpty ? 'http://127.0.0.1:1/v1' : baseUrl,
        model: 'test-model',
        apiKey: baseUrl.isEmpty ? '' : 'test-key',
      );

  @override
  Future<String> readToolKey(String name) async => '';
}

/// 一次用例的运行环境：内存库 + 已初始化完成的 ChatController。
class _Env {
  _Env._(this.db, this.container, this.controller);

  final AppDatabase db;
  final ProviderContainer container;
  final ChatController controller;

  ChatState get state => container.read(chatControllerProvider);

  static Future<_Env> boot({
    _FakeUpstream? upstream,
    int? maxSteps,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      providerConfigStoreProvider
          .overrideWith((ref) => _UpstreamConfigStore(upstream?.baseUrl ?? '')),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
      await upstream?.close();
    });
    final controller = container.read(chatControllerProvider.notifier);
    await pumpEventQueue();
    if (maxSteps != null) {
      // 交互式预算由 Agent.maxSteps 决定（_prepareRun 从 state.agentId 读取），
      // 因此要真跑「预算耗尽」必须显式选一个 maxSteps 很小的 Agent。
      final agent = Agent(
        id: 'agent-budget',
        name: '预算测试 Agent',
        systemPrompt: '你是测试 Agent。',
        modelProfileId: 'default',
        enabledToolsJson: '["calculator"]',
        temperature: 0.0,
        maxTokens: 512,
        maxSteps: maxSteps,
        topP: 1.0,
        updatedAt: DateTime.now(),
      );
      await db.saveAgent(agent);
      await controller.selectAgent(agent);
    }
    return _Env._(db, container, controller);
  }
}
