import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/background/foreground_run_lease.dart';

void main() {
  test(
      'concurrent successful runs release the service only after the last stop',
      () async {
    var running = false;
    var stops = 0;
    final lease = ForegroundRunLease(startPlatform: (_, __) async {
      running = true;
      return true;
    }, stopPlatform: () async {
      if (running) stops++;
      running = false;
    });
    expect(
        await Future.wait([
          lease.start(title: 'A', text: ''),
          lease.start(title: 'B', text: ''),
        ]),
        [true, true]);
    expect(lease.activeRuns, 2);
    await lease.stop();
    expect(running, isTrue);
    await lease.stop();
    expect(running, isFalse);
    expect(stops, 1);
  });

  for (final throwError in [false, true]) {
    test('failed startup releases ownership (throws=$throwError)', () async {
      final lease = ForegroundRunLease(
          startPlatform: (_, __) async {
            if (throwError) throw StateError('platform denied');
            return false;
          },
          stopPlatform: () async {});
      expect(await lease.start(title: 'A', text: ''), isFalse);
      await lease.settled;
      expect(lease.activeRuns, 0);
    });
  }

  test('timeout releases the owner and compensates a late successful startup',
      () async {
    final pending = Completer<bool>();
    var running = false;
    var stops = 0;
    final lease = ForegroundRunLease(
        startupTimeout: const Duration(milliseconds: 20),
        startPlatform: (_, __) async {
          final result = await pending.future;
          running = result;
          return result;
        },
        stopPlatform: () async {
          if (running) stops++;
          running = false;
        });
    expect(await lease.start(title: 'A', text: ''), isFalse);
    expect(lease.activeRuns, 0);
    pending.complete(true);
    await lease.settled;
    expect(running, isFalse);
    expect(stops, 1);
  });

  test('late startup failure does not escape or poison subsequent starts',
      () async {
    final pending = Completer<bool>();
    var first = true;
    final lease = ForegroundRunLease(
        startupTimeout: const Duration(milliseconds: 20),
        startPlatform: (_, __) async {
          if (first) {
            first = false;
            return pending.future;
          }
          return true;
        },
        stopPlatform: () async {});
    expect(await lease.start(title: 'A', text: ''), isFalse);
    pending.completeError(StateError('late failure'));
    await lease.settled;
    expect(await lease.start(title: 'B', text: ''), isTrue);
    await lease.stop();
    expect(lease.activeRuns, 0);
  });

  test('late cleanup never stops a newer owner', () async {
    final pending = Completer<bool>();
    var running = false;
    final lease = ForegroundRunLease(
        startupTimeout: const Duration(milliseconds: 30),
        startPlatform: (_, __) async {
          await pending.future;
          running = true;
          return true;
        },
        stopPlatform: () async {
          running = false;
        });
    expect(await lease.start(title: 'A', text: ''), isFalse);
    final next = lease.start(title: 'B', text: '');
    pending.complete(true);
    expect(await next, isTrue);
    await lease.settled;
    expect(lease.activeRuns, 1);
    expect(running, isTrue);
    await lease.stop();
    expect(running, isFalse);
  });

  test('an expired queued request never starts the platform service', () async {
    final pending = Completer<bool>();
    var starts = 0;
    final lease = ForegroundRunLease(
        startupTimeout: const Duration(milliseconds: 20),
        startPlatform: (_, __) {
          starts++;
          return pending.future;
        },
        stopPlatform: () async {});
    final results = await Future.wait([
      lease.start(title: 'A', text: ''),
      lease.start(title: 'B', text: ''),
    ]);
    expect(results, [false, false]);
    pending.complete(true);
    await lease.settled;
    expect(starts, 1);
    expect(lease.activeRuns, 0);
  });
}
