import 'dart:async';

/// Process-local notification emitted after the installed Skill catalog changes.
///
/// The database remains the source of truth. This bus only lets long-lived UI
/// surfaces (for example ChatPage) refresh without requiring a restart.
class SkillChangeNotifier {
  SkillChangeNotifier._();

  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  static Stream<void> get changes => _controller.stream;

  static void notify() {
    if (!_controller.isClosed) _controller.add(null);
  }
}
