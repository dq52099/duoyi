/// Counts must come from the same captured set of today's active habits.
int widgetHabitCompletionPercent({
  required int activeCount,
  required int completedCount,
}) {
  assert(
    activeCount >= 0 && completedCount >= 0 && completedCount <= activeCount,
  );
  if (activeCount == 0) return 0;
  if (completedCount == activeCount) return 100;
  // Rounded progress must not claim completion while any habit is unfinished.
  return (completedCount / activeCount * 100).round().clamp(0, 99).toInt();
}

/// Normalized completion ratio in `[0.0, 1.0]` for widget progress meters.
double widgetHabitCompletionRatio({
  required int activeCount,
  required int completedCount,
}) {
  assert(
    activeCount >= 0 && completedCount >= 0 && completedCount <= activeCount,
  );
  if (activeCount == 0) return 0.0;
  return (completedCount / activeCount).clamp(0.0, 1.0).toDouble();
}

/// Compact `done/total` ratio label for widget summaries.
String widgetHabitSummaryRatioText({
  required int activeCount,
  required int completedCount,
}) {
  assert(
    activeCount >= 0 && completedCount >= 0 && completedCount <= activeCount,
  );
  return '$completedCount/$activeCount';
}
