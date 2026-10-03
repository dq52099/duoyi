class DailyDigestReminderResult {
  final List<DailyDigestReminderIssue> issues;

  const DailyDigestReminderResult({this.issues = const []});

  DailyDigestReminderIssue? issueForSlot(int index) {
    final relatedId = 'daily_reminder_$index';
    final slotIssue = _lastWhereOrNull(
      issues,
      (issue) => issue.relatedId == relatedId,
    );
    return slotIssue ?? generalIssue;
  }

  DailyDigestReminderIssue? get generalIssue => _lastWhereOrNull(
    issues,
    (issue) => issue.relatedId == null || issue.relatedId == 'daily_reminder',
  );
}

class DailyDigestReminderIssue {
  final String title;
  final String message;
  final DateTime? scheduledTime;
  final String? relatedId;
  final bool blocking;

  const DailyDigestReminderIssue({
    required this.title,
    required this.message,
    this.scheduledTime,
    this.relatedId,
    this.blocking = true,
  });
}

class DailyDigestReminderSync {
  final Future<DailyDigestReminderResult> Function() registerImmediately;

  const DailyDigestReminderSync({required this.registerImmediately});
}

T? _lastWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  T? result;
  for (final value in values) {
    if (test(value)) result = value;
  }
  return result;
}
