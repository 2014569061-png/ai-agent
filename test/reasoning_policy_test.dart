import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/reasoning_policy.dart';
import 'package:mobile_agent/domain/models.dart';

void main() {
  test('automatic reasoning stays light for ordinary chat', () {
    expect(
      ReasoningPolicy.resolve(
        taskType: 'general',
        configured: ReasoningEffort.auto,
      ),
      ReasoningEffort.low,
    );
  });

  test('automatic reasoning raises the level for development tasks', () {
    expect(
      ReasoningPolicy.resolve(
        taskType: 'bug_fix',
        configured: ReasoningEffort.auto,
      ),
      ReasoningEffort.medium,
    );
    expect(
      ReasoningPolicy.resolve(
        taskType: 'general',
        configured: ReasoningEffort.auto,
        planMode: true,
      ),
      ReasoningEffort.high,
    );
  });

  test('explicit reasoning choices are not overridden', () {
    expect(
      ReasoningPolicy.resolve(
        taskType: 'bug_fix',
        configured: ReasoningEffort.off,
        planMode: true,
      ),
      ReasoningEffort.off,
    );
  });
}
