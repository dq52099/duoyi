import 'widget_action_scope.dart';

/// The receiver must check [isCurrent] again when deferred feedback is shown.
typedef WidgetActionFeedback<T> =
    void Function(T message, bool Function() isCurrent);

enum WidgetQuickTodoResult { unavailable, denied, saved, failed }

/// Keeps a typed widget draft tied to its account throughout permission waits.
/// The caller binds its original provider before invoking this operation.
Future<WidgetQuickTodoResult> runWidgetQuickTodoAction<T>({
  required bool Function() isCallerAvailable,
  required Future<bool> Function(void Function(T) feedback) preflight,
  required Future<T> Function() create,
  required WidgetActionFeedback<T> feedback,
  required T failureMessage,
  bool Function()? isFeedbackAvailable,
  void Function(Object error, StackTrace stack)? logError,
}) async {
  final scope = WidgetActionScope();
  bool isCurrent() => scope.isCurrent && isCallerAvailable();
  bool isFeedbackCurrent() =>
      scope.isCurrent && (isFeedbackAvailable ?? isCallerAvailable)();
  void guardedFeedback(T message) {
    if (isFeedbackCurrent()) feedback(message, isFeedbackCurrent);
  }

  try {
    if (!isCurrent()) return WidgetQuickTodoResult.unavailable;
    final ready = await preflight(guardedFeedback);
    final currentAfterPreflight = isCurrent();
    if (!currentAfterPreflight) return WidgetQuickTodoResult.unavailable;
    if (!ready) return WidgetQuickTodoResult.denied;
    final message = await create();
    guardedFeedback(message);
    return WidgetQuickTodoResult.saved;
  } catch (error, stack) {
    logError?.call(error, stack);
    guardedFeedback(failureMessage);
    return WidgetQuickTodoResult.failed;
  }
}
