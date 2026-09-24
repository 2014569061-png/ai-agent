import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_execution_stage.dart';

void main() {
  test('prefers explicit run progress and preserves waiting-for-user state',
      () {
    final now = DateTime(2026);
    final stage = resolveChatExecutionStage(
      toolActivities: const [],
      running: true,
      paused: false,
      planState: null,
      runProgress: ChatRunProgress(
        stage: ChatRunStage.waitingForUser,
        label: '等待批准',
        startedAt: now,
        lastActivityAt: now,
      ),
    );
    expect(stage?.stage, ChatExecutionStage.waitingForUser);
    expect(stage?.label, '等待批准');
  });

  test('falls back to the current tool status', () {
    final stage = resolveChatExecutionStage(
      toolActivities: const [
        ToolActivity(
          call: ToolCall(id: 'tool-1', name: 'terminal', arguments: {}),
          risk: ToolRisk.safe,
          status: '执行中',
        ),
      ],
      running: true,
      paused: false,
      planState: null,
    );
    expect(stage?.stage, ChatExecutionStage.running);
    expect(stage?.label, '正在执行：terminal');
  });
}
