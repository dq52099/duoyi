import 'dart:convert';
import 'dart:io';

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
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
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
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('今日和我的概览/入口样式保持独立且不过度放大', () {
    final today = File('lib/screens/today_screen.dart').readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    expect(today, contains('constraints.maxWidth < 520 ? 2.55 : 3.65'));
    expect(mine, contains('constraints.maxWidth < 520 ? 2.55 : 3.65'));
    expect(surface, contains('fontSize: 12.5'));
    expect(surface, contains('fontSize: 10'));
    expect(surface, contains('iconBoxSize = 28'));

    expect(mine, contains('class _TileGroup'));
    expect(mine, contains('border: Border.all'));
    expect(mine, contains('alpha: isDark ? 0.76 : 1'));
    expect(mine, contains("label: '目标管理'"));
    expect(mine, contains("label: '生日'"));
    expect(mine, contains("label: '纪念日'"));
    expect(mine, contains("label: '倒数日'"));
    expect(mine, contains('const MemorialAnniversaryScreen()'));
    expect(mine, contains('const BirthdayScreen()'));
    expect(mine, contains('const CountdownScreen()'));
    expect(mine, contains("label: '备份'"));
    expect(mine, contains("label: '恢复数据'"));
    expect(mine, contains("label: '许愿与反馈'"));
    expect(mine, contains('FeedbackScreen(initialCategory: category)'));
    expect(mine, contains('AlmanacEntryMode.almanac'));
    expect(mine, contains('AlmanacEntryMode.calendar'));
    expect(mine, contains('BackupEntryMode.backup'));
    expect(mine, contains('BackupEntryMode.restore'));
    expect(mine, isNot(contains("label: '纪念日 · 生日 · 倒数'")));
    expect(mine, isNot(contains("label: '黄历 · 万年历'")));
    expect(mine, isNot(contains("label: '备份 · 恢复'")));
    expect(mine, isNot(contains("label: '功能建议'")));
    expect(mine, isNot(contains("label: '问题反馈'")));
    expect(mine, isNot(contains("label: '许愿池'")));

    expect(
      mine.indexOf("title: '行动计划'"),
      lessThan(mine.indexOf("title: '记录回顾'")),
    );
    expect(
      mine.indexOf("title: '记录回顾'"),
      lessThan(mine.indexOf("title: '日程日期'")),
    );
    expect(
      mine.indexOf("title: '个性安全'"),
      lessThan(mine.indexOf("title: '数据协作'")),
    );
  });

  testWidgets('TodayScreen and MineScreen render on desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('待办'), findsWidgets);
    expect(find.text('习惯'), findsWidgets);
    expect(find.text('专注'), findsWidgets);
    expect(find.text('日记'), findsWidgets);
    expect(find.text('今日代表'), findsNothing);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(MineScreen), findsOneWidget);
    expect(find.text('行动计划'), findsOneWidget);
    expect(find.text('记录回顾'), findsOneWidget);
    expect(find.text('日程日期'), findsOneWidget);
    expect(find.text('智能工具'), findsOneWidget);
    expect(find.text('个性安全'), findsOneWidget);
    expect(find.text('目标管理'), findsOneWidget);
    expect(find.text('效率评分'), findsOneWidget);
    expect(find.text('综合评分'), findsNothing);
    expect(find.text('纪念日'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('倒数日'), findsOneWidget);
    expect(find.text('黄历'), findsOneWidget);
    expect(find.text('万年历'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('通知支持'),
      600,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('数据协作'), findsOneWidget);
    expect(find.text('通知支持'), findsOneWidget);
    expect(find.text('导出为日历 (.ics)'), findsOneWidget);
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('恢复数据'), findsOneWidget);
    expect(find.text('许愿与反馈'), findsOneWidget);
    expect(find.text('纪念日 · 生日 · 倒数'), findsNothing);
    expect(find.text('黄历 · 万年历'), findsNothing);
    expect(find.text('备份 · 恢复'), findsNothing);
    expect(find.text('功能建议'), findsNothing);
    expect(find.text('问题反馈'), findsNothing);
    expect(find.text('许愿池'), findsNothing);
  });

  testWidgets('AnniversaryScreen can open a specific tab directly', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AnniversaryScreen(initialTab: 1)));
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller?.index, 1);
    expect(find.text('生日'), findsWidgets);
    expect(find.text('纪念日 · 生日 · 倒数'), findsNothing);
  });

  testWidgets('Birthday and countdown entries use independent pages', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const BirthdayScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(BirthdayScreen), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('生日'), findsWidgets);

    await tester.pumpWidget(_wrap(const CountdownScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(CountdownScreen), findsOneWidget);
    expect(find.text('倒数日'), findsWidgets);
    expect(find.byType(AnniversaryScreen), findsNothing);
  });

  testWidgets(
    'Mine notification records open as a scalable page separate from preferences',
    (tester) async {
      final now = DateTime(2026, 5, 22, 8, 30);
      final storedHistory = List.generate(55, (i) {
        return jsonEncode({
          'id': 'history-$i',
          'title': '通知标题 $i',
          'body': i == 54 ? '最后一页记录' : '通知内容 $i',
          'scheduledTime': now.subtract(Duration(minutes: i)).toIso8601String(),
          'type': i.isEven
              ? NotificationType.todo.index
              : NotificationType.general.index,
          'relatedId': 'related-$i',
        });
      });
      SharedPreferences.setMockInitialValues({
        'duoyi_notif_history': storedHistory,
      });

      final notificationService = NotificationService();
      await notificationService.loadHistoryForTest();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TodoProvider()),
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
            ChangeNotifierProvider<NotificationService>.value(
              value: notificationService,
            ),
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
          child: const MaterialApp(home: MineScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('通知支持'),
        700,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('通知记录'), findsOneWidget);
      expect(find.text('通知设置'), findsOneWidget);
      expect(find.text('55 条'), findsWidgets);

      await tester.ensureVisible(find.text('通知记录'));
      final historyLabelCenter = tester.getCenter(find.text('通知记录').first);
      await tester.tapAt(historyLabelCenter + const Offset(0, 28));
      await tester.pumpAndSettle();

      expect(find.text('通知记录'), findsWidgets);
      expect(find.byTooltip('上一页'), findsOneWidget);
      expect(find.byTooltip('下一页'), findsOneWidget);
      expect(find.textContaining('第 1 / 2 页'), findsOneWidget);
      expect(find.textContaining('每页 50 条'), findsOneWidget);
      expect(find.text('通知标题 0'), findsOneWidget);
      expect(find.text('最后一页记录'), findsNothing);

      await tester.scrollUntilVisible(
        find.byTooltip('下一页'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('通知标题 54'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('通知标题 54'), findsOneWidget);
      expect(find.text('最后一页记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'related-54');
      await tester.pumpAndSettle();
      expect(find.text('通知标题 54'), findsOneWidget);
      expect(find.textContaining('已筛出 1 / 55 条'), findsOneWidget);
    },
  );

  testWidgets('ProfileScreen edits and persists local profile fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '旧昵称',
      displayName: '旧显示名',
      email: 'old@example.com',
      avatarUrl: 'https://example.com/old.png',
      bio: '旧简介',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('登录账号'), findsOneWidget);
    expect(find.text('旧显示名'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, '显示名'), '新显示名');
    await tester.enterText(find.widgetWithText(TextField, '本地昵称'), '新昵称');
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱（仅本地展示，不用于登录或找回）'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的个人简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(userProvider.profile.username, '新昵称');
    expect(userProvider.profile.displayName, '新显示名');
    expect(userProvider.profile.avatarInitials, '新');
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.bio, '新的个人简介');
    expect(find.text('本地资料已更新'), findsWidgets);
  });

  testWidgets('ProfileScreen edits account profile through auth API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <String>[];
    final requestBodies = <Map<String, dynamic>>[];
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        email: 'old@example.com',
        emailVerified: true,
        displayName: '旧昵称',
        avatar: 'https://example.com/old.png',
        bio: '旧简介',
        token: 'token-1',
        coinBalance: 88,
        lifetimeCoins: 144,
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'PATCH' &&
              request.url.path == '/api/auth/profile') {
            expect(request.headers['authorization'], 'Bearer token-1');
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': body['email'],
                'email_verified': false,
                'display_name': body['display_name'],
                'avatar': 'https://example.com/old.png',
                'bio': body['bio'],
                'is_admin': false,
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final userProvider = UserProvider();
    await userProvider.updateProfile(username: '旧本地昵称');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('修改登录密码'), findsOneWidget);
    expect(find.text('old@example.com · 已验证'), findsOneWidget);
    expect(find.textContaining('时光币 88'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '昵称'), '新昵称');
    final usernameField = tester.widget<TextField>(
      find.widgetWithText(TextField, '用户名'),
    );
    expect(usernameField.readOnly, isTrue);
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '邮箱验证码'), '123456');
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的账号简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(requests, contains('PATCH /api/auth/profile'));
    expect(requestBodies.single, {
      'email': 'new@example.com',
      'email_code': '123456',
      'display_name': '新昵称',
      'bio': '新的账号简介',
    });
    expect(auth.state.username, 'old-user');
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isFalse);
    expect(auth.state.displayName, '新昵称');
    expect(auth.state.avatar, 'https://example.com/old.png');
    expect(auth.state.bio, '新的账号简介');
    expect(auth.state.coinBalance, 88);
    expect(auth.state.lifetimeCoins, 144);
    expect(userProvider.profile.username, '新昵称');
    expect(userProvider.profile.displayName, '新昵称');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.emailVerified, isFalse);
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.bio, '新的账号简介');
    expect(find.text('资料已更新'), findsWidgets);
  });
}
