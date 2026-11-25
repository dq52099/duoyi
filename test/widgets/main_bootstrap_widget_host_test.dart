// NEW2914. PREPARED ONLY: never compiled, imported, formatted or executed.
// One whole ordered HOST method. Calls production main() exactly once.
// Native publication is a MethodChannel peer. Linux mobile launch branch is open.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/main.dart' as app;
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/crash_guard.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/services/holiday_calendar.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _caseName = 'NEW2914 real main bootstrap ordered HOST ledger';
const _todoId = ' todo /?#&=é ';
const _sentinelTodoId = 'todo /?#&=é';
const _todoTitle = ' 原始任务 / keep & text ';
const _habitId = ' habit /?#&=é ';
const _sentinelHabitId = 'habit /?#&=é';
const _habitTitle = '  喝水 / & é  ';
const _noteId = ' note /?#&=é ';
const _noteText = '完整随手记 / & é\n第二行保持原文；不能为了验收缩短内容。';
const _targets = <String>{
  'DuoyiTodoWidgetProvider', 'DuoyiFocusHabitWidgetProvider',
  'DuoyiHabitWidgetProvider', 'DuoyiCalendarWidgetProvider',
  'DuoyiScheduleWidgetProvider', 'DuoyiGoalWidgetProvider',
  'DuoyiCourseWidgetProvider', 'DuoyiNoteWidgetProvider',
  'DuoyiAnniversaryWidgetProvider', 'DuoyiDiaryWidgetProvider',
};
// Literal independent catalog follows below; no valueKeys used as its oracle.
const _catalog90 = <String>{
  'todo_count',
  'habit_percent',
  'habit_active_count',
  'pomodoro_today',
  'focus_minutes_today',
  'brand_app_title',
  'nav_todo',
  'nav_habit',
  'nav_calendar',
  'nav_focus',
  'widget_first_day_of_week',
  'todo_top3_count',
  'todo_top3_1',
  'todo_top3_1_id',
  'todo_top3_2',
  'todo_top3_2_id',
  'todo_top3_3',
  'todo_top3_3_id',
  'goal_highlight_1',
  'goal_highlight_1_id',
  'goal_highlight_2',
  'goal_highlight_2_id',
  'goal_highlight_3',
  'goal_highlight_3_id',
  'anniversary_highlight_1',
  'anniversary_highlight_1_id',
  'anniversary_highlight_2',
  'anniversary_highlight_2_id',
  'course_highlight_1',
  'course_highlight_1_id',
  'course_highlight_2',
  'course_highlight_2_id',
  'course_highlight_3',
  'course_highlight_3_id',
  'note_highlight_1',
  'note_highlight_1_id',
  'note_highlight_2',
  'note_highlight_2_id',
  'note_highlight_3',
  'note_highlight_3_id',
  'memorial_highlight_1',
  'memorial_highlight_1_id',
  'memorial_highlight_2',
  'memorial_highlight_2_id',
  'memorial_highlight_3',
  'memorial_highlight_3_id',
  'diary_highlight_1',
  'diary_highlight_1_id',
  'diary_highlight_2',
  'diary_highlight_2_id',
  'diary_highlight_3',
  'diary_highlight_3_id',
  'today_event_summary',
  'schedule_highlight_1',
  'schedule_highlight_1_id',
  'schedule_highlight_2',
  'schedule_highlight_2_id',
  'schedule_highlight_3',
  'schedule_highlight_3_id',
  'calendar_month_summary',
  'focus_summary',
  'habit_summary',
  'streak_summary',
  'next_focus_label',
  'focus_timer_count_up',
  'focus_timer_started_at_millis',
  'focus_timer_running',
  'focus_timer_remaining_seconds',
  'focus_timer_total_seconds',
  'focus_timer_ends_at_millis',
  'focus_timer_label',
  'habit_quick_check_id',
  'habit_quick_check_label',
  'widget_theme_brand_id',
  'widget_theme_card_skin_id',
  'widget_theme_dark',
  'widget_theme_primary',
  'widget_theme_background',
  'widget_theme_surface',
  'widget_theme_nav_background',
  'widget_theme_border',
  'widget_theme_text',
  'widget_theme_muted_text',
  'widget_theme_on_primary',
  'widget_theme_accent_start',
  'widget_theme_accent_end',
  'widget_theme_background_asset_key',
  'widget_theme_corner_radius_dp',
  'widget_theme_control_radius_dp',
  'widget_theme_border_width_dp',
};

void main() {
  // Real-clock binding admits the application's private startup timers. The
  // process must be isolated for this whole file, and its terminal collected.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(_caseName, (tester) async {
    final rawOutput = Platform.environment['DUOYI_BOOTSTRAP_2914_LEDGER']?.trim();
    if (rawOutput != null && rawOutput.isNotEmpty && !rawOutput.startsWith('/home/ubuntu/duoyi/evidence/')) {
      throw StateError('A named absolute evidence ledger is required');
    }
    final ledger = <String, Object?>{
      'id': 'NEW2914', 'executed': true, 'accepted': false,
      'mainInvocations': 0, 'case': _caseName, 'stages': <Object?>[],
      'mobileLaunchEntryExecuted': false, 'nativeStoreExecuted': false,
      'osPaintAccepted': false, 'fullStartupTerminalAccepted': false,
    };
    final stages = ledger['stages'] as List<Object?>;
    final privateDir = await Directory.systemTemp.createTemp('duoyi-bootstrap-2914-');
    final oldPaths = PathProviderPlatform.instance;
    final oldStore = SharedPreferencesStorePlatform.instance;
    final oldLocale = I18n.current;
    final oldWriter = HomeWidgetService.publicationWriter;
    final oldDashboard = HomeWidgetService.dashboardDataRefresher;
    final oldValidator = HomeWidgetService.publicationActionValidator;
    final oldLifecycle = HomeWidgetService.widgetLifecycleChanged;
    final oldSupported = HomeWidgetService.supportedForTesting;
    final oldNative = HomeWidgetService.nativePublicationForTesting;
    final oldCrashPath = CrashGuard.logDirectoryOverride;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final peer = _Peer();
    final homeCalls = <MethodCall>[];
    final requests = <String>[];
    final originalFutures = <_Original<dynamic>>[];
    Object? bodyFailure;
    StackTrace? bodyStack;
    final lifetime = _TimerOwner();
    final allHomeCalls = <MethodCall>[];
    await lifetime.run(() async {
    try {
      if (!Platform.isLinux) throw StateError('This candidate is Linux HOST only');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final target = TodoItem(id: _todoId, title: _todoTitle, date: day,
        priority: TodoPriority.high, notes: '原始完整备注 / ?#&=é',
        tags: ['原始标签', 'literal & tag'], timeTargetSeconds: 600,
        createdAt: day, updatedAt: day);
      final sentinel = TodoItem(id: _sentinelTodoId, title: 'Untouched row / 中文',
        date: day, sortOrder: 1, notes: 'sentinel complete JSON',
        createdAt: day, updatedAt: day);
      final habit = Habit(id: _habitId, name: _habitTitle, targetCount: 1,
        activeWeekdays: [0, 1, 2, 3, 4, 5, 6], createdAt: day, updatedAt: day,
        tags: ['保留标签 / & é'], unit: '次');
      final otherHabit = Habit(id: _sentinelHabitId, name: 'Untouched habit / 中文',
        sortOrder: 1, targetCount: 1, createdAt: day, updatedAt: day);
      final note = NoteItem(id: _noteId, content: _noteText,
        createdAt: day, updatedAt: day);
      final initial = <String, Object>{
        'flutter.todos': jsonEncode([target.toJson(), sentinel.toJson()]),
        'flutter.habits': jsonEncode([habit.toJson(), otherHabit.toJson()]),
        'flutter.duoyi_notes': <String>[jsonEncode(note.toJson())],
        'flutter.duoyi_locale_v1': 'en',
        'flutter.pref_first_day_of_week': 1,
        'flutter.pref_notification_quick_add': false,
        'flutter.pref_notification_today_progress': false,
        'flutter.pref_daily_reminder_enabled': false,
        'flutter.pref_daily_report_reminder': false,
        'flutter.pref_weekly_report_reminder': false,
        'flutter.pref_monthly_report_reminder': false,
        'flutter.pref_yearly_report_reminder': false,
      };
      final store = _Store(initial);
      lifetime.storageGates = store.gates;
      SharedPreferencesStorePlatform.instance = store;
      PathProviderPlatform.instance = _PrivatePaths(privateDir.path);
      CrashGuard.logDirectoryOverride = () => privateDir;
      HomeWidgetService.supportedForTesting = true;
      HomeWidgetService.nativePublicationForTesting = true;
      // No writer/dashboard/listener injection. Production main owns them.
      HomeWidgetService.publicationWriter = null;
      HomeWidgetService.dashboardDataRefresher = null;
      HomeWidgetService.publicationActionValidator = null;
      HomeWidgetService.widgetLifecycleChanged = null;
      HomeWidgetService.invalidatePushSignature();
      messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (call) async {
        homeCalls.add(call); allHomeCalls.add(call);
        if (call.method == 'getWidgetData') return null;
        if (call.method == 'initiallyLaunchedFromHomeWidget') return null;
        if (call.method == 'setAppGroupId') {
          expectSync((call.arguments as Map)['groupId'], 'group.com.duoyi.duoyi');
          return true;
        }
        if (call.method == 'updateWidget') {
          peer.trace.add('refresh-request');
          return true;
        }
        if (call.method == 'saveWidgetData') return true;
        throw StateError('Unexpected home_widget ${call.method}');
      });
      messenger.setMockMethodCallHandler(const MethodChannel('home_widget/updates'), (call) async {
        requests.add('plugin-event:${call.method}');
        return null;
      });
      messenger.setMockMethodCallHandler(const MethodChannel('duoyi/widget_launch'), (call) async {
        requests.add('mobile-launch:${call.method}');
        throw StateError('Linux main must not enter this mobile branch');
      });
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (call) async => 'Asia/Shanghai');
      messenger.setMockMethodCallHandler(const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
        requests.add('notification:${call.method}');
        if (call.method == 'getNotificationAppLaunchDetails') {
          return {'notificationLaunchedApp': false};
        }
        if (call.method == 'pendingNotificationRequests') return <Object>[];
        if (call.method == 'getActiveNotifications') return <Object>[];
        return true;
      });
      messenger.setMockMethodCallHandler(peer.channel, peer.respond);
      final boot = http.runWithClient(() async {
        ledger['mainInvocations'] = 1;
        app.main(); // production async-void entry; never await a fabricated Future.
        await _until(tester, () => app.mainShellKey.currentContext != null,
          'production runApp/MainShell mount');
      }, () => MockClient((request) async {
        requests.add('http:${request.method}:${request.url.path}');
        if (request.url.path == '/api/config') return http.Response('{}', 200);
        return http.Response('{"detail":"isolated HOST endpoint unavailable"}', 503);
      }));
      final bootObserved = _Original<void>(boot); originalFutures.add(bootObserved);
      await bootObserved.value();
      final context = app.mainShellKey.currentContext!;
      expect(context.mounted, isTrue);
      final auth = context.read<AuthProvider>();
      expect(auth.runtimeType, AuthProvider);
      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.isGuestWorkspaceReady, isTrue);
      expect(auth.isLocalAccountDataBlocked, isFalse);
      expect(auth.isAccountTransitionInProgress, isFalse);
      final todos = context.read<TodoProvider>();
      final habits = context.read<HabitProvider>();
      final notes = context.read<NoteProvider>();
      final theme = context.read<ThemeProvider>();
      final locale = context.read<LocaleProvider>();
      final prefs = context.read<PreferencesProvider>();
      final audit = context.read<TimeAuditProvider>();
      expect(HomeWidgetService.publicationWriter, isNotNull);
      expect(HomeWidgetService.dashboardDataRefresher, isNotNull);
      expect(HomeWidgetService.publicationActionValidator, isNotNull);
      expect(HomeWidgetService.widgetLifecycleChanged, isNotNull);
      expect(requests.where((e) => e.startsWith('mobile-launch:')), isEmpty);
      await _until(tester, () => requests.contains('plugin-event:listen'), 'real plugin stream subscribe');
      stages.add({'stage': 'real-main-mount', 'auth': 'real hydrated guest',
        'mainFuture': 'async void; mount witnessed, no fabricated terminal'});

      // Calls the production callback to hydrate all 13 inputs and establish
      // baseline. A later listener-only mutation supplies queue evidence.
      final baseline = _Original<bool>(HomeWidgetService.refreshDashboardData());
      originalFutures.add(baseline);
      expect(await baseline.value(), isTrue);
      _assertPublication(peer.document!, todoCount: 2, habitPercent: 0,
        topId: _todoId, topTitle: _todoTitle, brand: 'defaultBrand', locale: 'en');
      expect(todos.todos.map((e) => e.toJson()).toList(), [target.toJson(), sentinel.toJson()]);
      expect(habits.habits.map((e) => e.toJson()).toList(), [habit.toJson(), otherHabit.toJson()]);
      expect(notes.notes.single.toJson(), note.toJson());
      await _durableEqual(store, todos, habits, notes, audit);
      final originalSentinel = _copy(sentinel.toJson());
      final originalOtherHabit = _copy(otherHabit.toJson());
      _assertEmptyCopy(peer.document!, 'en');
      expect(peer.document!.values['todo_top3_2_id'], _sentinelTodoId);
      expect(peer.document!.values['todo_top3_2'], '· ${sentinel.title}');
      expect(peer.document!.values['note_highlight_1'], '· 完整随手记 / & é');
      expect(peer.document!.values['note_highlight_1_id'], 'duoyi://note/${Uri.encodeComponent(_noteId)}');
      stages.add({'stage': 'baseline', 'document': peer.document!.toJson(),
        'receipt': peer.lastAck, 'read': peer.reads.last});
      homeCalls.clear(); peer.trace.clear();

      // Rejected backend write is deliberately applied then reports false;
      // production compensation must restore full bytes before failure returns.
      final rejected = NoteItem(id: ' rejected /?#&=é ', content: 'Rejected full content\n原文保留',
        createdAt: day, updatedAt: day);
      final beforeRejectedStore = await store.getAll();
      final beforeRejectedModels = notes.notes.map((e) => e.toJson()).toList();
      final beforeRejectedRequests = peer.writes.length;
      store.rejectNextKey = 'flutter.duoyi_notes';
      final rejectFuture = _Original<void>(notes.addOrUpdateNotePersisted(rejected));
      originalFutures.add(rejectFuture);
      expect(await rejectFuture.failure(), isNotNull);
      expect(await store.getAll(), beforeRejectedStore);
      expect(notes.notes.map((e) => e.toJson()).toList(), beforeRejectedModels);
      expect(peer.writes.length, beforeRejectedRequests);
      expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      stages.add({'stage': 'durability-rejected', 'restoredStore': await store.getAll(),
        'restoredModels': beforeRejectedModels});

      // Provider mutation has no dashboard call and no harness queue/listener.
      // The only binding allowed to publish it was installed by main().
      final added = NoteItem(id: ' next note /?#&=é ',
        content: '第二篇完整原文 / & é\n保留正文与对象 URI。',
        pinned: true, createdAt: day, updatedAt: day.add(const Duration(milliseconds: 1)));
      final gate = store.hold('flutter.duoyi_notes');
      final publicationGate = peer.holdNextPublication();
      final beforeModels = notes.notes.map((e) => e.toJson()).toList();
      final beforeWrites = peer.writes.length;
      final mutation = _Original<void>(notes.addOrUpdateNotePersisted(added));
      originalFutures.add(mutation);
      await gate.entered.future.timeout(const Duration(seconds: 20));
      expect(notes.notes.map((e) => e.toJson()).toList(), beforeModels);
      expect(peer.writes.length, beforeWrites);
      expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      gate.release.complete();
      await mutation.value();
      await _until(tester, () => publicationGate.ackEntered.isCompleted,
        'main provider listener -> original queue -> real capture');
      expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      publicationGate.ackRelease.complete();
      await _until(tester, () => publicationGate.readEntered.isCompleted,
        'real publication ACK -> ordered fresh read');
      expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      publicationGate.readRelease.complete();
      await _until(tester, () => _refreshedTargets(homeCalls).length == 10,
        'confirmed fresh read -> actual refresh request fanout');
      expect(_refreshedTargets(homeCalls), _targets);
      expect(peer.trace.indexOf('publication-ack-released'), lessThan(peer.trace.indexOf('fresh-read-released')));
      expect(peer.trace.indexOf('fresh-read-released'), lessThan(peer.trace.indexOf('refresh-request')));
      expect(peer.document!.values['note_highlight_1'], '· 第二篇完整原文 / & é');
      expect(peer.document!.values['note_highlight_1_id'], 'duoyi://note/${Uri.encodeComponent(added.id)}');
      await _durableEqual(store, todos, habits, notes, audit);
      expect(todos.todos.singleWhere((e) => e.id == _sentinelTodoId).toJson(), originalSentinel);
      expect(habits.habits.singleWhere((e) => e.id == _sentinelHabitId).toJson(), originalOtherHabit);
      stages.add({'stage': 'listener-queue-ack-read-refresh', 'trace': [...peer.trace],
        'document': peer.document!.toJson(), 'writes': _copy(peer.writes), 'reads': _copy(peer.reads)});

      // Real deep-link handler installed by main, real binding validator and
      // original opaque object route. External channel is not mobile receiver.
      final beforeStale = await store.getAll();
      final staleUri = _boundAction(peer.document!, 'complete_todo', _sentinelTodoId).replace(
        queryParameters: {..._boundAction(peer.document!, 'complete_todo', _sentinelTodoId).queryParameters,
          'widget_account': 'unrelated-owner-2914'});
      await _sendLink(messenger, staleUri);
      await _until(tester, () => find.text('Widget content is out of date. Refresh and try again').evaluate().isNotEmpty,
        'real validator rejects stale action');
      expect(await store.getAll(), beforeStale);
      expect(todos.todos.singleWhere((e) => e.id == _sentinelTodoId).isCompleted, isFalse);
      stages.add({'stage': 'stale-action-rejected', 'uri': staleUri.toString(), 'store': beforeStale});
      await _sendLink(messenger, _bound(peer.document!, 'todo', _todoId));
      await _until(tester, () => find.byType(TodoDetailScreen).evaluate().length == 1, 'exact Todo route');
      expect(tester.widget<TodoDetailScreen>(find.byType(TodoDetailScreen)).todoId, _todoId);
      expect(tester.widget<TodoDetailScreen>(find.byType(TodoDetailScreen)).accountGeneration,
        AccountLocalDataCleaner.accountDataGeneration);
      Navigator.of(app.mainShellKey.currentContext!).pop(); await tester.pump();
      await _sendPluginUri(messenger, _bound(peer.document!, 'habit', _habitId));
      await _until(tester, () => find.byType(HabitDetailScreen).evaluate().length == 1, 'exact Habit route');
      expect(tester.widget<HabitDetailScreen>(find.byType(HabitDetailScreen)).habitId, _habitId);
      Navigator.of(app.mainShellKey.currentContext!).pop(); await tester.pump();
      stages.add({'stage': 'production-external-route', 'todoId': _todoId, 'habitId': _habitId,
        'habitReceiver': 'actual Linux main HomeWidget.widgetClicked plugin-event branch',
        'mobileDeliveryReceipt': 'unsupported on Linux production branch'});

      // Real complete_todo lookup and handler; it retains its original future
      // privately via access.run. No substitute handler Future is invented.
      homeCalls.clear();
      final completeStart = DateTime.now();
      final todoGate = store.hold('flutter.todos');
      final beforeTodoJson = _copy(todos.todos.singleWhere((e) => e.id == _todoId).toJson()) as Map;
      await _sendLink(messenger, _boundAction(peer.document!, 'complete_todo', _todoId));
      await _until(tester, () => todoGate.entered.isCompleted, 'real Todo handler held storage');
      expect(todos.todos.singleWhere((e) => e.id == _todoId).isCompleted, isFalse);
      expect(audit.entries.where((e) => e.sourceId == _todoId), isEmpty);
      todoGate.release.complete();
      await _until(tester, () => todos.todos.singleWhere((e) => e.id == _todoId).isCompleted &&
        audit.entries.where((e) => e.sourceId == _todoId).length == 1 &&
        peer.document!.values['todo_count'] == 1 && _refreshedTargets(homeCalls).length == 10,
        'real Todo default completion-time/durable/capture/refresh');
      final completed = todos.todos.singleWhere((e) => e.id == _todoId);
      final completedJson = completed.toJson();
      expect(completed.updatedAt.isBefore(completeStart), isFalse);
      expect(completed.updatedAt.isAfter(DateTime.now()), isFalse);
      for (final entry in beforeTodoJson.entries) {
        if (!{'isCompleted', 'kanbanColumnId', 'completedAt', 'updatedAt'}.contains(entry.key)) {
          expect(completedJson[entry.key], entry.value, reason: 'full target ${entry.key}');
        }
      }
      expect(completed.kanbanColumnId, 'done');
      expect(completed.completedAt!.isBefore(completeStart), isFalse);
      expect(completed.completedAt!.isAfter(DateTime.now()), isFalse);
      final timeEntry = audit.entries.singleWhere((e) => e.sourceId == _todoId);
      expect(timeEntry.source, TimeEntrySource.todo);
      expect(timeEntry.category, TimeEntryCategory.todo);
      expect(timeEntry.title, _todoTitle);
      expect(timeEntry.endAt, completed.completedAt);
      expect(timeEntry.endAt.difference(timeEntry.startAt).inSeconds, 600);
      await _durableEqual(store, todos, habits, notes, audit);
      expect(todos.todos.singleWhere((e) => e.id == _sentinelTodoId).toJson(), originalSentinel);
      stages.add({'stage': 'real-complete-todo-handler', 'model': completedJson,
        'timeEntry': timeEntry.toJson(), 'document': peer.document!.toJson(),
        'originalPrivateHandlerFuture': 'retained by production WidgetLaunchAccess.run; not exposed'});
      // Duplicate external action is not mobile receipt dedup. It must be
      // harmless because the exact model is already completed.
      await _sendLink(messenger, _boundAction(peer.document!, 'complete_todo', _todoId));
      await tester.pump(const Duration(milliseconds: 100));
      expect(audit.entries.where((e) => e.sourceId == _todoId).length, 1);
      expect(todos.todos.singleWhere((e) => e.id == _todoId).toJson(), completedJson);

      homeCalls.clear();
      final habitGate = store.hold('flutter.habits');
      final beforeHabits = habits.habits.map((e) => e.toJson()).toList();
      await _sendLink(messenger, _boundAction(peer.document!, 'checkin_habit', _habitId));
      await _until(tester, () => habitGate.entered.isCompleted, 'real eligible Habit handler held write');
      expect(habits.habits.map((e) => e.toJson()).toList(), beforeHabits);
      habitGate.release.complete();
      await _until(tester, () => habits.habits.singleWhere((e) => e.id == _habitId).countForDate(day) == 1 &&
        peer.document!.values['habit_percent'] == 50 && _refreshedTargets(homeCalls).length == 10,
        'real Habit handler/main dashboard and listener publication');
      expect(peer.document!.values['habit_active_count'], 2);
      expect(peer.document!.values['habit_quick_check_id'], _sentinelHabitId);
      expect(habits.habits.singleWhere((e) => e.id == _sentinelHabitId).toJson(), originalOtherHabit);
      await _durableEqual(store, todos, habits, notes, audit);
      final changedHabit = habits.habits.singleWhere((e) => e.id == _habitId).toJson();
      final beforeHabit = beforeHabits.singleWhere((e) => e['id'] == _habitId);
      for (final entry in beforeHabit.entries) {
        if (!{'completions', 'completionUpdatedAt', 'currentStreak', 'bestStreak', 'updatedAt'}.contains(entry.key)) {
          expect(changedHabit[entry.key], entry.value, reason: 'complete Habit ${entry.key}');
        }
      }
      expect(changedHabit['currentStreak'], 1); expect(changedHabit['bestStreak'], 1);
      stages.add({'stage': 'real-checkin-habit-handler', 'models': habits.habits.map((e) => e.toJson()).toList(),
        'document': peer.document!.toJson()});

      // Complete startup binding for presentation invalidates A -> B -> A,
      // then keeps an actual zh/liquidGlass capture selected, with no reused ACK.
      final modelInventory = await store.getAll();
      homeCalls.clear();
      final lateGate = peer.holdNextPublication();
      final stalePush = _Original<bool>(HomeWidgetService.refreshDashboardData());
      originalFutures.add(stalePush);
      await _until(tester, () => lateGate.ackEntered.isCompleted, 'held old presentation');
      final toZh = _Original<void>(locale.setLocale(AppLocale.zh)); originalFutures.add(toZh); await toZh.value();
      final toEn = _Original<void>(locale.setLocale(AppLocale.en)); originalFutures.add(toEn); await toEn.value();
      lateGate.ackRelease.complete();
      await _until(tester, () => lateGate.readEntered.isCompleted, 'old presentation original fresh read');
      lateGate.readRelease.complete();
      expect(await stalePush.value(), isFalse);
      expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      stages.add({'stage': 'presentation-A-B-A-rejects-old-success', 'oldRequest': lateGate.request});
      final unlock = _Original<void>(theme.unlockBrand('liquidGlass')); originalFutures.add(unlock); await unlock.value();
      final selectGlass = _Original<bool>(theme.setBrand('liquidGlass')); originalFutures.add(selectGlass);
      expect(await selectGlass.value(), isTrue);
      final finalZh = _Original<void>(locale.setLocale(AppLocale.zh)); originalFutures.add(finalZh); await finalZh.value();
      final sunday = _Original<void>(prefs.setFirstDayOfWeek(7)); originalFutures.add(sunday); await sunday.value();
      final glassPush = _Original<bool>(HomeWidgetService.refreshDashboardData()); originalFutures.add(glassPush);
      expect(await glassPush.value(), isTrue);
      _assertPublication(peer.document!, todoCount: 1, habitPercent: 50,
        topId: _sentinelTodoId, topTitle: sentinel.title, brand: 'liquidGlass', locale: 'zh');
      expect(peer.document!.values['widget_first_day_of_week'], 7);
      for (final entry in modelInventory.entries) {
        if ({'flutter.todos', 'flutter.habits', 'flutter.duoyi_notes', 'flutter.duoyi_time_entries'}.contains(entry.key)) {
          expect((await store.getAll())[entry.key], entry.value);
        }
      }
      _assertEmptyCopy(peer.document!, 'zh');
      stages.add({'stage': 'real-theme-locale-preference', 'document': peer.document!.toJson()});

      // The text-carrying quick action reaches production SmartTodoDraftBuilder
      // and real private quick-create/preflight under mounted Auth/context.
      const quickText = '原始快捷 / keep & é 完整标题';
      final quickBeforeModels = todos.todos.map((e) => e.toJson()).toList();
      final quickGate = store.hold('flutter.todos');
      homeCalls.clear();
      final quickParameters = Map<String, String>.from(
        _boundAction(peer.document!, 'quick_todo', 'unused').queryParameters)
        ..remove('id');
      quickParameters['text'] = quickText;
      final quickUri = _boundAction(peer.document!, 'quick_todo', 'unused').replace(
        queryParameters: quickParameters);
      await _sendLink(messenger, quickUri);
      await _until(tester, () => quickGate.entered.isCompleted, 'real text quick-create held write');
      expect(todos.todos.map((e) => e.toJson()).toList(), quickBeforeModels);
      quickGate.release.complete();
      await _until(tester, () => todos.todos.where((e) => e.title == quickText).length == 1,
        'real SmartTodoDraft/private quick-create durable result');
      final quickModel = todos.todos.singleWhere((e) => e.title == quickText);
      expect(quickModel.id.trim(), isNotEmpty); expect(quickModel.id, isNot(_todoId));
      expect(quickModel.reminderPlan.enabled, isFalse); expect(quickModel.isCompleted, isFalse);
      expect(_day(quickModel.date), _day(day));
      final quickCapture = _Original<bool>(HomeWidgetService.refreshDashboardData());
      originalFutures.add(quickCapture); expect(await quickCapture.value(), isTrue);
      expect(peer.document!.values['todo_count'], 2);
      expect({peer.document!.values['todo_top3_1_id'], peer.document!.values['todo_top3_2_id']},
        {_sentinelTodoId, quickModel.id});
      for (final row in quickBeforeModels) {
        expect(todos.todos.singleWhere((e) => e.id == row['id']).toJson(), row);
      }
      await _durableEqual(store, todos, habits, notes, audit);
      stages.add({'stage': 'real-text-quick-create-handler', 'uri': quickUri.toString(),
        'model': quickModel.toJson(), 'document': peer.document!.toJson(),
        'reminderPreflight': 'real no-enabled-plan branch; permission-bearing flow open'});

      // ACK receipt mismatch and unknown response remain different outcomes.
      // The original dashboard Future is retained, never reconstructed.
      for (final mode in ['mismatch', 'responseUnknown']) {
        homeCalls.clear(); peer.nextFailure = mode;
        final negative = _Original<bool>(HomeWidgetService.refreshDashboardData()); originalFutures.add(negative);
        expect(await negative.value(), isFalse);
        expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
        await _durableEqual(store, todos, habits, notes, audit);
        stages.add({'stage': mode, 'lastRequest': peer.writes.last,
          'lastAck': peer.lastAck, 'reads': _copy(peer.reads)});
        peer.corruptFreshRead = false;
        final retry = _Original<bool>(HomeWidgetService.refreshDashboardData()); originalFutures.add(retry);
        expect(await retry.value(), isTrue);
      }

      // Actual DuoyiApp lifecycle drives the queue. First dirty a provider,
      // then pause via binding observer delivery. No harness lifecycle binding.
      homeCalls.clear();
      final lifecycleNote = NoteItem(id: ' lifecycle /?#&=é ', content: '后台完整原文\n不丢失内容与 URI。',
        pinned: true, createdAt: day, updatedAt: DateTime.now());
      final lifecycleMutation = _Original<void>(notes.addOrUpdateNotePersisted(lifecycleNote));
      originalFutures.add(lifecycleMutation); await lifecycleMutation.value();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _until(tester, () => peer.document!.values['note_highlight_1_id'] ==
        'duoyi://note/${Uri.encodeComponent(lifecycleNote.id)}' && _refreshedTargets(homeCalls).length == 10,
        'real lifecycle background drain');
      stages.add({'stage': 'real-lifecycle-background', 'document': peer.document!.toJson()});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      // A real account preference boundary rejects the production writer. It
      // neither substitutes Auth nor claims a full signed-in logout workflow.
      homeCalls.clear();
      final boundary = _Original<void>(AccountLocalDataCleaner.runPreferenceBoundary(() async {
        final blockedPush = _Original<bool>(HomeWidgetService.publicationWriter!(
          Map<String, Object>.from(peer.document!.values), DateTime.now()));
        originalFutures.add(blockedPush);
        expect(await blockedPush.value(), isFalse);
        expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      }));
      originalFutures.add(boundary); await boundary.value();
      stages.add({'stage': 'real-account-boundary-blocks-writer'});

      // Account invalidation during an original ACK/read blocks late refresh.
      // This public generation fence is real, but is not a complete logout UI.
      homeCalls.clear(); final accountGate = peer.holdNextPublication();
      final accountPush = _Original<bool>(HomeWidgetService.refreshDashboardData()); originalFutures.add(accountPush);
      await _until(tester, () => accountGate.ackEntered.isCompleted, 'old-account original publication');
      final accountBefore = AccountLocalDataCleaner.accountDataGeneration;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(AccountLocalDataCleaner.accountDataGeneration, accountBefore + 1);
      accountGate.ackRelease.complete();
      await _until(tester, () => accountGate.readEntered.isCompleted, 'old-account original read');
      accountGate.readRelease.complete();
      expect(await accountPush.value(), isFalse);
      expect(homeCalls.where((e) => e.method == 'updateWidget'), isEmpty);
      stages.add({'stage': 'account-generation-rejects-late-success', 'oldGeneration': accountBefore,
        'request': accountGate.request});
      expect(allHomeCalls.where((e) => e.method == 'saveWidgetData'), isEmpty);
      ledger['bodyCompleted'] = true;
    } catch (error, stack) {
      bodyFailure = error; bodyStack = stack;
      ledger['bodyCompleted'] = false; ledger['failure'] = '$error'; ledger['stack'] = '$stack';
    } finally {
      // No shutdown seam exists for main's private queue/subscriptions/timers.
      // Leave all diagnostics in the owned private path for terminal collector.
      peer.releaseAll();
      for (final gate in lifetime.storageGates) {
        if (!gate.release.isCompleted) gate.release.complete();
      }
      final cleanupErrors = <String>[];
      for (final original in originalFutures) {
        try { original.observed = await original.terminal.timeout(const Duration(seconds: 20)); }
        catch (error) { cleanupErrors.add('$error'); }
      }
      try { await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 20)); }
      catch (error) { cleanupErrors.add('$error'); }
      try {
        final lifecycleState = tester.binding.lifecycleState;
        if (lifecycleState == AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        } else if (lifecycleState == AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        } else if (lifecycleState == AppLifecycleState.inactive ||
            lifecycleState == AppLifecycleState.detached ||
            !tester.binding.framesEnabled) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        await tester.pumpWidget(const SizedBox.shrink()); await tester.pump();
      }
      catch (error) { cleanupErrors.add('$error'); }
      ledger['observedOriginalFutureCount'] = originalFutures.length;
      ledger['originalFutureTerminal'] = originalFutures.map((e) => e.summary).toList();
      ledger['ownedTimersAtClosure'] = lifetime.close();
      ledger['privateDiagnosticPath'] = privateDir.path;
      ledger['cleanupErrors'] = cleanupErrors;
      ledger['peerTrace'] = peer.trace; ledger['peerWrites'] = peer.writes;
      ledger['peerReads'] = peer.reads; ledger['boundaryRequests'] = requests;
      ledger['homeCalls'] = allHomeCalls.map((e) => {'method': e.method, 'arguments': e.arguments}).toList();
      ledger['collectionRequiresOriginalWaitAndGuardClosure'] = true;
      ledger['elapsedHostEpochMillis'] = DateTime.now().difference(lifetime.started).inMilliseconds;
      if (DateTime.now().difference(lifetime.started) >= const Duration(seconds: 50) && bodyFailure == null) {
        bodyFailure = StateError('Bounded startup epoch exceeded; deferred services may have run');
        bodyStack = StackTrace.current;
        ledger['bodyCompleted'] = false; ledger['failure'] = '$bodyFailure';
      }
      if (rawOutput != null && rawOutput.isNotEmpty) {
        await File(rawOutput).writeAsString('${jsonEncode(ledger)}\n', flush: true);
      }
      // These global boundaries restore only after collection of owned futures.
      // Main-created private async work is still a process-terminal obligation.
      HomeWidgetService.publicationWriter = oldWriter;
      HomeWidgetService.dashboardDataRefresher = oldDashboard;
      HomeWidgetService.publicationActionValidator = oldValidator;
      HomeWidgetService.widgetLifecycleChanged = oldLifecycle;
      HomeWidgetService.supportedForTesting = oldSupported;
      HomeWidgetService.nativePublicationForTesting = oldNative;
      PathProviderPlatform.instance = oldPaths;
      SharedPreferencesStorePlatform.instance = oldStore;
      CrashGuard.reset(); CrashGuard.logDirectoryOverride = oldCrashPath;
      I18n.setLocale(oldLocale); tester.view.reset();
      for (final name in ['home_widget', 'home_widget/updates', 'duoyi/widget_launch',
          'flutter_timezone', 'dexterous.com/flutter/local_notifications', peer.channel.name]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
      if (cleanupErrors.isNotEmpty && bodyFailure == null) {
        bodyFailure = StateError('Original futures/cleanup did not close: $cleanupErrors');
        bodyStack = StackTrace.current;
      }
    }
    });
    if (bodyFailure != null) Error.throwWithStackTrace(bodyFailure!, bodyStack!);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 12)));
}

class _Original<T> {
  _Original(this.original) {
    terminal = original.then<_End<T>>((value) => _End<T>(value),
      onError: (Object error, StackTrace stack) => _End<T>.error(error, stack));
  }
  final Future<T> original;
  late final Future<_End<T>> terminal;
  _End<T>? observed;
  Future<T> value() async {
    final end = await terminal.timeout(const Duration(seconds: 40));
    observed = end;
    if (end.error != null) Error.throwWithStackTrace(end.error!, end.stack!);
    return end.value as T;
  }
  Future<Object?> failure() async {
    observed = await terminal.timeout(const Duration(seconds: 40));
    return observed!.error;
  }
  Map<String, Object?> get summary => {'observed': observed != null,
    'error': observed?.error?.toString(), 'value': observed?.value?.toString()};
}
class _End<T> {
  _End(this.value) : error = null, stack = null;
  _End.error(this.error, this.stack) : value = null;
  final T? value;
  final Object? error;
  final StackTrace? stack;
}
class _StorageGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}
class _Store extends InMemorySharedPreferencesStore {
  _Store(super.data) : super.withData();
  final gates = <_StorageGate>[];
  final gateKeys = <String, _StorageGate>{};
  String? rejectNextKey;
  _StorageGate hold(String key) {
    if (gateKeys.containsKey(key)) throw StateError('Already held: $key');
    final gate = _StorageGate(); gateKeys[key] = gate; gates.add(gate);
    return gate;
  }
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final gate = gateKeys.remove(key);
    if (gate != null) { gate.entered.complete(); await gate.release.future; }
    final result = await super.setValue(type, key, value);
    if (key == rejectNextKey) { rejectNextKey = null; return false; }
    return result;
  }
}
class _PublicationGate {
  final ackEntered = Completer<void>(), ackRelease = Completer<void>();
  final readEntered = Completer<void>(), readRelease = Completer<void>();
  Map<String, Object?>? request;
}
// Storage/transport peer only. It retains literal production requests, checks
// exact CAS/lease/operation identity and emits scripted receipts/fresh reads.
// It does not calculate model counts, expected catalog or a fit/layout oracle.
class _Peer {
  final channel = const MethodChannel('duoyi/widget-publication');
  final trace = <String>[];
  final writes = <Map<String, Object?>>[];
  final reads = <Map<String, Object?>>[];
  final gates = <_PublicationGate>[];
  final memo = <String, Map<String, Object?>>{};
  final originalByOperation = <String, Object?>{};
  WidgetPublication? document;
  Map<String, Object?>? binding, lastAck;
  int revision = 0, desired = 0;
  String epoch = '', lease = '', operation = '';
  AppLocale desiredLocale = AppLocale.en;
  _PublicationGate? nextGate, awaitingRead;
  String? nextFailure;
  bool corruptFreshRead = false;
  _PublicationGate holdNextPublication() {
    if (nextGate != null) throw StateError('Publication already held');
    final gate = _PublicationGate(); nextGate = gate; gates.add(gate); return gate;
  }
  void releaseAll() {
    for (final gate in gates) {
      if (!gate.ackRelease.isCompleted) gate.ackRelease.complete();
      if (!gate.readRelease.isCompleted) gate.readRelease.complete();
    }
  }
  Future<Object?> respond(MethodCall call) async {
    if (call.method == 'readWidgetStore') {
      if (document == null) return {'status': 'absent'};
      final gate = awaitingRead; awaitingRead = null;
      if (gate != null) {
        gate.readEntered.complete(); trace.add('fresh-read-entered');
        await gate.readRelease.future; trace.add('fresh-read-released');
      }
      final rawDocument = _copy(document!.toJson()) as Map<String, dynamic>;
      if (corruptFreshRead) {
        final values = rawDocument['values'] as Map;
        values['todo_count'] = (values['todo_count'] as int) + 1;
        values['todo_top3_count'] = (values['todo_top3_count'] as int) + 1;
      }
      final reply = <String, Object?>{
        'status': 'ready', 'storeRevision': revision, 'binding': binding,
        'ownerEpoch': epoch, 'leaseState': 'active',
        'desiredPresentation': {'revision': desired, 'locale': desiredLocale.name},
        'document': rawDocument, 'lastOperationId': operation,
        // Receipt format boundary only. This scripted digest is not native
        // SHA/CAS durability evidence; original request JSON stays in writes.
        'lastRequestDigest': 'a' * 64,
      };
      reads.add(Map<String, Object?>.from(_copy(reply) as Map));
      trace.add('read:${document!.state.name}'); return reply;
    }
    final args = Map<String, Object?>.from(call.arguments as Map);
    expectSync(args['protocolVersion'], 1);
    final id = args['operationId'] as String;
    expectSync(id.trim(), isNotEmpty);
    if (memo.containsKey(id)) {
      expectSync(args, originalByOperation[id], reason: 'Exact immutable retry request');
      return {...memo[id]!, 'status': 'alreadyApplied'};
    }
    expectSync(args['expectedStoreRevision'], revision == 0 ? null : revision);
    expectSync(args['expectedOwnerEpoch'], revision == 0 ? null : epoch);
    writes.add({'method': call.method, 'arguments': Map<String, Object?>.from(_copy(args) as Map)});
    operation = id;
    final open = call.method == 'openWidgetWorkspace';
    if (open) {
      final requestedBinding = Map<String, Object?>.from(args['binding'] as Map);
      expectSync(requestedBinding, {'kind': 'guest', 'key': 'local-device'});
      final p = args['presentation'] as Map;
      expectSync(p['revision'] as int, greaterThanOrEqualTo(desired));
      desired = p['revision'] as int;
      desiredLocale = p['locale'] == 'en' ? AppLocale.en : AppLocale.zh;
      if (document == null) {
        expectSync(args['mode'], 'initialize');
        binding = requestedBinding;
        epoch = 'bootstrap-owner-2914-$id';
        document = WidgetPublication(ownerEpoch: epoch, publicationRevision: 0,
          localeRevision: desired, state: WidgetPublicationState.cleared,
          locale: desiredLocale, snapshotDay: '', snapshotUtcOffsetMinutes: 0,
          capturedAtMillis: 0, values: Map<String, Object>.from(p['values'] as Map));
      } else {
        expectSync(args['mode'], 'resume');
        expectSync(requestedBinding, binding);
        // Real native resume contract retains every applied document field.
      }
      lease = 'bootstrap-lease-2914-$id';
    } else if (call.method == 'advanceDesiredWidgetPresentation') {
      expectSync(args['writerLeaseId'], lease);
      final p = args['desiredPresentation'] as Map;
      expectSync(p['revision'] as int, greaterThan(desired));
      desired = p['revision'] as int;
      desiredLocale = p['locale'] == 'en' ? AppLocale.en : AppLocale.zh;
    } else if (call.method == 'publishWidgetPublication') {
      expectSync(args['writerLeaseId'], lease);
      expectSync(args['expectedPublicationRevision'], document!.publicationRevision);
      final outgoing = WidgetPublication.tryFromJson(args['document']);
      expectSync(outgoing, isNotNull);
      expectSync(outgoing!.ownerEpoch, epoch);
      expectSync(outgoing.localeRevision, desired);
      expectSync(outgoing.locale, desiredLocale);
      expectSync(outgoing.publicationRevision, document!.publicationRevision + 1);
      document = outgoing;
    } else {
      throw StateError('Unexpected production operation ${call.method}; retain diagnostic and expand peer only after audit');
    }
    revision++;
    final ack = <String, Object?>{
      'status': 'applied', 'operationId': operation,
      'committedStoreRevision': revision, 'ownerEpoch': epoch,
      'publicationRevision': document!.publicationRevision,
      'desiredPresentationRevision': desired,
      'appliedPresentationRevision': document!.localeRevision,
      'documentState': document!.state.name, 'refreshRequested': false,
      if (open) 'writerLeaseId': lease,
    };
    memo[id] = ack; originalByOperation[id] = _copy(args); lastAck = Map<String, Object?>.from(_copy(ack) as Map);
    if (call.method == 'publishWidgetPublication') {
      final gate = nextGate; nextGate = null;
      if (gate != null) {
        gate.request = {'method': call.method, 'arguments': Map<String, Object?>.from(_copy(args) as Map)};
        awaitingRead = gate; gate.ackEntered.complete(); trace.add('publication-ack-entered');
        await gate.ackRelease.future; trace.add('publication-ack-released');
      }
      final failure = nextFailure; nextFailure = null;
      if (failure == 'mismatch') corruptFreshRead = true;
      if (failure == 'responseUnknown') {
        trace.add('publication-response-unknown');
        throw PlatformException(code: 'lost_reply_after_scripted_commit');
      }
    }
    trace.add('ack:${call.method}'); return ack;
  }
}
class _PrivatePaths extends PathProviderPlatform {
  _PrivatePaths(this.path);
  final String path;
  @override Future<String?> getTemporaryPath() async => path;
  @override Future<String?> getApplicationSupportPath() async => path;
  @override Future<String?> getApplicationDocumentsPath() async => path;
  @override Future<String?> getDownloadsPath() async => path;
}
Object? _copy(Object? value) => jsonDecode(jsonEncode(value));
Future<void> _until(WidgetTester tester, bool Function() condition, String stage) async {
  final expires = DateTime.now().add(const Duration(seconds: 40));
  while (!condition()) {
    final owner = Zone.current[_timerOwnerKey] as _TimerOwner?;
    owner?.ensureBoundedLifetime();
    if (DateTime.now().isAfter(expires)) throw TimeoutException(stage);
    if (tester.binding.framesEnabled) {
      await tester.pump(const Duration(milliseconds: 20));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  if (tester.binding.framesEnabled) {
    await tester.pump();
  }
}
Set<String> _refreshedTargets(List<MethodCall> calls) => {
  for (final call in calls)
    if (call.method == 'updateWidget') (call.arguments as Map)['android'] as String,
};
Future<void> _sendLink(TestDefaultBinaryMessenger messenger, Uri uri) async {
  final reply = Completer<ByteData?>();
  await messenger.handlePlatformMessage('duoyi/deep_links',
    const StandardMethodCodec().encodeMethodCall(MethodCall('onLink', uri.toString())), reply.complete);
  final data = await reply.future.timeout(const Duration(seconds: 20));
  if (data != null) const StandardMethodCodec().decodeEnvelope(data);
}
Uri _bound(WidgetPublication doc, String host, String id) => Uri.parse(
  'duoyi://$host/${Uri.encodeComponent(id)}').replace(queryParameters: {
    'source': 'widget', 'widget_day': doc.snapshotDay,
    'widget_offset': doc.snapshotUtcOffsetMinutes.toString(), 'widget_account': doc.ownerEpoch,
  });
Uri _boundAction(WidgetPublication doc, String action, String id) => Uri(
  scheme: 'duoyi', host: 'action', path: '/$action', queryParameters: {
    'id': id, 'source': 'widget', 'widget_day': doc.snapshotDay,
    'widget_offset': doc.snapshotUtcOffsetMinutes.toString(), 'widget_account': doc.ownerEpoch,
  });
void _assertPublication(WidgetPublication doc, {required int todoCount,
    required int habitPercent, required String topId, required String topTitle,
    required String brand, required String locale}) {
  expect(doc.state, WidgetPublicationState.published);
  expect(doc.locale.name, locale);
  expect(doc.values.keys.toSet(), _catalog90);
  expect(doc.values.length, 90);
  expect(doc.values['todo_count'], todoCount);
  expect(doc.values['todo_top3_count'], todoCount);
  expect(doc.values['todo_top3_1_id'], topId);
  expect(doc.values['todo_top3_1'], '· $topTitle');
  expect(doc.values['habit_percent'], habitPercent);
  expect(doc.values['habit_active_count'], 2);
  expect(doc.values['widget_theme_brand_id'], brand);
  expect(doc.values['widget_theme_card_skin_id'], 'plain_card');
  expect(doc.values['focus_timer_running'], isFalse);
  expect(doc.values['focus_timer_started_at_millis'], 0);
  expect(doc.values['focus_timer_ends_at_millis'], 0);
  expect(doc.snapshotDay, _day(DateTime.now()));
  expect(doc.snapshotUtcOffsetMinutes, DateTime.now().timeZoneOffset.inMinutes);
  expect(doc.capturedAtMillis, greaterThan(0));
  expect(doc.capturedAtMillis, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
  for (final key in ['goal_highlight_1_id', 'anniversary_highlight_1_id',
    'course_highlight_1_id', 'memorial_highlight_1_id', 'diary_highlight_1_id']) {
    expect(doc.values[key], '', reason: 'No residual unsupported object target $key');
  }
}
String _day(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
Future<void> _durableEqual(_Store store, TodoProvider todos, HabitProvider habits,
    NoteProvider notes, TimeAuditProvider audit) async {
  await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 30));
  final prefs = await SharedPreferences.getInstance(); await prefs.reload();
  final raw = await store.getAll();
  final todoJson = todos.todos.map((e) => e.toJson()).toList();
  final habitJson = habits.habits.map((e) => e.toJson()).toList();
  final noteJson = notes.notes.map((e) => e.toJson()).toList();
  final auditJson = audit.entries.map((e) => e.toJson()).toList();
  final storedTodos = (jsonDecode(raw['flutter.todos'] as String) as List).cast<Map<String, dynamic>>();
  final cachedTodos = (jsonDecode(prefs.getString('todos')!) as List).cast<Map<String, dynamic>>();
  // Durable insertion order is preserved in storage; TodoProvider._notify sorts in-memory read order.
  final todoById = {for (final row in todoJson) row['id']: row};
  expect(cachedTodos, storedTodos);
  expect(storedTodos.length, todoJson.length);
  for (final row in storedTodos) { expect(row, todoById[row['id']]); }
  expect(jsonDecode(raw['flutter.habits'] as String), habitJson);
  expect(jsonDecode(prefs.getString('habits')!), habitJson);
  final storedNotes = (raw['flutter.duoyi_notes'] as List).map((e) => jsonDecode(e as String)).toList();
  final cachedNotes = prefs.getStringList('duoyi_notes')!.map(jsonDecode).toList();
  // Durable order is part of the snapshot; sorted provider read order may differ.
  final byId = {for (final row in noteJson) row['id']: row};
  expect(storedNotes.length, noteJson.length); expect(cachedNotes, storedNotes);
  for (final row in storedNotes) { expect(row, byId[(row as Map)['id']]); }
  final storedAudit = ((raw['flutter.duoyi_time_entries'] as List?) ?? const []).map((e) => jsonDecode(e as String)).toList();
  final cachedAudit = (prefs.getStringList('duoyi_time_entries') ?? const []).map(jsonDecode).toList();
  expect(cachedAudit, storedAudit); expect(storedAudit.length, auditJson.length);
  final auditById = {for (final row in auditJson) row['id']: row};
  for (final row in storedAudit) { expect(row, auditById[(row as Map)['id']]); }
}

final Object _timerOwnerKey = Object();
class _TimerOwner {
  final started = DateTime.now();
  final timers = <Timer>[];
  List<_StorageGate> storageGates = [];
  Future<void> run(Future<void> Function() body) => runZoned(body,
    zoneValues: {_timerOwnerKey: this},
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        timers.add(timer); return timer;
      },
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createPeriodicTimer(zone, duration, callback);
        timers.add(timer); return timer;
      },
    ));
  void ensureBoundedLifetime() {
    // Never admit deferred-platform65/SystemTray DBus on this HOST boundary.
    // This is a limited startup epoch; deferred tasks remain explicitly open.
    if (DateTime.now().difference(started) >= const Duration(seconds: 50)) {
      throw TimeoutException('Bounded HOST epoch before deferred platform65');
    }
  }
  Map<String, Object?> close() {
    final active = timers.where((timer) => timer.isActive).toList();
    for (final timer in active) { timer.cancel(); }
    return {'observedOriginalTimers': timers.length, 'cancelledAtBoundedTeardown': active.length,
      'remainingActive': timers.where((timer) => timer.isActive).length,
      'fullMainDeferredTasksTerminal': false};
  }
}
void _assertEmptyCopy(WidgetPublication document, String locale) {
  final english = locale == 'en';
  final expected = <String, Object>{
    'goal_highlight_1': english ? 'No active goals' : '暂无进行中目标',
    'anniversary_highlight_1': english ? 'No upcoming anniversaries' : '暂无近期纪念日',
    'course_highlight_1': english ? 'No courses today' : '今日暂无课程',
    'memorial_highlight_1': english ? 'No upcoming anniversaries' : '暂无近期纪念日',
    'diary_highlight_1': english ? 'No diary entries yet' : '暂无日记',
    'calendar_month_summary': _expectedCalendarMonthSummary(english),
    'focus_summary': english ? 'No focus today yet' : '今日还未专注',
    'focus_timer_label': english ? 'Focus countdown' : '专注倒计时',
  };
  for (final entry in expected.entries) { expect(document.values[entry.key], entry.value); }
}

String _expectedCalendarMonthSummary(bool english) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final nextHoliday = HolidayCalendar.nextHoliday(today);
  String? holidayText;
  if (nextHoliday != null) {
    final days = nextHoliday.daysUntil(today);
    final name = nextHoliday.localizedName(
      english ? AppLocale.en : AppLocale.zh,
    );
    if (days == 0) {
      holidayText = english ? '$name today' : '今日$name';
    } else if (days > 0) {
      holidayText = english ? '$name in ${days}d' : '距$name$days天';
    }
  }
  if (english) {
    return holidayText == null
        ? 'Month view · today is marked'
        : '${today.month}/${today.day} · $holidayText';
  }
  final lunar = LunarCalendar.fromSolar(today);
  final term = LunarCalendar.solarTerm(today);
  return <String>[
    '农历${lunar.chineseText}',
    if (term != null && term.isNotEmpty) term,
    ?holidayText,
  ].join(' · ');
}
Future<void> _sendPluginUri(TestDefaultBinaryMessenger messenger, Uri uri) async {
  final reply = Completer<ByteData?>();
  await messenger.handlePlatformMessage('home_widget/updates',
    const StandardMethodCodec().encodeSuccessEnvelope(uri.toString()), reply.complete);
  await reply.future.timeout(const Duration(seconds: 20));
}
