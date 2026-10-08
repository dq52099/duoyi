import 'widget_action_scope.dart';

/// The receiver must check [isCurrent] again when deferred feedback is shown.
typedef WidgetActionFeedback<T> =
    void Function(T message, bool Function() isCurrent);

/// Keeps a typed widget draft tied to its account throughout permission waits.
/// The caller binds its original provider before invoking this operation.
Future<void> runWidgetQuickTodoAction<T>({
  required bool Function() isCallerAvailable,
  required Future<bool> Function(void Function(T) feedback) preflight,
  required Future<T> Function() create,
  required WidgetActionFeedback<T> feedback,
  required T failureMessage,
  void Function(Object error, StackTrace stack)? logError,
}) async {
  final scope = WidgetActionScope(isCallerAvailable: isCallerAvailable);
  bool isCurrent() => scope.isCurrent;
  void guardedFeedback(T message) {
    if (isCurrent()) feedback(message, isCurrent);
  }

  try {
    if (!isCurrent()) return;
    final ready = await preflight(guardedFeedback);
    if (!ready || !isCurrent()) return;
    final message = await create();
    guardedFeedback(message);
  } catch (error, stack) {
    logError?.call(error, stack);
    guardedFeedback(failureMessage);
  }
}
