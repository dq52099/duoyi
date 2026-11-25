// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
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
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/deep_link_service.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/widgets/shared_text_import_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.en));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'native share waits for durable note acceptance before navigation or success',
    (tester) async {
      final f = await _mount(tester);
      f.store.hold = true;
      await _receive(tester, 'literal / 保留原文');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(f.store.started.isCompleted, isTrue);
      expect(f.notes.notes, isEmpty);
      expect(find.byType(NoteScreen), findsNothing);
      expect(find.text('Note saved'), findsNothing);
      f.store.release.complete();
      await tester.pumpAndSettle();
      expect(f.notes.notes.single.content, 'literal / 保留原文');
      expect(find.byType(NoteScreen), findsOneWidget);
      expect(find.text('Note saved'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('duoyi_notes')!;
      expect((jsonDecode(stored.single) as Map)['content'], 'literal / 保留原文');
    },
  );

  testWidgets(
    'rejected share keeps original text for live bilingual explicit retry',
    (tester) async {
      final f = await _mount(tester);
      f.store.reject = true;
      await _receive(tester, 'retry original / 原文');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(f.notes.notes, isEmpty);
      expect(find.byType(NoteScreen), findsNothing);
      expect(
        find.text('Could not import the text. Please try again'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text('导入失败，请稍后重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedTextImportSheet), findsOneWidget);
      expect(find.text('retry original / 原文'), findsOneWidget);
      await tester.tap(find.text('保存笔记'));
      await tester.pumpAndSettle();
      expect(f.notes.notes, hasLength(1));
      expect(f.store.ids, hasLength(2));
      expect(f.store.ids.first, f.store.ids.last);
      expect(find.text('已保存笔记'), findsOneWidget);
    },
  );

  testWidgets(
    'account cleanup during accepted note write prevents old navigation and feedback',
    (tester) async {
      final f = await _mount(tester);
      f.store.hold = true;
      await _receive(tester, 'departing shared text');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(f.store.started.isCompleted, isTrue);
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences();
      f.notes.resetLocalState();
      f.store.release.complete();
      await tester.pumpAndSettle();
      await cleanup;
      await tester.pumpAndSettle();
      expect(f.notes.notes, isEmpty);
      expect(find.byType(NoteScreen), findsNothing);
      expect(find.text('Note saved'), findsNothing);
      expect(
        find.text('Could not import the text. Please try again'),
        findsNothing,
      );
      expect(
        (await SharedPreferences.getInstance()).getStringList('duoyi_notes'),
        isNull,
      );
    },
  );

  testWidgets(
    'a covering route survives late accepted note save without stale navigation',
    (tester) async {
      final f = await _mount(tester);
      f.store.hold = true;
      await _receive(tester, 'accepted original');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      Navigator.of(mainShellKey.currentContext!).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('newer route')),
        ),
      );
      await tester.pumpAndSettle();
      f.store.release.complete();
      await tester.pumpAndSettle();
      expect(f.notes.notes, hasLength(1));
      expect(find.text('newer route'), findsOneWidget);
      expect(find.byType(NoteScreen), findsNothing);
      expect(find.text('Note saved'), findsNothing);
    },
  );

  testWidgets(
    'incoming share from a secondary page still completes navigation',
    (tester) async {
      final f = await _mount(tester);
      Navigator.of(mainShellKey.currentContext!).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('original secondary page')),
        ),
      );
      await tester.pumpAndSettle();
      await _receive(tester, 'shared while on secondary page');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(f.notes.notes, hasLength(1));
      expect(find.byType(NoteScreen), findsOneWidget);
      expect(find.text('Note saved'), findsOneWidget);
    },
  );

  testWidgets(
    'held reminder permission rejects old-account shared todo before provider write',
    (tester) async {
      final f = await _mount(tester);
      await _receive(tester, '明天下午3点开会');
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(f.notification.started.isCompleted, isTrue);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      f.notification.release.complete(true);
      await tester.pumpAndSettle();
      expect(f.todos.todos, isEmpty);
      expect(find.textContaining('Task added'), findsNothing);
    },
  );

  testWidgets(
    'lock during permission reopens the choice and never imports automatically',
    (tester) async {
      final f = await _mount(tester);
      await f.lock.setPin('2468');
      await _receive(tester, '明天下午3点开会');
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(f.notification.started.isCompleted, isTrue);
      f.lock.lock();
      f.notification.release.complete(true);
      await tester.pumpAndSettle();
      expect(f.todos.todos, isEmpty);
      await f.lock.unlockWith('2468');
      await tester.pumpAndSettle();
      expect(find.byType(SharedTextImportSheet), findsOneWidget);
      expect(f.todos.todos, isEmpty);
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(f.notes.notes, hasLength(1));
      expect(find.text('Note saved'), findsOneWidget);
    },
  );
}

Future<void> _receive(WidgetTester tester, String text) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'duoyi/deep_links',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onSharedText', text),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
  expect(find.byType(SharedTextImportSheet), findsOneWidget);
}

Future<
  ({
    NoteProvider notes,
    TodoProvider todos,
    AppLockProvider lock,
    _Store store,
    _Notification notification,
  })
>
_mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  final notes = NoteProvider();
  final todos = TodoProvider();
  final lock = AppLockProvider();
  final notification = _Notification();
  DeepLinkService.onSharedText = receiveSharedText;
  await DeepLinkService.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ChangeNotifierProvider<NotificationService>.value(value: notification),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => PomodoroProvider()),
        ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CountdownProvider()),
        ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => AchievementProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
        ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
        ChangeNotifierProvider(
          create: (_) =>
              AppUpdateService(repo: 'dq52099/duoyi', currentVersion: '0.0.0'),
        ),
      ],
      child: const DuoyiApp(),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    DeepLinkService.onSharedText = null;
    if (store.hold && !store.release.isCompleted) store.release.complete();
    if (notification.started.isCompleted && !notification.release.isCompleted) {
      notification.release.complete(false);
    }
    await AccountPreferenceWrites.drain();
    notes.dispose();
    todos.dispose();
    lock.dispose();
    notification.dispose();
  });
  return (
    notes: notes,
    todos: todos,
    lock: lock,
    store: store,
    notification: notification,
  );
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool hold = false;
  bool reject = false;
  final started = Completer<void>();
  final release = Completer<void>();
  final ids = <String>[];

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.duoyi_notes') return super.setValue(type, key, value);
    ids.add((jsonDecode((value as List<String>).last) as Map)['id'] as String);
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (reject) {
      reject = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

class _Notification extends NotificationService {
  final started = Completer<void>();
  final release = Completer<bool>();
  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) {
    if (!started.isCompleted) started.complete();
    return release.future;
  }
}
