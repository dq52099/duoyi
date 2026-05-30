import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('AI schedule entries share one confirmation flow', () {
    final screen = File(
      'lib/screens/ai_schedule_screen.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final quickFab = File(
      'lib/widgets/quick_capture_fab.dart',
    ).readAsStringSync();
    final aiService = File('lib/services/ai_service.dart').readAsStringSync();

    expect(screen, contains('class AiScheduleScreen'));
    expect(screen, contains('createScheduleDraft('));
    expect(screen, contains('确认创建内容'));
    expect(screen, contains('已生成确认草稿'));
    expect(screen, contains('AI 识别未完成'));
    expect(screen, contains('AI 识别结果不完整'));
    expect(screen, contains('当前不是完整 AI 识别结果'));
    expect(screen, contains('确认创建'));
    expect(
      screen,
      contains("title: Text('\${draft.isCalendar ? '日程' : '待办'}已创建')"),
    );
    expect(screen, contains('AI 未启用'));
    expect(screen, contains('请输入要创建的日程或待办内容'));
    expect(
      screen,
      contains('final calendarProvider = context.read<CalendarProvider>()'),
    );
    expect(screen, contains('await calendarProvider.addLocalEvent(event)'));
    expect(
      screen,
      contains('final todoProvider = context.read<TodoProvider>()'),
    );
    expect(screen, contains('final todo = draft.toTodo()'));
    expect(screen, contains('await todoProvider.addTodo(todo)'));
    expect(screen, contains('preflightTodoReminderPlan(todo)'));
    expect(screen, contains("import '../models/goal.dart' show ReminderKind;"));
    expect(screen, contains('AI 待办提醒注册失败'));
    expect(
      screen,
      contains('final usesPush = preflight.kinds.contains(ReminderKind.push);'),
    );
    expect(
      screen,
      contains(
        'final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);',
      ),
    );
    expect(
      screen,
      contains(
        'final usesPopup = preflight.kinds.contains(ReminderKind.popup);',
      ),
    );
    expect(screen, contains('if (usesPush || usesPopup)'));
    expect(screen, contains('final usesAlarmOnly ='));
    expect(screen, contains('usesAlarm && !usesPush && !usesPopup'));
    expect(screen, contains('LocalNotifications.instance.ensurePermission()'));
    expect(screen, contains('系统通知权限未开启，闹钟提醒未注册'));
    expect(
      screen.indexOf('preflightTodoReminderPlan(todo)'),
      lessThan(screen.indexOf('await todoProvider.addTodo(todo)')),
    );
    final todoBranchStart = screen.indexOf('final todo = draft.toTodo()');
    final todoAddIndex = screen.indexOf('await todoProvider.addTodo(todo)');
    expect(todoBranchStart, greaterThanOrEqualTo(0));
    expect(todoAddIndex, greaterThan(todoBranchStart));
    final todoBranch = screen.substring(todoBranchStart, todoAddIndex);
    expect(todoBranch, contains('if (usesPush || usesPopup)'));
    expect(todoBranch, contains('notificationService.ensureReadyForReminder'));
    expect(
      todoBranch,
      contains('LocalNotifications.instance.ensurePermission()'),
    );
    expect(screen, contains('notificationService.scheduleCalendarReminder'));
    expect(screen, isNot(contains('notificationService.scheduleOnce')));
    expect(screen, contains('notificationService.ensureReadyForReminder'));
    expect(screen, contains('if (_saving) return;'));
    expect(screen, contains('AI 日程提醒注册失败'));
    expect(
      screen.indexOf('notificationService.ensureReadyForReminder'),
      lessThan(screen.indexOf('await calendarProvider.addLocalEvent(event)')),
    );
    expect(screen, contains('NotificationPermissionDeniedException'));
    expect(screen, contains('提醒注册失败'));
    expect(screen, contains('AI 创建失败'));
    expect(screen, contains('保存失败'));

    expect(calendar, contains("import 'ai_schedule_screen.dart';"));
    expect(calendar, contains("title: const Text('AI 创建日程')"));
    expect(calendar, contains('AiScheduleScreen(initialDate: _selectedDay)'));

    expect(quickFab, contains("import '../screens/ai_schedule_screen.dart';"));
    expect(
      quickFab,
      contains('MaterialPageRoute(builder: (_) => const AiScheduleScreen())'),
    );
    expect(quickFab, isNot(contains('.breakDownTask(ctrl.text.trim())')));

    expect(aiService, contains('Future<AiScheduleDraft> createScheduleDraft'));
    expect(aiService, contains('AiScheduleSource.localParser'));
    expect(aiService, contains('AI 识别失败，已用本地时间解析生成草稿'));
    expect(aiService, contains('AI 没有返回可用草稿'));
    expect(aiService, contains('AI 上游服务不可达'));
  });

  test(
    'AI calendar reminder is scheduled through a guarded service helper',
    () {
      final screen = File(
        'lib/screens/ai_schedule_screen.dart',
      ).readAsStringSync();
      final notificationService = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();

      expect(screen, contains('scheduleCalendarReminder('));
      expect(screen, contains('calendarEventId: event.id'));
      expect(screen, isNot(contains("_notificationIdFor('ai_calendar_")));

      final helperStart = notificationService.indexOf(
        'Future<void> scheduleCalendarReminder',
      );
      final dailyStart = notificationService.indexOf(
        'Future<void> scheduleDaily',
        helperStart,
      );
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(dailyStart, greaterThan(helperStart));
      final helper = notificationService.substring(helperStart, dailyStart);

      expect(helper, contains("_idFor('ai_calendar_\$calendarEventId')"));
      expect(helper, contains('_scheduleOnceOrRecord('));
      expect(helper, contains("issueTitle: 'AI 日程提醒注册失败'"));
      expect(helper, contains('relatedId: calendarEventId'));
      expect(helper, contains('_addScheduledToHistory('));
      expect(helper, contains('notifyListeners();'));

      expect(
        notificationService,
        contains('Future<void> cancelCalendarReminder'),
      );
      expect(
        notificationService,
        contains("_idFor('ai_calendar_\$calendarEventId')"),
      );
    },
  );
}
