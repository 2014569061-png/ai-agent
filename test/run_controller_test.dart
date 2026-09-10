import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/run_controller.dart';

void main() {
  test('pause blocks at the next checkpoint and resume releases it', () async {
    final controller = AgentRunController();
    expect(controller.pause(), isTrue);

    var reached = false;
    final checkpoint = controller.checkpoint().then((_) => reached = true);
    await Future<void>.delayed(Duration.zero);
    expect(reached, isFalse);

    expect(controller.resume(), isTrue);
    await checkpoint;
    expect(reached, isTrue);
    expect(controller.resume(), isFalse);
  });

  test('cancel wakes a paused checkpoint and clears steering', () async {
    var callbackCount = 0;
    final controller = AgentRunController(onCancel: () => callbackCount++);
    expect(controller.steer('continue'), isTrue);
    expect(controller.pendingSteering, ['continue']);
    expect(controller.pause(), isTrue);

    final checkpoint = controller.checkpoint();
    expect(controller.cancel(), isTrue);
    await checkpoint;

    expect(callbackCount, 1);
    expect(controller.isCancelled, isTrue);
    expect(controller.pendingSteering, isEmpty);
    expect(controller.steer('too late'), isFalse);
    expect(controller.cancel(), isFalse);
  });

  test('pollSteeringOrSeal atomically consumes or seals the run', () {
    final withSteering = AgentRunController()..steer('first');
    expect(withSteering.pollSteeringOrSeal(), ['first']);
    expect(withSteering.isSealed, isFalse);
    expect(withSteering.pollSteeringOrSeal(), isEmpty);
    expect(withSteering.isSealed, isTrue);
    expect(withSteering.steer('late'), isFalse);

    final empty = AgentRunController();
    expect(empty.pollSteeringOrSeal(), isEmpty);
    expect(empty.isSealed, isTrue);
  });
}
