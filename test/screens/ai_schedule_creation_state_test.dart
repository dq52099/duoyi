import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ai_schedule_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _title = 'Literal title / 原始标题';
const _notes = 'Literal notes / 原始备注';
const _diagnostic = 'Private transport diagnostic / 私有诊断';
const _origin = AuthState(
  userId: 'schedule-A',
  username: 'account-A',
  token: 'synthetic-schedule-A',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_state': jsonEncode(_origin.toJson()),
      AccountLocalDataCleaner.accountDataOwnerKey: 'id:schedule-A',
    });
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final calendar in [true, false]) {
      testWidgets(
        'completion live root theme $brand calendar=$calendar retains saved result',
        (tester) async {
          final f = await _pump(tester, calendar: calendar, liveBrand: brand);
          final theme = tester
              .element(find.byType(AiScheduleScreen))
              .read<ThemeProvider>();
          expect(theme.brand.id, brand);
          await _recognize(tester);
          await _create(tester);
          await tester.pumpAndSettle();
          final dialog = tester.element(find.byType(AppDialog));
          final route = ModalRoute.of(dialog)!;
          final screen = tester.state(find.byType(AiScheduleScreen));
          final savedEvents = f.prefs.getStringList(
            'duoyi_local_calendar_events_v1',
          );
          final savedTodos = f.prefs.getString('todos');
          void expectRetained() {
            final current = tester.element(find.byType(AppDialog));
            expect(current, same(dialog));
            expect(ModalRoute.of(current), same(route));
            expect(route.isCurrent, isTrue);
            expect(
              Theme.of(current).colorScheme,
              theme.brand.theme.colorScheme,
            );
            expect(tester.state(find.byType(AiScheduleScreen)), same(screen));
            expect(find.textContaining(_title), findsWidgets);
            expect(f.savedCount, 1);
            expect(f.storedCount, 1);
            expect(f.ai.recognitions, 1);
            expect(
              f.prefs.getStringList('duoyi_local_calendar_events_v1'),
              savedEvents,
            );
            expect(f.prefs.getString('todos'), savedTodos);
            expect(tester.takeException(), isNull);
          }

          expectRetained();
          for (final next in [
            brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
            brand,
          ]) {
            var done = false;
            final change = theme.setBrand(next).whenComplete(() => done = true);
            await _until(tester, () => done);
            expect(await change, isTrue);
            await tester.pumpAndSettle();
            expect(theme.brand.id, next);
            expectRetained();
            I18n.setLocale(AppLocale.en);
            await tester.pumpAndSettle();
            expectRetained();
          }
          await tester.tap(find.widgetWithText(FilledButton, 'Done').last);
          await tester.pumpAndSettle();
          expect(route.isActive, isFalse);
          expect(find.byType(AiScheduleScreen), findsNothing);
          expect(find.text('Open AI'), findsOneWidget);
          expect(f.savedCount, 1);
          expect(f.storedCount, 1);
          expect(f.ai.recognitions, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final calendar in [true, false]) {
    final kind = calendar ? 'event' : 'task';
    testWidgets('real $kind creation and open completion localize', (
      tester,
    ) async {
      final f = await _pump(tester, calendar: calendar);
      await _recognize(tester);
      await _create(tester);
      await tester.pumpAndSettle();
      expect(f.savedCount, 1);
      expect(f.storedCount, 1);
      expect(find.byType(AppDialog), findsOneWidget);
      final screen = tester.state(find.byType(AiScheduleScreen));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AiScheduleScreen)), same(screen));
      expect(
        find.text(calendar ? 'Event created' : 'Task created'),
        findsWidgets,
      );
      expect(find.textContaining(_title), findsWidgets);
      expect(f.ai.recognitions, 1);
      expect(f.savedCount, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Done').last);
      await tester.pumpAndSettle();
      expect(find.text('Open AI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final throws in [false, true]) {
      testWidgets(
        'rejected $kind storage throws=$throws never reports success and retry inserts once',
        (tester) async {
          final store = _RejectingStore();
          SharedPreferencesStorePlatform.instance = store;
          final f = await _pump(tester, calendar: calendar);
          await _recognize(tester);
          store.rejectKey = calendar
              ? 'flutter.duoyi_local_calendar_events_v1'
              : 'flutter.todos';
          store.throws = throws;
          await _create(tester);
          await tester.pumpAndSettle();
          expect(find.byType(AppDialog), findsNothing);
          expect(find.text(AiScheduleUiCopy.genericSaveFailed), findsOneWidget);
          expect(f.savedCount, 0);
          expect(f.storedCount, 0);
          await _create(tester);
          await tester.pumpAndSettle();
          expect(f.savedCount, 1);
          expect(f.storedCount, 1);
          expect(find.byType(AppDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('permission refusal precedes $kind write', (tester) async {
      final f = await _pump(tester, calendar: calendar, reminder: true);
      f.notifications.ready = false;
      await _recognize(tester);
      await _create(tester);
      await tester.pumpAndSettle();
      expect(f.savedCount, 0);
      expect(f.storedCount, 0);
      expect(f.notifications.permissionCalls, 1);
      expect(find.byType(AppDialog), findsNothing);
      expect(find.textContaining(_diagnostic), findsNothing);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final permissionMessage = find.text(
        AiScheduleUiCopy.renderReminderIssue(
          f.notifications.lastScheduleIssue,
          AppLocale.en,
        ),
      );
      await tester.scrollUntilVisible(
        permissionMessage,
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(permissionMessage, findsOneWidget);
      expect(f.savedCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('covered permission return cannot begin $kind save', (
      tester,
    ) async {
      final f = await _pump(tester, calendar: calendar, reminder: true);
      f.notifications.permissionGate = Completer<bool>();
      await _recognize(tester);
      await _create(tester);
      await tester.pump();
      expect(f.notifications.permissionCalls, 1);
      await _cover(tester, f);
      f.notifications.permissionGate!.complete(true);
      await tester.pumpAndSettle();
      expect(f.savedCount, 0);
      expect(f.storedCount, 0);
      expect(find.text('Cover'), findsOneWidget);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, AiScheduleUiCopy.create),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    for (final sameUser in [false, true]) {
      testWidgets(
        'held $kind permission rejects new session sameUser=$sameUser',
        (tester) async {
          final f = await _pump(tester, calendar: calendar, reminder: true);
          f.notifications.permissionGate = Completer<bool>();
          await _recognize(tester);
          await _create(tester);
          await tester.pump();
          await _replace(tester, f.auth, sameUser: sameUser);
          f.notifications.permissionGate!.complete(true);
          await tester.pumpAndSettle();
          expect(f.savedCount, 0);
          expect(f.storedCount, 0);
          expect(find.byType(AppDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'acknowledged save recovers behind cover and retained callbacks cannot duplicate',
    (tester) async {
      final f = await _pump(tester, calendar: true);
      f.events.resultGate = Completer<void>();
      await _recognize(tester);
      final recognizeCallback = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, AiScheduleUiCopy.recognize),
          )
          .onPressed!;
      await _revealCreate(tester);
      final callback = tester.widget<FilledButton>(_createButton()).onPressed!;
      await _create(tester);
      await _until(tester, () => f.storedCount == 1);
      await _cover(tester, f);
      f.events.resultGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cover'), findsOneWidget);
      expect(find.byType(AppDialog), findsNothing);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text(AiScheduleUiCopy.viewDetails), findsOneWidget);
      recognizeCallback();
      await tester.pumpAndSettle();
      expect(
        f.ai.recognitions,
        1,
        reason: 'An unchanged saved input cannot become another create',
      );
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(f.savedCount, 1);
      expect(f.storedCount, 1);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final calendar in [true, false]) {
    for (final nativeThrows in [false, true]) {
      testWidgets(
        'held actual storage rejects same-user session calendar=$calendar throw=$nativeThrows',
        (tester) async {
          final store = _RejectingStore();
          SharedPreferencesStorePlatform.instance = store;
          final f = await _pump(tester, calendar: calendar);
          await _recognize(tester);
          store.holdKey = calendar
              ? 'flutter.duoyi_local_calendar_events_v1'
              : 'flutter.todos';
          store.throwAfterHold = nativeThrows;
          await _create(tester);
          await _until(tester, () => store.started.isCompleted);
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          await _replace(tester, f.auth, sameUser: true);
          expect(AccountLocalDataCleaner.accountDataGeneration, generation);
          store.release.complete();
          await tester.pumpAndSettle();
          expect(f.savedCount, 0);
          expect(f.storedCount, 0);
          expect(find.byType(AppDialog), findsNothing);
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            isEmpty,
          );
          expect(find.textContaining(_title), findsNothing);
          expect(find.textContaining(_diagnostic), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'real todo reminder result reports partial success without raw diagnostics',
    (tester) async {
      final f = await _pump(tester, calendar: false, reminder: true);
      await _recognize(tester);
      await _create(tester);
      await tester.pumpAndSettle();
      expect(f.savedCount, 1);
      expect(f.storedCount, 1);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(
        find.text(AiScheduleUiCopy.createdTaskWithReminderIssue),
        findsWidgets,
      );
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.textContaining('not registered'), findsWidgets);
      expect(find.textContaining('reminder_scheduler_missing'), findsNothing);
      expect(f.savedCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open completion observes same-user session change and keeps a covering route',
    (tester) async {
      final f = await _pump(tester, calendar: true);
      await _recognize(tester);
      await _create(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      await _cover(tester, f);
      final generation = AccountLocalDataCleaner.accountDataGeneration;
      await _replace(tester, f.auth, sameUser: true);
      expect(AccountLocalDataCleaner.accountDataGeneration, generation);
      expect(find.text('Cover'), findsOneWidget);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(find.textContaining(_title), findsNothing);
      expect(find.byType(AiScheduleScreen), findsOneWidget);
      expect(find.text(AiScheduleUiCopy.accountChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a service NoSuchMethodError does not replay an unguarded save', (
    tester,
  ) async {
    final f = await _pump(tester, calendar: true);
    await _recognize(tester);
    f.events.noSuchBeforeWrite = true;
    await _create(tester);
    await tester.pumpAndSettle();
    expect(f.events.addCalls, 1);
    expect(f.savedCount, 0);
    expect(f.storedCount, 0);
    expect(find.byType(AppDialog), findsNothing);
    expect(find.text(AiScheduleUiCopy.genericSaveFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session invalidation during Navigator push safely removes only its completion',
    (tester) async {
      final f = await _pump(tester, calendar: true);
      await _recognize(tester);
      await _create(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      var replacementDone = false;
      f.observer.onNextPush = () {
        unawaited(
          f.auth
              .loadFromStorage(refreshServerConfig: false)
              .whenComplete(() => replacementDone = true),
        );
      };
      await _cover(tester, f);
      await _until(tester, () => replacementDone);
      await tester.pumpAndSettle();
      expect(find.text('Cover'), findsOneWidget);
      expect(tester.takeException(), isNull);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.text(AiScheduleUiCopy.accountChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing origin removes only its owned completion', (
    tester,
  ) async {
    final f = await _pump(tester, calendar: true);
    final originRoute = ModalRoute.of(
      tester.element(find.byType(AiScheduleScreen)),
    )!;
    await _recognize(tester);
    await _create(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await _cover(tester, f);
    f.navigator.currentState!.removeRoute(originRoute);
    await tester.pumpAndSettle();
    expect(find.text('Cover'), findsOneWidget);
    expect(find.byType(AiScheduleScreen, skipOffstage: false), findsNothing);
    f.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.textContaining(_title), findsNothing);
    expect(find.text('Open AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalidated completion cleanup outlives origin disposal', (
    tester,
  ) async {
    final f = await _pump(tester, calendar: true);
    final originRoute = ModalRoute.of(
      tester.element(find.byType(AiScheduleScreen)),
    )!;
    await _recognize(tester);
    await _create(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    // Remove origin before the deferred completion cleanup in the same frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      f.navigator.currentState!.removeRoute(originRoute);
    });
    var replaced = false;
    f.observer.onNextPush = () {
      unawaited(
        f.auth
            .loadFromStorage(refreshServerConfig: false)
            .whenComplete(() => replaced = true),
      );
    };
    await _cover(tester, f);
    await _until(tester, () => replaced);
    await tester.pumpAndSettle();
    expect(find.text('Cover'), findsOneWidget);
    expect(find.byType(AiScheduleScreen, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    f.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.textContaining(_title), findsNothing);
    expect(find.text('Open AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing auth authority revokes an identical user and token', (
    tester,
  ) async {
    final f = await _pump(tester, calendar: true);
    await _recognize(tester);
    final replacement = AuthProvider(
      initialState: _origin,
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: _origin.token,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
    addTearDown(replacement.dispose);
    f.authority.value = replacement;
    await tester.pumpAndSettle();
    expect(find.byType(AiScheduleScreen), findsOneWidget);
    expect(find.text(AiScheduleUiCopy.accountChanged), findsOneWidget);
    expect(find.textContaining(_title), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    expect(f.savedCount, 0);
    expect(f.storedCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'first server identity preserves legacy session draft and creation',
    (tester) async {
      final f = await _pump(
        tester,
        calendar: true,
        origin: const AuthState(
          username: 'account-A',
          token: 'synthetic-schedule-A',
        ),
      );
      await _recognize(tester);
      final lease = f.auth.captureSessionLease();
      final generation = AccountLocalDataCleaner.accountDataGeneration;
      var done = false;
      final pending = f.auth
          .applyServerAccountSnapshot({
            'user_id': 'schedule-A',
            'username': 'account-A',
          })
          .whenComplete(() => done = true);
      await _until(tester, () => done);
      await pending;
      await tester.pumpAndSettle();
      expect(f.auth.state.userId, 'schedule-A');
      expect(f.auth.isSessionLeaseCurrent(lease), isTrue);
      expect(AccountLocalDataCleaner.accountDataGeneration, generation);
      expect(find.text(AiScheduleUiCopy.accountChanged), findsNothing);
      expect(find.text(_title), findsOneWidget);
      await _create(tester);
      await tester.pumpAndSettle();
      expect(f.savedCount, 1);
      expect(f.storedCount, 1);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _createButton() =>
    find.widgetWithText(FilledButton, AiScheduleUiCopy.create);
Future<void> _recognize(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Literal / 日程输入');
  FocusManager.instance.primaryFocus?.unfocus();
  final button = find.widgetWithText(FilledButton, AiScheduleUiCopy.recognize);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text(_title), findsOneWidget);
}

Future<void> _create(WidgetTester tester) async {
  await _revealCreate(tester);
  await tester.tap(_createButton());
}

Future<void> _revealCreate(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _createButton(),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(_createButton());
  await tester.pumpAndSettle();
  expect(_createButton().hitTestable(), findsOneWidget);
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

Future<void> _cover(WidgetTester tester, _Fixture f) async {
  unawaited(
    f.navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('Cover'))),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _replace(
  WidgetTester tester,
  AuthProvider auth, {
  required bool sameUser,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'auth_state',
    jsonEncode(
      AuthState(
        userId: sameUser ? 'schedule-A' : 'schedule-B',
        username: 'replacement',
        token: 'synthetic-schedule-new',
      ).toJson(),
    ),
  );
  var done = false;
  final pending = auth
      .loadFromStorage(refreshServerConfig: false)
      .whenComplete(() => done = true);
  await _until(tester, () => done);
  await pending;
  // A permission request is deliberately held; its spinner must keep ticking.
  await tester.pump(const Duration(milliseconds: 350));
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  required bool calendar,
  bool reminder = false,
  AuthState origin = _origin,
  String? liveBrand,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    AccountLocalDataCleaner.accountDataOwnerKey,
    'id:schedule-A',
  );
  final auth = AuthProvider(
    initialState: origin,
    client: ApiClient(
      baseUrl: 'https://duoyi.test',
      token: origin.token,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    ),
  );
  final ai = _Ai(
    AiScheduleDraft(
      type: calendar ? AiScheduleType.calendar : AiScheduleType.todo,
      title: _title,
      notes: _notes,
      startAt: DateTime(2100, 10, 13, 15),
      endAt: calendar ? DateTime(2100, 10, 13, 16) : null,
      reminderEnabled: reminder,
    ),
  );
  final events = _Calendar();
  final todos = TodoProvider();
  final notifications = _Notifications();
  final theme = ThemeProvider();
  if (liveBrand != null) {
    await prefs.setString('active_brand', liveBrand);
    await prefs.setStringList('theme_unlocked_brands', [
      'defaultBrand',
      'liquidGlass',
    ]);
    await theme.loadFromStorage();
  }
  final f = _Fixture(auth, ai, events, todos, notifications, prefs, calendar);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await AccountPreferenceWrites.drain();
    auth.dispose();
    ai.dispose();
    events.dispose();
    todos.dispose();
    notifications.dispose();
    theme.dispose();
    f.authority.dispose();
  });
  Widget buildApp() => MaterialApp(
    navigatorKey: f.navigator,
    navigatorObservers: [f.observer],
    theme: theme.brand.theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.6)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const BrandRouteSurface(child: AiScheduleScreen()),
            ),
          ),
          child: const Text('Open AI'),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    ValueListenableBuilder<AuthProvider>(
      valueListenable: f.authority,
      builder: (_, authority, child) =>
          ChangeNotifierProvider<AuthProvider>.value(
            value: authority,
            child: child,
          ),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AiService>.value(value: ai),
          ChangeNotifierProvider<CalendarProvider>.value(value: events),
          ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ChangeNotifierProvider<NotificationService>.value(
            value: notifications,
          ),
        ],
        child: liveBrand == null
            ? buildApp()
            : AnimatedBuilder(
                animation: theme,
                builder: (context, child) => buildApp(),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open AI'));
  await tester.pumpAndSettle();
  return f;
}

class _Fixture {
  final AuthProvider auth;
  final _Ai ai;
  final _Calendar events;
  final TodoProvider todos;
  final _Notifications notifications;
  final SharedPreferences prefs;
  final bool calendar;
  final navigator = GlobalKey<NavigatorState>();
  final observer = _Observer();
  late final authority = ValueNotifier<AuthProvider>(auth);
  _Fixture(
    this.auth,
    this.ai,
    this.events,
    this.todos,
    this.notifications,
    this.prefs,
    this.calendar,
  );
  int get savedCount =>
      calendar ? events.localEvents.length : todos.todos.length;
  int get storedCount => calendar
      ? (prefs.getStringList('duoyi_local_calendar_events_v1') ?? []).length
      : (jsonDecode(prefs.getString('todos') ?? '[]') as List).length;
}

class _Observer extends NavigatorObserver {
  VoidCallback? onNextPush;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final callback = onNextPush;
    onNextPush = null;
    callback?.call();
  }
}

class _Ai extends AiService {
  final AiScheduleDraft draft;
  int recognitions = 0;
  _Ai(this.draft);
  @override
  bool get enabled => true;
  @override
  Future<AiScheduleDraft> createScheduleDraft(
    String input, {
    DateTime? now,
  }) async {
    recognitions++;
    return draft;
  }
}

class _Calendar extends CalendarProvider {
  Completer<void>? resultGate;
  bool noSuchBeforeWrite = false;
  int addCalls = 0;
  @override
  Future<void> addLocalEvent(
    CalendarEvent event, {
    bool Function()? canWrite,
  }) async {
    addCalls++;
    if (noSuchBeforeWrite) {
      noSuchBeforeWrite = false;
      throw NoSuchMethodError.withInvocation(
        Object(),
        Invocation.method(#synthetic, []),
      );
    }
    await super.addLocalEvent(event, canWrite: canWrite);
    if (resultGate != null) await resultGate!.future;
  }
}

class _Notifications extends NotificationService {
  bool ready = true;
  int permissionCalls = 0;
  Completer<bool>? permissionGate;
  @override
  NotificationScheduleIssue get lastScheduleIssue => NotificationScheduleIssue(
    title: _diagnostic,
    message: _diagnostic,
    happenedAt: DateTime(2026),
    copy: const ReminderIssueCopy.notification(
      NotificationIssueNotice.oncePermissionDenied,
      titleCode: NotificationIssueTitle.aiRegistrationFailed,
    ),
  );
  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) async {
    permissionCalls++;
    return permissionGate == null ? ready : permissionGate!.future;
  }

  @override
  Future<void> scheduleCalendarReminder({
    required String calendarEventId,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool Function()? canContinue,
  }) async {}
}

class _RejectingStore extends InMemorySharedPreferencesStore {
  _RejectingStore() : super.withData({});
  String? rejectKey;
  bool throws = false;
  String? holdKey;
  bool throwAfterHold = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey) {
      holdKey = null;
      started.complete();
      await release.future;
      if (throwAfterHold) throw StateError(_diagnostic);
    }
    if (key == rejectKey) {
      rejectKey = null;
      if (throws) throw StateError(_diagnostic);
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
