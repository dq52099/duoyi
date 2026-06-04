import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('CalendarScreen filters todos by project', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final todoProvider = TodoProvider();
    final today = DateTime.now();
    await todoProvider.addTodo(
      TodoItem(title: '准备周会', date: today, listGroupName: '工作'),
    );
    await todoProvider.addTodo(
      TodoItem(title: '背单词', date: today, listGroupName: '学习'),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => CountdownProvider()),
          ChangeNotifierProvider(create: (_) => NoteProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => AppLockProvider()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
          ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
          ChangeNotifierProvider(
            create: (_) => AppUpdateService(
              repo: 'dq52099/duoyi',
              currentVersion: AppVersion.name,
            ),
          ),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('工作 1'), findsOneWidget);
    expect(find.text('学习 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, '周'));
    await tester.pumpAndSettle();
    expect(find.text('准备周会'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);

    await tester.tap(
      find.ancestor(of: find.text('工作 1'), matching: find.byType(FilterChip)),
    );
    await tester.pumpAndSettle();

    expect(find.text('准备周会'), findsOneWidget);
    expect(find.text('背单词'), findsNothing);

    await tester.tap(
      find.ancestor(of: find.text('全部项目'), matching: find.byType(FilterChip)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, '日'));
    await tester.pumpAndSettle();
    expect(find.text('准备周会'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);

    await tester.tap(
      find.ancestor(of: find.text('工作 1'), matching: find.byType(FilterChip)),
    );
    await tester.pumpAndSettle();

    expect(find.text('准备周会'), findsOneWidget);
    expect(find.text('背单词'), findsNothing);

    await tester.tap(
      find.ancestor(of: find.text('全部项目'), matching: find.byType(FilterChip)),
    );
    await tester.pumpAndSettle();

    expect(find.text('准备周会'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);
  });
}
