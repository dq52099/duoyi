import 'account_local_data_cleaner.dart';

/// The receiver must check [isCurrent] again when deferred feedback is shown.
typedef WidgetActionFeedback =
    void Function(String message, bool Function() isCurrent);

/// Keeps a typed widget draft tied to its account throughout permission waits.
/// The caller binds its original provider before invoking this operation.
Future<void> runWidgetQuickTodoAction({
  required bool Function() isCallerAvailable,
  required Future<bool> Function(void Function(String) feedback) preflight,
  required Future<String> Function() create,
  required WidgetActionFeedback feedback,
  required String failureMessage,
  void Function(Object error, StackTrace stack)? logError,
}) async {
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  bool isCurrent() =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
      isCallerAvailable();
  void guardedFeedback(String message) {
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
