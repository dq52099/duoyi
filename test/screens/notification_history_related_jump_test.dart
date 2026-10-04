import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通知记录卡片点击动线测试。
///
/// - todo / habit / anniversary 且 relatedId 非空：点击卡片先标已读，
///   再经 TodayDetailRouter 跳到关联对象详情；对象已删除时进空态兜底；
/// - pomodoro / general（以及无 relatedId）：点击保持原行为，只切换已读；
/// - 尾部按钮始终只做已读/未读切换。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  NotificationService serviceWithItems(List<NotificationItem> items) {
    final service = NotificationService();
    for (final item in items) {
      service.addHistoryForTest(item);
    }
    return service;
  }

  Future<void> pumpHistory(
    WidgetTester tester, {
    required NotificationService service,
    TodoProvider? todos,
    HabitProvider? habits,
    AnniversaryProvider? anniversaries,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationService>.value(value: service),
          ChangeNotifierProvider<TodoProvider>.value(
            value: todos ?? TodoProvider(),
          ),
          ChangeNotifierProvider<HabitProvider>.value(
            value: habits ?? HabitProvider(),
          ),
          // anniversary 跳转分支读取 AnniversaryProvider；不注册会走
          // TodayDetailRouter 的 ErrorState 兜底而非正常/空态路径。
          ChangeNotifierProvider<AnniversaryProvider>.value(
            value: anniversaries ?? AnniversaryProvider(),
          ),
          // TodayDetailRouter 推入的 BrandRouteSurface 依赖 ThemeProvider。
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: NotificationHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder recordCard(String id) =>
      find.byKey(ValueKey('notification_record_$id'));

  testWidgets('有 relatedId 的待办通知：点击卡片先标已读再进入待办详情', (tester) async {
    final todos = TodoProvider();
    final todo = TodoItem(title: '补交周报');
    await todos.addTodo(todo);

    final service = serviceWithItems([
      NotificationItem(
        id: 'todo-jump',
        title: '待办提醒',
        body: '补交周报',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.todo,
        relatedId: todo.id,
      ),
    ]);
    await pumpHistory(tester, service: service, todos: todos);
    expect(service.unreadCount, 1);

    await tester.tap(recordCard('todo-jump'));
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.text('补交周报'), findsWidgets);
    expect(service.unreadCount, 0);
    expect(service.history.single.isRead, isTrue);
  });

  testWidgets('relatedId 指向已删除待办：进入空态兜底，且记录标为已读', (tester) async {
    final service = serviceWithItems([
      NotificationItem(
        id: 'todo-missing',
        title: '待办提醒',
        body: '对象已删除',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.todo,
        relatedId: 'missing-todo-id',
      ),
    ]);
    // 不注册任何待办 → relatedId 必然指向已删除对象。
    await pumpHistory(tester, service: service);

    await tester.tap(recordCard('todo-missing'));
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.text('这个待办不存在或已被删除'), findsOneWidget);
    expect(service.unreadCount, 0);
    expect(service.history.single.isRead, isTrue);
  });

  testWidgets('已读的待办通知卡片仍可点击进入详情', (tester) async {
    final todos = TodoProvider();
    final todo = TodoItem(title: '回访客户');
    await todos.addTodo(todo);

    final service = serviceWithItems([
      NotificationItem(
        id: 'todo-read-jump',
        title: '待办提醒',
        body: '回访客户',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.todo,
        relatedId: todo.id,
        isRead: true,
      ),
    ]);
    await pumpHistory(tester, service: service, todos: todos);
    expect(service.unreadCount, 0);

    await tester.tap(recordCard('todo-read-jump'));
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(service.unreadCount, 0);
  });

  testWidgets('有 relatedId 的习惯通知：点击卡片进入习惯详情', (tester) async {
    final habits = HabitProvider();
    await habits.addHabit(Habit(id: 'habit-jump', name: '喝水'));

    final service = serviceWithItems([
      NotificationItem(
        id: 'habit-jump-record',
        title: '习惯提醒',
        body: '喝水',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.habit,
        relatedId: 'habit-jump',
      ),
    ]);
    await pumpHistory(tester, service: service, habits: habits);
    expect(service.unreadCount, 1);

    await tester.tap(recordCard('habit-jump-record'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitDetailScreen), findsOneWidget);
    expect(find.text('喝水'), findsWidgets);
    expect(service.unreadCount, 0);
  });

  testWidgets('有 relatedId 的生日通知：点击卡片进入生日页', (tester) async {
    final anniversaries = AnniversaryProvider();
    await anniversaries.add(
      Anniversary(
        id: 'anni-birthday',
        title: '妈妈生日',
        originDate: DateTime(2026, 6, 1),
        type: AnniversaryType.birthday,
      ),
    );

    final service = serviceWithItems([
      NotificationItem(
        id: 'anni-birthday-record',
        title: '纪念日提醒',
        body: '妈妈生日',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.anniversary,
        relatedId: 'anni-birthday',
      ),
    ]);
    await pumpHistory(tester, service: service, anniversaries: anniversaries);
    expect(service.unreadCount, 1);

    await tester.tap(recordCard('anni-birthday-record'));
    await tester.pumpAndSettle();

    expect(find.byType(BirthdayScreen), findsOneWidget);
    expect(service.unreadCount, 0);
    expect(service.history.single.isRead, isTrue);
  });

  testWidgets('有 relatedId 的纪念日通知（memorial）：点击卡片进入纪念日页', (tester) async {
    final anniversaries = AnniversaryProvider();
    await anniversaries.add(
      Anniversary(
        id: 'anni-memorial',
        title: '结婚纪念',
        originDate: DateTime(2026, 6, 1),
        type: AnniversaryType.memorial,
      ),
    );

    final service = serviceWithItems([
      NotificationItem(
        id: 'anni-memorial-record',
        title: '纪念日提醒',
        body: '结婚纪念',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.anniversary,
        relatedId: 'anni-memorial',
      ),
    ]);
    await pumpHistory(tester, service: service, anniversaries: anniversaries);
    expect(service.unreadCount, 1);

    await tester.tap(recordCard('anni-memorial-record'));
    await tester.pumpAndSettle();

    expect(find.byType(MemorialAnniversaryScreen), findsOneWidget);
    expect(service.unreadCount, 0);
  });

  testWidgets(
    '有 relatedId 的倒数日通知（normal）：进入 AnniversaryScreen 且 fixedType=normal',
    (tester) async {
      final anniversaries = AnniversaryProvider();
      await anniversaries.add(
        Anniversary(
          id: 'anni-normal',
          title: '项目上线',
          originDate: DateTime(2026, 6, 1),
          type: AnniversaryType.normal,
        ),
      );

      final service = serviceWithItems([
        NotificationItem(
          id: 'anni-normal-record',
          title: '倒数日提醒',
          body: '项目上线',
          scheduledTime: DateTime(2026, 6, 9, 8),
          type: NotificationType.anniversary,
          relatedId: 'anni-normal',
        ),
      ]);
      await pumpHistory(tester, service: service, anniversaries: anniversaries);
      expect(service.unreadCount, 1);

      await tester.tap(recordCard('anni-normal-record'));
      await tester.pumpAndSettle();

      expect(find.byType(AnniversaryScreen), findsOneWidget);
      expect(find.byType(BirthdayScreen), findsNothing);
      expect(find.byType(MemorialAnniversaryScreen), findsNothing);
      final screen = tester.widget<AnniversaryScreen>(
        find.byType(AnniversaryScreen),
      );
      expect(screen.fixedType, AnniversaryType.normal);
      expect(service.unreadCount, 0);
    },
  );

  testWidgets('relatedId 指向已删除纪念日：进入空态兜底，且记录标为已读', (tester) async {
    final service = serviceWithItems([
      NotificationItem(
        id: 'anni-missing',
        title: '纪念日提醒',
        body: '对象已删除',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.anniversary,
        relatedId: 'missing-anniversary-id',
      ),
    ]);
    // 注册空的 AnniversaryProvider → relatedId 必然指向已删除对象。
    await pumpHistory(tester, service: service);

    await tester.tap(recordCard('anni-missing'));
    await tester.pumpAndSettle();

    expect(find.byType(AnniversaryScreen), findsNothing);
    expect(find.text('这个纪念日不存在或已被删除'), findsOneWidget);
    expect(service.unreadCount, 0);
    expect(service.history.single.isRead, isTrue);
  });

  testWidgets('pomodoro / general 通知：点击仍只切换已读，不发生跳转', (tester) async {
    final service = serviceWithItems([
      NotificationItem(
        id: 'pomo-record',
        title: '番茄钟结束',
        body: '休息一下',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.pomodoro,
        // 即使带 relatedId，pomodoro 也不跳转。
        relatedId: 'pomodoro-session-1',
      ),
      NotificationItem(
        id: 'general-record',
        title: '成就解锁',
        body: '连续打卡 7 天',
        scheduledTime: DateTime(2026, 6, 9, 9),
        type: NotificationType.general,
      ),
    ]);
    await pumpHistory(tester, service: service);
    expect(service.unreadCount, 2);

    await tester.tap(recordCard('pomo-record'));
    await tester.pumpAndSettle();

    expect(find.text('通知记录'), findsOneWidget);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.byType(HabitDetailScreen), findsNothing);
    expect(
      service.history.firstWhere((e) => e.id == 'pomo-record').isRead,
      isTrue,
    );

    await tester.tap(recordCard('general-record'));
    await tester.pumpAndSettle();

    expect(find.text('通知记录'), findsOneWidget);
    expect(
      service.history.firstWhere((e) => e.id == 'general-record').isRead,
      isTrue,
    );

    // 尾部按钮始终保留"标为未读"的显式切换能力。
    final generalToggle = find.descendant(
      of: recordCard('general-record'),
      matching: find.byIcon(Icons.mark_email_unread_outlined),
    );
    expect(generalToggle, findsOneWidget);
    await tester.tap(generalToggle);
    await tester.pumpAndSettle();
    expect(
      service.history.firstWhere((e) => e.id == 'general-record').isRead,
      isFalse,
    );
  });
}
