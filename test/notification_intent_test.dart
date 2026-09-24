import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/notifications/notification_intent.dart';

void main() {
  setUp(NotificationIntentRouter.reset);

  group('NotificationIntent.parse', () {
    test('parses conversation payload', () {
      expect(
        NotificationIntent.parse('conversation:conv-1'),
        const NotificationIntent(NotificationIntentKind.conversation, 'conv-1'),
      );
    });

    test('parses task payload', () {
      expect(
        NotificationIntent.parse('task:task-1'),
        const NotificationIntent(NotificationIntentKind.task, 'task-1'),
      );
    });

    test('parses approval payload', () {
      expect(
        NotificationIntent.parse('approval:req-1'),
        const NotificationIntent(NotificationIntentKind.approval, 'req-1'),
      );
    });

    test('keeps separators that appear inside the id', () {
      // 会话 id 由应用自己生成，仍按第一个冒号切分最稳妥。
      expect(
        NotificationIntent.parse('conversation:a:b'),
        const NotificationIntent(NotificationIntentKind.conversation, 'a:b'),
      );
    });

    test('returns null for null payload', () {
      expect(NotificationIntent.parse(null), isNull);
    });

    test('returns null for an unknown kind', () {
      expect(NotificationIntent.parse('unknown:1'), isNull);
    });

    test('returns null when the separator is missing', () {
      expect(NotificationIntent.parse('conversation'), isNull);
    });

    test('returns null for an empty id', () {
      expect(NotificationIntent.parse('conversation:'), isNull);
    });

    test('returns null for a leading separator', () {
      expect(NotificationIntent.parse(':conversation'), isNull);
    });
  });

  group('NotificationIntentRouter', () {
    test('buffers intents while nobody is listening', () {
      // 冷启动时通知点击发生在 ChatPage 订阅之前，广播流会丢事件。
      NotificationIntentRouter.dispatch(
        const NotificationIntent(NotificationIntentKind.task, 't1'),
      );
      NotificationIntentRouter.dispatch(
        const NotificationIntent(NotificationIntentKind.conversation, 'c1'),
      );

      expect(NotificationIntentRouter.drainPending(), [
        const NotificationIntent(NotificationIntentKind.task, 't1'),
        const NotificationIntent(NotificationIntentKind.conversation, 'c1'),
      ]);
    });

    test('draining clears the buffer', () {
      NotificationIntentRouter.dispatch(
        const NotificationIntent(NotificationIntentKind.task, 't1'),
      );

      expect(NotificationIntentRouter.drainPending(), hasLength(1));
      expect(NotificationIntentRouter.drainPending(), isEmpty);
    });

    test('delivers live to a listener instead of buffering', () async {
      // 运行中点击通知必须实时导航；若还塞进缓冲，用户得等到下次冷启动才被带走。
      final received = <NotificationIntent>[];
      final subscription = NotificationIntentRouter.intents.listen(received.add);
      addTearDown(subscription.cancel);
      // 广播流需要一次事件循环让订阅生效。
      await Future<void>.delayed(Duration.zero);

      NotificationIntentRouter.dispatch(
        const NotificationIntent(NotificationIntentKind.task, 't1'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        const NotificationIntent(NotificationIntentKind.task, 't1'),
      ]);
      expect(NotificationIntentRouter.drainPending(), isEmpty);
    });
  });
}
