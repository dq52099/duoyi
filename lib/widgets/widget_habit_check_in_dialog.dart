import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../models/habit.dart';
import 'surface_components.dart';

/// Presentation dialog for confirming habit check-ins initiated from home widgets.
class WidgetHabitCheckInDialog extends StatelessWidget {
  const WidgetHabitCheckInDialog({
    super.key,
    required this.habit,
    required this.canSubmit,
  });

  final Habit habit;
  final bool Function() canSubmit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final english = locale == AppLocale.en;
        return AppDialog(
          icon: const Icon(Icons.check_circle_outline),
          title: Text(
            english ? 'Check in: ${habit.name}' : '打卡：${habit.name}',
          ),
          content: Text(
            habit.targetCount > 1
                ? (english
                      ? '${habit.todayCount()} / ${habit.targetCount} check-ins today. Check in again?'
                      : '今天已打卡 ${habit.todayCount()} / ${habit.targetCount} 次，继续打卡吗？')
                : (english
                      ? 'Check in for “${habit.name}” now?'
                      : '现在完成“${habit.name}”打卡吗？'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (canSubmit()) Navigator.of(context).pop(false);
              },
              child: Text(english ? 'Cancel' : '取消'),
            ),
            FilledButton(
              onPressed: () {
                if (canSubmit()) Navigator.of(context).pop(true);
              },
              child: Text(english ? 'Check in' : '完成打卡'),
            ),
          ],
        );
      },
    );
  }
}
