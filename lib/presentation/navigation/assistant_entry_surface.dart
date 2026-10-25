import 'package:flutter/material.dart';

bool canConsumeAssistantEntry(
        {required bool visible,
        required bool currentRoute,
        required bool busy}) =>
    visible && currentRoute && !busy;

/// The notifier changes synchronously on tab selection. Even before the next
/// frame, a late ASR result cannot auto-send from an offstage cached navigator.
class AssistantEntrySurface extends InheritedNotifier<ValueNotifier<bool>> {
  const AssistantEntrySurface(
      {super.key,
      required ValueNotifier<bool> visibility,
      required super.child,
      this.parentRoute})
      : super(notifier: visibility);
  final ModalRoute<dynamic>? parentRoute;
  static bool canConsume(BuildContext context, {bool busy = false}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final scope =
        context.dependOnInheritedWidgetOfExactType<AssistantEntrySurface>();
    return canConsumeAssistantEntry(
        visible:
            (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
                (scope?.notifier?.value ?? true) &&
                (scope?.parentRoute?.isCurrent ?? true),
        currentRoute: ModalRoute.of(context)?.isCurrent ?? true,
        busy: busy);
  }
}
