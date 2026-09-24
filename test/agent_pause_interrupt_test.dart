import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/run_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/presentation/chat/widgets/floating_capsule_input.dart';
import 'package:mobile_agent/presentation/motion/motion_preferences.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

/// 暂停相关回归：暂停必须真的停下（模型输出立即中断、工具在当前命令后停下），
/// 并且停下时一定发出 paused 事件，UI 才能露出继续/停止按钮。
List<ChatMessage> _history(String text) => [
      ChatMessage(role: MessageRole.user, parts: [MessagePart.text(text)]),
    ];

void main() {
  test('pause cuts the streaming turn and resume continues from the cut',
      () async {
    final runController = AgentRunController();
    final provider = _SlowStreamingProvider();
    final text = StringBuffer();
    var pausedEvents = 0;

    await for (final event in AgentExecutor(
      provider: provider,
      tools: ToolRegistry(),
    ).run(
      history: _history('写一段话'),
      model: 'test',
      runController: runController,
    )) {
      if (event is TextEvent) {
        text.write(event.text);
        if (text.toString() == '第一段') {
          expect(runController.pause(), isTrue);
        }
      }
      if (event is AgentStatusEvent && event.status == RunStatus.paused) {
        pausedEvents++;
        expect(runController.resume(), isTrue);
      }
    }

    expect(pausedEvents, 1);
    // 暂停后的后半段不会再流出来；恢复后接着输出第二段。
    expect(text.toString(), '第一段第二段');
    expect(provider.requests, hasLength(2));
    final resumed = provider.requests.last.messages;
    final partialIndex = resumed.indexWhere((message) =>
        message.role == MessageRole.assistant && message.text == '第一段');
    expect(partialIndex, isNonNegative);
    expect(
      resumed.skip(partialIndex + 1).any((message) =>
          message.role == MessageRole.user && message.text.contains('暂停')),
      isTrue,
    );
  });

  test('stop still cancels the in-flight per-step request token', () async {
    final runToken = CancelToken();
    final runController = AgentRunController(onCancel: runToken.cancel);
    final provider = _SlowStreamingProvider();
    var sawCancelled = false;

    await for (final event in AgentExecutor(
      provider: provider,
      tools: ToolRegistry(),
    ).run(
      history: _history('写一段话'),
      model: 'test',
      runController: runController,
      cancelToken: runToken,
    )) {
      if (event is TextEvent) runController.cancel();
      if (event is AgentStatusEvent && event.status == RunStatus.cancelled) {
        sawCancelled = true;
      }
    }
    await Future<void>.delayed(Duration.zero);

    expect(sawCancelled, isTrue);
    expect(provider.requests, hasLength(1));
    expect(provider.tokens.single, isNot(same(runToken)));
    expect(provider.tokens.single!.isCancelled, isTrue);
  });

  test('pause during a tool call stops before the next tool and emits paused',
      () async {
    final runController = AgentRunController();
    final tool = _PausingTool(runController);
    final statuses = <RunStatus>[];

    await for (final event in AgentExecutor(
      provider: _TwoToolCallsProvider(),
      tools: ToolRegistry()..register(tool),
    ).run(
      history: _history('执行两个工具'),
      model: 'test',
      runController: runController,
    )) {
      if (event is AgentStatusEvent) {
        statuses.add(event.status);
        if (event.status == RunStatus.paused) {
          // 第一个工具（当前命令）跑完才停，第二个还没开始。
          expect(tool.executions, 1);
          expect(runController.resume(), isTrue);
        }
      }
    }

    expect(
        statuses.where((status) => status == RunStatus.paused), hasLength(1));
    expect(tool.executions, 2);
  });

  testWidgets('paused composer shows stop and resume side by side at 320dp',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var stopped = false;
    var resumed = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(2),
          disableAnimations: true,
        ),
        child: NexusMotionScope(
          level: MotionLevel.off,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingCapsuleInput(
                controller: controller,
                isRunning: true,
                isPaused: true,
                onSend: () {},
                onStop: () => stopped = true,
                onResume: () => resumed = true,
                onAttachmentMenu: () {},
                onModeTap: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    final stop = find.byKey(const ValueKey('trailing_action_stop_when_paused'));
    final resume = find.byKey(const ValueKey('trailing_action_resume'));
    expect(stop, findsOneWidget);
    expect(resume, findsOneWidget);
    await tester.tap(stop);
    expect(stopped, isTrue);
    await tester.tap(resume);
    expect(resumed, isTrue);
  });
}

/// 模拟真实 provider：分片流式输出，收到取消后静默结束（不产出错误事件）。
class _SlowStreamingProvider implements LlmProvider {
  final requests = <UnifiedRequest>[];
  final tokens = <CancelToken?>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    tokens.add(cancelToken);
    if (requests.length == 1) {
      for (final chunk in const ['第一', '段', '不该出现的后半段']) {
        if (cancelToken?.isCancelled ?? false) return;
        yield TextDeltaEvent(chunk);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      yield const CompletedEvent(stopReason: StopReason.endOfTurn);
      return;
    }
    yield const TextDeltaEvent('第二段');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

class _TwoToolCallsProvider implements LlmProvider {
  var _requests = 0;

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    if (_requests++ == 0) {
      yield const ToolCallEvent(
          ToolCall(id: 'p1', name: 'pausing', arguments: {}));
      yield const ToolCallEvent(
          ToolCall(id: 'p2', name: 'pausing', arguments: {}));
      yield const CompletedEvent(stopReason: StopReason.toolUse);
      return;
    }
    yield const TextDeltaEvent('done');
    yield const CompletedEvent(stopReason: StopReason.endOfTurn);
  }
}

/// 第一次执行时模拟「用户在工具运行期间点了暂停」。
class _PausingTool implements AgentTool {
  _PausingTool(this.controller);

  final AgentRunController controller;
  int executions = 0;

  @override
  final manifest = const UnifiedTool(
    name: 'pausing',
    description: 'pauses the run on first execution',
    parametersSchema: {'type': 'object'},
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    executions++;
    if (executions == 1) controller.pause();
    return ToolResult.text('ok');
  }
}
