import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/course_schedule_ui_copy.dart';
import 'package:duoyi/core/global_search.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/time_audit_ui_copy.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/desktop_web/desktop_web_nav.dart';
import 'package:duoyi/desktop_web/desktop_web_workspace.dart';
import 'package:duoyi/desktop_web/views/desktop_habit_view.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/screens/goal_screen.dart';
import 'package:duoyi/screens/time_audit_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/ics_exporter.dart';
import 'package:duoyi/services/web_file_download.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _samplePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';

class _ShellTestFixture {
  final TodoProvider todos = TodoProvider();
  final HabitProvider habits = HabitProvider();
  final CalendarProvider calendar = CalendarProvider();
  final PomodoroProvider pomodoro = PomodoroProvider();
  final ThemeProvider theme = ThemeProvider();
  final CloudSyncProvider cloudSync = CloudSyncProvider();
  late final SyncStatusController syncStatus = SyncStatusController(
    source: cloudSync,
  );
  final UserProvider user = UserProvider();
  final PreferencesProvider preferences = PreferencesProvider();
  final QuickCaptureTemplateProvider quickTemplates =
      QuickCaptureTemplateProvider();
  final LocaleProvider localeProvider = LocaleProvider();
  final CountdownProvider countdown = CountdownProvider();
  final NoteProvider note = NoteProvider();
  final AnniversaryProvider anniversary = AnniversaryProvider();
  final DiaryProvider diary = DiaryProvider();
  final GoalProvider goal = GoalProvider();
  final CourseProvider course = CourseProvider();
  final AppLockProvider appLock = AppLockProvider();
  final AchievementProvider achievement = AchievementProvider();
  final CustomFocusSoundProvider customSound = CustomFocusSoundProvider();
  final FocusRoomProvider focusRoom = FocusRoomProvider();
  final ShareProvider share = ShareProvider();
  final TimeAuditProvider timeAudit = TimeAuditProvider();
  final LocationReminderProvider locationReminder = LocationReminderProvider();
  final CalendarSyncProvider calendarSync = CalendarSyncProvider();
  final NotificationService notifications = NotificationService();
  final AiService ai = AiService();
  final AppUpdateService appUpdate = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
  );
  final AuthProvider auth;

  _ShellTestFixture(this.auth);

  static Future<_ShellTestFixture> create({
    AppLocale locale = AppLocale.zh,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_brand': AppBrands.defaultBrand.id,
      'theme_unlocked_brands': <String>[
        AppBrands.defaultBrand.id,
        AppBrands.liquidGlass.id,
      ],
    });
    I18n.setLocale(locale);
    final auth = AuthProvider(
      initialState: const AuthState(),
      client: ApiClient(
        baseUrl: 'https://duoyi.example.test',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'offline test'}),
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    final fixture = _ShellTestFixture(auth);
    await fixture.localeProvider.setLocale(locale);
    await fixture.theme.loadFromStorage();
    return fixture;
  }

  Widget wrapWithProviders(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<CloudSyncProvider>.value(value: cloudSync),
        ChangeNotifierProvider<SyncStatusController>.value(value: syncStatus),
        ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
        ChangeNotifierProvider<UserProvider>.value(value: user),
        ChangeNotifierProvider<CountdownProvider>.value(value: countdown),
        ChangeNotifierProvider<NoteProvider>.value(value: note),
        ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversary),
        ChangeNotifierProvider<DiaryProvider>.value(value: diary),
        ChangeNotifierProvider<GoalProvider>.value(value: goal),
        ChangeNotifierProvider<CourseProvider>.value(value: course),
        ChangeNotifierProvider<AppLockProvider>.value(value: appLock),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: quickTemplates,
        ),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
        ChangeNotifierProvider<AchievementProvider>.value(value: achievement),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: customSound,
        ),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: focusRoom),
        ChangeNotifierProvider<ShareProvider>.value(value: share),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<LocationReminderProvider>.value(
          value: locationReminder,
        ),
        ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendarSync),
        ChangeNotifierProvider<NotificationService>.value(value: notifications),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
        ChangeNotifierProvider<AppUpdateService>.value(value: appUpdate),
      ],
      child: child,
    );
  }

  Widget wrapDesktopApp(Widget child) {
    return wrapWithProviders(
      ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (_, currentLocale, _) => MaterialApp(
          locale: currentLocale.flutterLocale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: theme.brand.theme,
          home: child,
        ),
      ),
    );
  }

  void dispose() {
    syncStatus.dispose();
    todos.dispose();
    habits.dispose();
    calendar.dispose();
    pomodoro.dispose();
    theme.dispose();
    cloudSync.dispose();
    user.dispose();
    preferences.dispose();
    quickTemplates.dispose();
    localeProvider.dispose();
    countdown.dispose();
    note.dispose();
    anniversary.dispose();
    diary.dispose();
    goal.dispose();
    course.dispose();
    appLock.dispose();
    achievement.dispose();
    customSound.dispose();
    focusRoom.dispose();
    share.dispose();
    timeAudit.dispose();
    locationReminder.dispose();
    calendarSync.dispose();
    notifications.dispose();
    ai.dispose();
    appUpdate.dispose();
    auth.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    WebFileDownload.debugSaveHandler = null;
    MainShell.debugUseDesktopWebWorkspace = null;
    WebTarget.debugDesktopWebBuild = null;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    WebFileDownload.debugSaveHandler = null;
    MainShell.debugUseDesktopWebWorkspace = null;
    WebTarget.debugDesktopWebBuild = null;
  });

  group('CourseSchedule conflicts, reminders, and CSV/ICS import', () {
    test('CourseItem reminderMinutes roundtrip & CourseProvider findConflicts/parseTimetable', () async {
      final legacy = CourseItem.fromJson({
        'id': 'legacy-1',
        'name': '线性代数',
        'weekday': 1,
        'startSection': 1,
      });
      expect(legacy.reminderMinutes, CourseItem.defaultReminderMinutes);

      final custom = CourseItem(
        id: 'course-a',
        name: '编译原理',
        teacher: '陈教授',
        location: '教3-201',
        weekday: 2,
        startSection: 3,
        sectionCount: 2,
        weeks: const [1, 2, 3, 4],
        reminderMinutes: 30,
      );
      final roundtrip = CourseItem.fromJson(custom.toJson());
      expect(roundtrip.reminderMinutes, 30);

      final provider = CourseProvider();
      addTearDown(provider.dispose);
      await provider.add(custom);

      // Overlapping weekday, section, and week -> conflict.
      final overlap = CourseItem(
        id: 'course-b',
        name: '操作系统',
        weekday: 2,
        startSection: 4,
        sectionCount: 2,
        weeks: const [3, 5],
      );
      expect(provider.findConflicts(overlap), hasLength(1));
      expect(provider.findConflicts(overlap, excludeCourseId: 'course-a'), isEmpty);

      // Disjoint week -> no conflict.
      final disjointWeek = CourseItem(
        name: '大学物理',
        weekday: 2,
        startSection: 3,
        sectionCount: 2,
        weeks: const [6, 7],
      );
      expect(provider.findConflicts(disjointWeek), isEmpty);

      // CSV import parse & batch add.
      final csvPreview = CourseProvider.parseTimetable(
        '课程名,星期,起始节,节数,周次,教室,教师,提醒\n'
        '数据结构,一,1,2,1-8(单),A101,赵老师,10\n'
        '数据库系统,三,5-6,1-4,B202,钱老师',
        settings: provider.settings,
      );
      expect(csvPreview.format, 'csv');
      expect(csvPreview.courses, hasLength(2));
      expect(csvPreview.courses.first.weekday, 1);
      expect(csvPreview.courses.first.weeks, [1, 3, 5, 7]);
      expect(csvPreview.courses.first.reminderMinutes, 10);
      expect(csvPreview.courses[1].startSection, 5);
      expect(csvPreview.courses[1].sectionCount, 2);

      // ICS import parse & batch add.
      const sampleIcs = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Artificial Intelligence
DTSTART:20260907T080000
DTEND:20260907T094000
LOCATION:Room C301
DESCRIPTION:Teacher: Prof. Lin
RRULE:FREQ=WEEKLY;COUNT=4;INTERVAL=1
END:VEVENT
END:VCALENDAR
''';
      final icsPreview = CourseProvider.parseTimetable(
        sampleIcs,
        settings: provider.settings,
      );
      expect(icsPreview.format, 'ics');
      expect(icsPreview.courses, hasLength(1));
      expect(icsPreview.courses.single.name, 'Artificial Intelligence');
      expect(icsPreview.courses.single.teacher, 'Prof. Lin');
      expect(icsPreview.courses.single.location, 'Room C301');
      expect(icsPreview.courses.single.weekday, DateTime(2026, 9, 7).weekday);
      expect(icsPreview.courses.single.startSection, 1);
      expect(icsPreview.courses.single.sectionCount, 2);

      final added = await provider.importCourses(icsPreview.courses);
      expect(added, 1);
      expect(provider.courses, hasLength(2));
    });

    testWidgets('CourseScheduleScreen shows conflict warning, reminder picker, and import modal', (tester) async {
      final provider = CourseProvider();
      final theme = ThemeProvider();
      addTearDown(provider.dispose);
      addTearDown(theme.dispose);

      await provider.add(
        CourseItem(
          id: 'existing-course',
          name: '高等数学',
          weekday: 1,
          startSection: 1,
          sectionCount: 2,
          weeks: const [1, 2, 3],
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CourseProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(home: CourseScheduleScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Open Add Course modal: default weekday=1, startSection=1, sectionCount=2 overlaps existing-course.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('course_conflict_banner')),
        findsOneWidget,
      );

      // Select 30m pre-class reminder and enter a non-empty name, then save.
      await tester.ensureVisible(
        find.byKey(const ValueKey('course_reminder_chip_30')),
      );
      await tester.tap(find.byKey(const ValueKey('course_reminder_chip_30')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '概率论');
      await tester.tap(find.widgetWithText(FilledButton, I18n.tr('action.add')));
      await tester.pumpAndSettle();

      expect(provider.courses, hasLength(2));
      expect(provider.courses.last.reminderMinutes, 30);
      expect(
        find.byKey(const ValueKey('course_conflict_badge_existing-course')),
        findsOneWidget,
      );

      // Open timetable import dialog & load sample CSV.
      await tester.tap(
        find.byKey(const ValueKey('course_import_timetable_btn')),
      );
      await tester.pumpAndSettle();
      expect(find.text(CourseScheduleUiCopy.importTitle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('course_import_sample_btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('course_import_preview_box')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('course_import_confirm_btn')));
      await tester.pumpAndSettle();
      expect(provider.courses.length, greaterThanOrEqualTo(4));
    });
  });

  group('GoalScreen filter tabs, search, sort & inline milestones', () {
    testWidgets('supports status tabs, search/sort, inline milestone toggle & initialGoalId', (tester) async {
      final provider = GoalProvider();
      final theme = ThemeProvider();
      addTearDown(provider.dispose);
      addTearDown(theme.dispose);

      await provider.add(
        GoalItem(
          id: 'g-active',
          title: '掌握 Flutter 桌面端',
          description: '完成全部核心模块',
          status: GoalStatus.active,
          autoProgress: true,
          milestones: [
            GoalMilestone(id: 'm1', title: '完成布局设计', isCompleted: true),
            GoalMilestone(id: 'm2', title: '补充组件测试', isCompleted: false),
          ],
        ),
      );
      await provider.add(
        GoalItem(
          id: 'g-done',
          title: '发布年度复盘',
          status: GoalStatus.achieved,
          autoProgress: false,
          progress: 1.0,
        ),
      );
      await provider.add(
        GoalItem(
          id: 'g-paused',
          title: '学习日语 N2',
          status: GoalStatus.paused,
          autoProgress: false,
          progress: 0.25,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(
            home: GoalScreen(initialGoalId: 'g-active'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Inline highlight opens NO blocking GoalEditScreen modal.
      expect(find.text('掌握 Flutter 桌面端'), findsOneWidget);
      expect(find.text('发布年度复盘'), findsOneWidget);
      expect(find.text('学习日语 N2'), findsOneWidget);

      // Inline milestone check-off toggles without opening GoalEditScreen.
      await tester.tap(
        find.byKey(const ValueKey('goal_inline_milestone_g-active_m2')),
      );
      await tester.pumpAndSettle();
      final updated = provider.goals.firstWhere((g) => g.id == 'g-active');
      expect(updated.milestones.every((m) => m.isCompleted), isTrue);
      expect(updated.status, GoalStatus.achieved);

      // Filter by Paused tab -> only Paused goal shows.
      await tester.tap(find.byKey(const ValueKey('goal_filter_paused')));
      await tester.pumpAndSettle();
      expect(find.text('学习日语 N2'), findsOneWidget);
      expect(find.text('发布年度复盘'), findsNothing);

      // Back to All + Search filter.
      await tester.tap(find.byKey(const ValueKey('goal_filter_all')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('goal_search_field')),
        '日语',
      );
      await tester.pumpAndSettle();
      expect(find.text('学习日语 N2'), findsOneWidget);
      expect(find.text('掌握 Flutter 桌面端'), findsNothing);
    });
  });

  group('DiaryScreen search, filters, location, imagePaths & Markdown preview', () {
    testWidgets('supports search/mood/weather/tag filters, Markdown preview & editor location/images', (tester) async {
      final provider = DiaryProvider();
      final theme = ThemeProvider();
      addTearDown(provider.dispose);
      addTearDown(theme.dispose);

      await provider.addOrUpdate(
        DiaryEntry(
          id: 'd-1',
          date: DateTime(2026, 5, 10),
          content: '# 今日复盘\n- [x] 完成重构任务',
          mood: Mood.awesome,
          weather: Weather.sunny,
          tags: const ['工作'],
          location: '杭州西湖',
          imagePaths: const [
            'data:image/png;base64,$_samplePngBase64',
            'photos/fallback-local.png',
          ],
        ),
      );
      await provider.addOrUpdate(
        DiaryEntry(
          id: 'd-2',
          date: DateTime(2026, 5, 9),
          content: '下雨天在家听音乐',
          mood: Mood.okay,
          weather: Weather.rain,
          tags: const ['生活'],
          location: '书房',
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DiaryProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(home: DiaryScreen(initialEntryId: 'd-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DiaryEditScreen), findsNothing);
      expect(find.byKey(const ValueKey('diary_card_d-1')), findsOneWidget);
      expect(find.text('杭州西湖'), findsOneWidget);

      final diaryScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;

      // Toggle Markdown preview on list cards (scroll back up to the search/filter bar
      // after initialEntryId auto-scrolls the lazy ListView down to d-1).
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diary_markdown_preview_toggle')),
        -120,
        scrollable: diaryScroll,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('diary_markdown_preview_toggle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('diary_markdown_preview_toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary_markdown_preview_body')),
        findsWidgets,
      );

      // Expand mood/weather/tag filter bar and filter by Weather.rain.
      await tester.ensureVisible(
        find.byKey(const ValueKey('diary_filter_expand_toggle')),
      );
      await tester.tap(
        find.byKey(const ValueKey('diary_filter_expand_toggle')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('diary_weather_filter_rain')),
      );
      await tester.tap(
        find.byKey(const ValueKey('diary_weather_filter_rain')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary_card_d-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary_card_d-1')), findsNothing);

      // Clear filter & search by location text.
      await tester.ensureVisible(
        find.byKey(const ValueKey('diary_clear_filters_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('diary_clear_filters_btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary_search_field')),
        '西湖',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diary_card_d-1')),
        120,
        scrollable: diaryScroll,
      );
      expect(find.byKey(const ValueKey('diary_card_d-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary_card_d-2')), findsNothing);

      // Open editor on d-1: verify Weather stays the ONLY FilterChip set, toggle MD preview, update location & save.
      await tester.ensureVisible(find.byKey(const ValueKey('diary_card_d-1')));
      await tester.tap(find.byKey(const ValueKey('diary_card_d-1')));
      await tester.pumpAndSettle();
      expect(find.byType(DiaryEditScreen), findsOneWidget);
      expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((c) => c.selected),
        hasLength(1),
      );
      final editorScroll = find
          .descendant(
            of: find.byType(DiaryEditScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diary_editor_location_field')),
        120,
        scrollable: editorScroll,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('diary_editor_location_field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('diary_editor_location_field')),
        '上海外滩',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diary_editor_preview_mode')),
        120,
        scrollable: editorScroll,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('diary_editor_preview_mode')),
      );
      await tester.tap(find.byKey(const ValueKey('diary_editor_preview_mode')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diary_markdown_preview_body')),
        120,
        scrollable: editorScroll,
      );
      expect(
        find.byKey(const ValueKey('diary_markdown_preview_body')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(
        provider.entries.firstWhere((e) => e.id == 'd-1').location,
        '上海外滩',
      );
    });
  });

  group('TimeAuditScreen live stopwatch & direct CSV export', () {
    testWidgets('live stopwatch creates TimeEntry and CSV button exports real CSV', (tester) async {
      final provider = TimeAuditProvider();
      final theme = ThemeProvider();
      addTearDown(provider.dispose);
      addTearDown(theme.dispose);

      WebFileDownloadRequest? capturedDownload;
      WebFileDownload.debugSaveHandler = (request) async {
        capturedDownload = request;
        return WebFileDownloadResult(saved: true, fileName: request.fileName);
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimeAuditProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(home: TimeAuditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('time_audit_stopwatch_card')), findsOneWidget);
      // Must keep zero TextFields on main body at rest so manual add sheet finder stays intact.
      expect(find.byType(TextField), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('time_audit_stopwatch_cat_study')),
      );
      await tester.tap(
        find.byKey(const ValueKey('time_audit_stopwatch_cat_study')),
      );
      await tester.tap(
        find.byKey(const ValueKey('time_audit_stopwatch_rename_btn')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '算法刷题');
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('time_audit_stopwatch_start_btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('time_audit_stopwatch_start_btn')),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('00:00:05'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('time_audit_stopwatch_stop_btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('time_audit_stopwatch_stop_btn')),
      );
      await tester.pumpAndSettle();

      expect(provider.entries, hasLength(1));
      expect(provider.entries.single.title, '算法刷题');
      expect(provider.entries.single.category, TimeEntryCategory.study);
      expect(provider.entries.single.durationSeconds, greaterThanOrEqualTo(5));

      await tester.ensureVisible(
        find.byKey(const ValueKey('time_audit_export_csv_btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('time_audit_export_csv_btn')),
      );
      await tester.pumpAndSettle();

      expect(capturedDownload, isNotNull);
      expect(capturedDownload!.fileName, endsWith('.csv'));
      expect(
        utf8.decode(capturedDownload!.bytes),
        ModuleExporter.timeEntriesCsv(provider.entries),
      );
    });

    testWidgets('TimeAuditScreen(openInitialEntrySheet: false) highlights inline without modal', (tester) async {
      final provider = TimeAuditProvider();
      final theme = ThemeProvider();
      addTearDown(provider.dispose);
      addTearDown(theme.dispose);
      final now = DateTime.now();
      await provider.add(
        TimeEntry(
          id: 'ta-inline-1',
          title: '复盘会议',
          startAt: now.subtract(const Duration(minutes: 30)),
          endAt: now,
          category: TimeEntryCategory.work,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimeAuditProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(
            home: TimeAuditScreen(
              initialEntryId: 'ta-inline-1',
              openInitialEntrySheet: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppModalSheet), findsNothing);
      expect(find.text('复盘会议'), findsOneWidget);
      expect(TimeAuditUiCopy.stopwatchTitle.isNotEmpty, isTrue);
    });
  });

  group('Desktop Web Shell Countdown, Command Palette Deep-Link & Startup Tab', () {
    testWidgets('Cmd+K routes SearchKind.countdown to CountdownScreen, exposes diary/event quick-create, and deep-links selectedEntityId', (tester) async {
      final fixture = await _ShellTestFixture.create(locale: AppLocale.zh);
      addTearDown(fixture.dispose);
      final now = DateTime.now();
      await fixture.countdown.addItem(
        CountdownItem(
          id: 'cd-exam',
          title: '架构师考试倒计时',
          targetDate: DateTime(now.year, now.month, now.day).add(
            const Duration(days: 14),
          ),
        ),
      );
      await fixture.diary.addOrUpdate(
        DiaryEntry(
          id: 'diary-hit-1',
          date: DateTime(now.year, now.month, now.day),
          content: '今天完成了深链测试笔记',
          location: '研发中心',
        ),
      );
      await fixture.note.addOrUpdateNotePersisted(
        NoteItem(
          id: 'note-hit-1',
          content: '重要会议纪要列表',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final controller = DesktopWebNavController(
        initialDestination: DesktopWebDestination.today,
      );
      addTearDown(controller.dispose);

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await tester.pumpWidget(
        fixture.wrapDesktopApp(
          DesktopWebWorkspace(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Verify quick-create includes diary & calendarEvent.
      controller.openCommandPalette(initialMode: DesktopCommandMode.quickCreate);
      await tester.pumpAndSettle();
      expect(find.text('快速写日记'), findsOneWidget);
      expect(find.text('快速新建日程'), findsOneWidget);
      Navigator.of(
        tester.element(find.byType(DesktopWebWorkspace)),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();

      // Search diary -> sets selectedEntityId + selectedEntityKind and embeds DiaryScreen.
      controller.openCommandPalette(initialQuery: '深链测试');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('今天完成了深链测试笔记'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.destination, DesktopWebDestination.diary);
      expect(controller.selectedEntityKind, SearchKind.diary);
      expect(controller.selectedEntityId, 'diary-hit-1');
      expect(find.byType(DiaryScreen), findsOneWidget);

      // Search note -> sets selectedEntityId + displays clickable note deep-link banner.
      controller.openCommandPalette(initialQuery: '会议纪要');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('重要会议纪要列表'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.destination, DesktopWebDestination.notes);
      expect(controller.selectedEntityKind, SearchKind.note);
      expect(controller.selectedEntityId, 'note-hit-1');
      expect(
        find.byKey(const ValueKey('desktop_note_deeplink_note-hit-1')),
        findsOneWidget,
      );

      // Search countdown -> routes directly to CountdownScreen (NEVER AnniversaryScreen).
      controller.openCommandPalette(initialQuery: '架构师考试');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('架构师考试倒计时'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.destination, DesktopWebDestination.countdown);
      expect(controller.selectedEntityKind, SearchKind.countdown);
      expect(controller.selectedEntityId, 'cd-exam');
      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.byType(AnniversaryScreen), findsNothing);
    });

    testWidgets('MainShell DesktopWebWorkspace honors preferences.defaultTab on frame 1', (tester) async {
      final fixture = await _ShellTestFixture.create(locale: AppLocale.zh);
      addTearDown(fixture.dispose);
      await tester.runAsync(() async {
        await fixture.preferences.loadFromStorage();
        await fixture.preferences.setDefaultTab(2); // Habit
      });
      MainShell.debugUseDesktopWebWorkspace = true;

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await tester.pumpWidget(
        fixture.wrapDesktopApp(const MainShell()),
      );
      await tester.pump();
      expect(find.byType(DesktopWebWorkspace), findsOneWidget);
      expect(find.byType(DesktopHabitView), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopHabitView), findsOneWidget);
    });
  });
}
