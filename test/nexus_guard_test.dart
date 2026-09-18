import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/nexus_guard.dart';

void main() {
  setUp(NexusGuard.resetReportedKeys);

  group('NexusGuard.silently', () {
    test('正常返回值原样透出', () {
      expect(NexusGuard.silently<int>('prefetch', () => 42), 42);
    });

    test('失败时吞掉异常并返回 null（保留原控制流）', () {
      expect(
        NexusGuard.silently<int>('prefetch', () => throw StateError('boom')),
        isNull,
      );
    });

    test('异步失败同样被吞掉', () async {
      final result = await NexusGuard.silentlyAsync<int>(
        'prefetch',
        () async => throw StateError('boom'),
      );
      expect(result, isNull);
    });

    test('异步成功返回值透出', () async {
      final result =
          await NexusGuard.silentlyAsync<int>('prefetch', () async => 7);
      expect(result, 7);
    });
  });

  group('NexusGuard.degrade', () {
    test('失败时写一条 warning 并记录安全字段', () {
      final events = <Map<String, dynamic>?>[];
      final result = NexusGuard.degrade<int>(
        'project-context',
        () => throw const FormatException('敏感内容不应出现'),
        logger: (message, {detail}) => events.add(detail),
        runId: 'run-1',
      );

      expect(result, isNull);
      expect(events, hasLength(1));
      final detail = events.single!;
      expect(detail['phase'], 'project-context');
      expect(detail['errorType'], 'FormatException');
      expect(detail['runId'], 'run-1');
      // 安全约束：不得把异常正文写进 detail。
      expect(detail.toString(), isNot(contains('敏感内容')));
    });

    test('同一 phase + errorType 只记录一次，避免噪声淹没日志', () {
      final events = <Map<String, dynamic>?>[];
      for (var i = 0; i < 3; i++) {
        NexusGuard.degrade<void>(
          'project-context',
          () => throw StateError('x'),
          logger: (message, {detail}) => events.add(detail),
        );
      }
      expect(events, hasLength(1));
    });

    test('不同 phase 各自记录', () {
      final events = <Map<String, dynamic>?>[];
      NexusGuard.degrade<void>(
        'phase-a',
        () => throw StateError('x'),
        logger: (message, {detail}) => events.add(detail),
      );
      NexusGuard.degrade<void>(
        'phase-b',
        () => throw StateError('x'),
        logger: (message, {detail}) => events.add(detail),
      );
      expect(events, hasLength(2));
    });

    test('成功时不写日志', () {
      final events = <Map<String, dynamic>?>[];
      final result = NexusGuard.degrade<int>(
        'project-context',
        () => 5,
        logger: (message, {detail}) => events.add(detail),
      );
      expect(result, 5);
      expect(events, isEmpty);
    });

    test('调用方自带的 detail 会合并进安全字段', () {
      Map<String, dynamic>? captured;
      NexusGuard.degrade<void>(
        'phase',
        () => throw StateError('x'),
        logger: (message, {detail}) => captured = detail,
        detail: {'attempt': 2},
      );
      expect(captured!['attempt'], 2);
      expect(captured!['phase'], 'phase');
    });
  });

  group('NexusGuard.report', () {
    test('影响用户的失败会记录并重新抛出', () {
      Map<String, dynamic>? captured;
      Object? capturedError;
      expect(
        () => NexusGuard.report<void>(
          'vault-export',
          () => throw ArgumentError('bad'),
          logger: (message,
              {error, stackTrace, runId, detail}) {
            capturedError = error;
            captured = detail;
          },
        ),
        throwsArgumentError,
      );
      expect(capturedError, isA<ArgumentError>());
      expect(captured!['phase'], 'vault-export');
      expect(captured!['errorType'], 'ArgumentError');
    });

    test('成功时不记录也不抛出', () {
      var logged = false;
      final result = NexusGuard.report<int>(
        'vault-export',
        () => 3,
        logger: (message, {error, stackTrace, runId, detail}) => logged = true,
      );
      expect(result, 3);
      expect(logged, isFalse);
    });
  });
}
