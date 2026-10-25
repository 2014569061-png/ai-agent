import '../../domain/assistant_page_context.dart';
import '../notifications/notification_intent.dart';

enum AssistantEntryKind { share, notification, pageContext }

class AssistantEntry {
  AssistantEntry.share(this.id, List<String> items)
      : kind = AssistantEntryKind.share,
        shared = List.unmodifiable(items),
        notification = null,
        pageContext = null;
  AssistantEntry.notification(this.id, NotificationIntent intent)
      : kind = AssistantEntryKind.notification,
        notification = intent,
        shared = const [],
        pageContext = null;
  AssistantEntry.pageContext(AssistantPageContext context)
      : id = 'context:${context.id}',
        kind = AssistantEntryKind.pageContext,
        pageContext = context,
        shared = const [],
        notification = null;
  final String id;
  final AssistantEntryKind kind;
  final List<String> shared;
  final NotificationIntent? notification;
  final AssistantPageContext? pageContext;
  int get size =>
      shared.fold<int>(0, (sum, value) => sum + value.length) +
      (pageContext?.text.length ?? 0);
}
