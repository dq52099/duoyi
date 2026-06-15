import '../core/i18n.dart';

class NotificationStatusBarPlan {
  final bool shouldShow;
  final String title;
  final String body;
  final bool enableQuickActions;

  const NotificationStatusBarPlan.show({
    required this.title,
    required this.body,
    required this.enableQuickActions,
  }) : shouldShow = true;

  const NotificationStatusBarPlan.cancel()
    : shouldShow = false,
      title = '',
      body = '',
      enableQuickActions = false;
}

NotificationStatusBarPlan buildNotificationStatusBarPlan({
  required bool notificationQuickAdd,
  required bool notificationTodayProgress,
  required String todayProgressBody,
}) {
  if (!notificationQuickAdd && !notificationTodayProgress) {
    return const NotificationStatusBarPlan.cancel();
  }
  if (notificationTodayProgress) {
    return NotificationStatusBarPlan.show(
      title: I18n.tr('notification.status_bar.today_progress_title'),
      body: notificationQuickAdd
          ? '$todayProgressBody\n${I18n.tr('notification.status_bar.quick_hint')}'
          : todayProgressBody,
      enableQuickActions: notificationQuickAdd,
    );
  }
  return NotificationStatusBarPlan.show(
    title: I18n.tr('notification.quick_add.title'),
    body: I18n.tr('notification.quick_add.body'),
    enableQuickActions: true,
  );
}

String formatNotificationTodayProgressBody({
  required int remaining,
  required int dailyCount,
  required int todoCount,
  required int goalCount,
}) {
  return '${I18n.tr('notification.status_bar.today_remaining.prefix')}'
      '$remaining'
      '${I18n.tr('notification.status_bar.today_remaining.suffix')}\n'
      '${I18n.tr('notification.status_bar.daily_count')}$dailyCount / '
      '${I18n.tr('notification.status_bar.todo_count')}'
      '$todoCount\n'
      '${I18n.tr('notification.status_bar.goal_count')}$goalCount';
}
