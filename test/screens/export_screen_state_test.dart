import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/export_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final ann in [true, false]) {
    for (final cal in [true, false]) {
      testWidgets('export ranges anniversaries=$ann calendar=$cal', (
        tester,
      ) async {
        final h = _Harness();
        await h.mount(tester);
        try {
          if (!ann) await _range(tester, 0, false);
          if (!cal) await _range(tester, 1, false);
          final generate = _generate(tester);
          if (!ann && !cal) {
            expect(generate, isNull);
            expect(_preview(tester), isNull);
            expect(find.text('请至少选择一个范围后生成导出。'), findsOneWidget);
          } else {
            generate!();
            await tester.pumpAndSettle();
            await _showPreview(tester);
            final text = _preview(tester)!;
            expect('BEGIN:VCALENDAR'.allMatches(text), hasLength(1));
            expect('END:VCALENDAR'.allMatches(text), hasLength(1));
            expect(text.contains('UID:anni_birthday-A@duoyi'), ann);
            // Only the independent external event deliberately uses this ID;
            // the aggregate projection with the same ID must be excluded.
            expect(
              'UID:anniversary_birthday-A@duoyi'.allMatches(text),
              hasLength(cal ? 1 : 0),
            );
            expect(text.contains('SUMMARY:External original'), cal);
            expect(text.contains('UID:local-A@duoyi'), cal);
            expect(text.contains('UID:external-anniversary@duoyi'), cal);
            expect(text.contains('RRULE:FREQ=YEARLY'), ann);
            expect(text.contains('DESCRIPTION:原始描述'), ann);
          }
        } finally {
          await h.dispose(tester);
        }
      });
    }
  }

  testWidgets(
    'real branded route retains range bytes State and scroll across locale',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      try {
        await _range(tester, 1, false);
        _generate(tester)!();
        await tester.pumpAndSettle();
        await _showPreview(tester);
        final text = _preview(tester)!;
        final state = tester.state(find.byType(ExportScreen));
        final scroll = tester.state<ScrollableState>(_listScrollable());
        final offset = scroll.position.pixels;
        expect(text, contains('X-WR-CALNAME:多仪 · 纪念日'));
        for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(
            identical(state, tester.state(find.byType(ExportScreen))),
            isTrue,
          );
          expect(
            identical(scroll, tester.state<ScrollableState>(_listScrollable())),
            isTrue,
          );
          expect(scroll.position.pixels, closeTo(offset, .01));
          expect(_preview(tester), text);
          expect(tester.takeException(), isNull);
        }
        await _showControls(tester);
        expect(
          tester
              .widgetList<AppSwitchTile>(find.byType(AppSwitchTile))
              .map((v) => v.value),
          [true, false],
        );
        _generate(tester)!();
        await tester.pumpAndSettle();
        await _showPreview(tester);
        expect(
          _preview(tester),
          contains('X-WR-CALNAME:Duoyi · Anniversaries'),
        );
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'range changes clear preview and reject retained copy generate and range actions',
    (tester) async {
      final h = _Harness();
      final copies = <String>[];
      _clipboard(tester, (text) async {
        copies.add(text);
      });
      await h.mount(tester);
      try {
        final retainedGenerate = _generate(tester)!;
        retainedGenerate();
        await tester.pumpAndSettle();
        await _showPreview(tester);
        final retainedCopy = _copy(tester)!;
        await _showControls(tester);
        final retainedRange = tester
            .widgetList<AppSwitchTile>(find.byType(AppSwitchTile))
            .last
            .onChanged!;
        await _range(tester, 0, false);
        retainedGenerate();
        retainedRange(false);
        retainedCopy();
        await tester.pumpAndSettle();
        expect(_preview(tester), isNull);
        expect(copies, isEmpty);
        expect(
          tester
              .widgetList<AppSwitchTile>(find.byType(AppSwitchTile))
              .map((v) => v.value),
          [false, true],
        );
      } finally {
        await h.dispose(tester);
        _clipboard(tester, null);
      }
    },
  );

  for (final change in [
    'source',
    'external',
    'account',
    'session',
    'client',
    'cleaner',
    'blocked',
    'changing',
  ]) {
    testWidgets('$change invalidates private preview and old callbacks', (
      tester,
    ) async {
      final h = _Harness();
      final copies = <String>[];
      _clipboard(tester, (text) async {
        copies.add(text);
      });
      await h.mount(tester);
      try {
        final generate = _generate(tester)!;
        generate();
        await tester.pumpAndSettle();
        await _showPreview(tester);
        final copy = _copy(tester)!;
        switch (change) {
          case 'source':
            h.ann.rename();
          case 'external':
            h.cal.setExternalEvents([]);
          case 'account':
            h.auth.change(userId: 'B');
          case 'session':
            h.auth.change();
          case 'client':
            h.auth.replaceClient();
          case 'cleaner':
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          case 'blocked':
            h.auth.availability(blocked: true);
          case 'changing':
            h.auth.availability(changing: true);
        }
        // Invoke before the notification's next frame has run.
        generate();
        copy();
        await tester.pumpAndSettle();
        expect(_preview(tester), isNull);
        expect(copies, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.dispose(tester);
        _clipboard(tester, null);
      }
    });
  }

  for (final gate in ['route', 'lock', 'update', 'dispose']) {
    testWidgets('$gate rejects retained export and clipboard callbacks', (
      tester,
    ) async {
      final h = _Harness();
      final copies = <String>[];
      _clipboard(tester, (text) async {
        copies.add(text);
      });
      await h.mount(tester);
      try {
        final generate = _generate(tester)!;
        generate();
        await tester.pumpAndSettle();
        await _showPreview(tester);
        final copy = _copy(tester)!;
        if (gate == 'route') {
          h.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          );
        } else if (gate == 'lock') {
          h.lock.locked = true;
        } else if (gate == 'update') {
          h.update.requiredUpdate = true;
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        generate();
        copy();
        await tester.pumpAndSettle();
        expect(copies, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.dispose(tester);
        _clipboard(tester, null);
      }
    });
  }

  testWidgets('copy equals exact preview and feedback follows live locale', (
    tester,
  ) async {
    final h = _Harness();
    final copies = <String>[];
    _clipboard(tester, (text) async {
      copies.add(text);
    });
    await h.mount(tester);
    try {
      _generate(tester)!();
      await tester.pumpAndSettle();
      await _showPreview(tester);
      final text = _preview(tester)!;
      _copy(tester)!();
      await tester.pumpAndSettle();
      expect(copies, [text]);
      expect(find.text(I18n.tr('export.copy.done')), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.text(I18n.tr('export.copy.done')), findsOneWidget);
      expect(_preview(tester), text);
    } finally {
      await h.dispose(tester);
      _clipboard(tester, null);
    }
  });

  testWidgets('clipboard failure hides technical errors and offers retry', (
    tester,
  ) async {
    final h = _Harness();
    _clipboard(tester, (_) async {
      throw PlatformException(code: 'PRIVATE ERROR');
    });
    await h.mount(tester);
    try {
      _generate(tester)!();
      await tester.pumpAndSettle();
      await _showPreview(tester);
      _copy(tester)!();
      await tester.pumpAndSettle();
      expect(find.text('复制失败，请重试。'), findsOneWidget);
      expect(find.textContaining('PRIVATE ERROR'), findsNothing);
      expect(find.text(I18n.tr('export.copy.done')), findsNothing);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.text('Could not copy. Please try again.'), findsOneWidget);
      expect(_copy(tester), isNotNull);
    } finally {
      await h.dispose(tester);
      _clipboard(tester, null);
    }
  });

  for (final lateFailure in [false, true]) {
    testWidgets(
      'late clipboard ${lateFailure ? 'failure' : 'success'} cannot report after account change',
      (tester) async {
        final h = _Harness();
        late Completer<void> held;
        await tester.runAsync(() async {
          held = Completer<void>();
        });
        _clipboard(tester, (_) => held.future);
        await h.mount(tester);
        try {
          _generate(tester)!();
          await tester.pumpAndSettle();
          await _showPreview(tester);
          _copy(tester)!();
          await tester.pump();
          h.auth.change(userId: 'B');
          await tester.pump();
          if (lateFailure) {
            held.completeError(PlatformException(code: 'PRIVATE ERROR'));
          } else {
            held.complete();
          }
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
          expect(_preview(tester), isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await h.dispose(tester);
          _clipboard(tester, null);
        }
      },
    );
  }

  testWidgets(
    'CalDAV keeps full payload regardless of ICS range and rejects double push',
    (tester) async {
      final sync = _Sync();
      final h = _Harness(sync: sync);
      await h.mount(tester);
      try {
        await _range(tester, 0, false);
        await _range(tester, 1, false);
        final push = tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                I18n.tr('export.push_caldav'),
              ),
            )
            .onPressed!;
        push();
        push();
        await tester.pump();
        expect(sync.pushes, hasLength(1));
        expect(
          sync.pushes.single.any(
            (e) =>
                e.id == 'anniversary_birthday-A' &&
                e.displayMetadata is AnniversaryDisplayMetadata,
          ),
          isTrue,
        );
        expect(sync.pushes.single.any((e) => e.id == 'local-A'), isTrue);
        sync.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'large text export layouts fit Chinese English narrow and landscape',
    (tester) async {
      final capture =
          Platform.environment['DUOYI_CAPTURE_EXPORT_SCREENSHOTS'] == '1';
      if (capture) await tester.runAsync(loadWidgetPolishScreenshotFonts);
      for (final size in [const Size(320, 844), const Size(568, 320)]) {
        for (final locale in [AppLocale.zh, AppLocale.en]) {
          I18n.setLocale(locale);
          final h = _Harness(textScale: 1.6, screenshot: capture);
          await h.mount(tester, size: size);
          try {
            await _showControls(tester);
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('export_generate')))
                  .height,
              greaterThanOrEqualTo(44),
            );
            _generate(tester)!();
            await tester.pumpAndSettle();
            if (capture) {
              await _capture(
                tester,
                h.captureKey,
                'controls-${locale.name}-${size.width.toInt()}x${size.height.toInt()}',
              );
            }
            await _showPreview(tester);
            expect(_preview(tester), contains('SUMMARY:妈妈生日'));
            expect(tester.takeException(), isNull);
            if (capture) {
              await _capture(
                tester,
                h.captureKey,
                '${locale.name}-${size.width.toInt()}x${size.height.toInt()}',
              );
            }
          } finally {
            await h.dispose(tester);
          }
        }
      }
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage();
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final file = File('evidence/screenshots/export-20261016/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      img.dispose();
    }
  });
}

Finder _listScrollable() => find
    .descendant(
      of: find.byKey(const PageStorageKey('export_list')),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> _showControls(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('export_generate')),
    -160,
    scrollable: _listScrollable(),
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

Future<void> _showPreview(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(SelectableText),
    180,
    scrollable: _listScrollable(),
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

String? _preview(WidgetTester tester) =>
    find.byType(SelectableText).evaluate().isEmpty
    ? null
    : tester.widget<SelectableText>(find.byType(SelectableText)).data;
VoidCallback? _generate(WidgetTester tester) => tester
    .widget<FilledButton>(find.byKey(const ValueKey('export_generate')))
    .onPressed;
VoidCallback? _copy(WidgetTester tester) => tester
    .widget<TextButton>(find.byKey(const ValueKey('export_copy')))
    .onPressed;
Future<void> _range(WidgetTester tester, int index, bool value) async {
  // Drive the actual rendered tile callback; it may be outside the viewport.
  final tiles = tester
      .widgetList<AppSwitchTile>(find.byType(AppSwitchTile))
      .toList();
  tiles[index].onChanged!(value);
  await tester.pumpAndSettle();
}

void _clipboard(WidgetTester tester, Future<void> Function(String)? write) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    write == null
        ? null
        : (call) async {
            if (call.method == 'Clipboard.setData') {
              await write((call.arguments as Map)['text'] as String);
            }
            return null;
          },
  );
}

class _Anniversaries extends AnniversaryProvider {
  String title = '妈妈生日';
  @override
  List<Anniversary> get items => [
    Anniversary(
      id: 'birthday-A',
      title: title,
      originDate: DateTime(2000, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      type: AnniversaryType.birthday,
      description: '原始描述',
    ),
  ];
  void rename() {
    title = '改名原文';
    notifyListeners();
  }
}

class _Auth extends AuthProvider {
  _Auth()
    : _client = ApiClient(baseUrl: 'https://duoyi.test', token: 'token-A'),
      super(
        client: ApiClient(baseUrl: 'https://duoyi.test'),
        initialState: const AuthState(
          userId: 'A',
          username: 'A',
          token: 'token-A',
        ),
      );
  ApiClient _client;
  AuthState _state = const AuthState(
    userId: 'A',
    username: 'A',
    token: 'token-A',
  );
  int _session = 1;
  bool _changing = false, _blocked = false;
  @override
  ApiClient get client => _client;
  @override
  AuthState get state => _state;
  @override
  int get sessionGeneration => _session;
  @override
  bool get isAccountTransitionInProgress => _changing;
  @override
  bool get isLocalAccountDataBlocked => _blocked;
  void change({String userId = 'A'}) {
    _session++;
    _state = AuthState(
      userId: userId,
      username: userId,
      token: 'token-$userId-$_session',
    );
    notifyListeners();
  }

  void replaceClient() {
    _client = ApiClient(
      baseUrl: 'https://other.duoyi.test',
      token: 'new-token',
    );
    notifyListeners();
  }

  void availability({bool changing = false, bool blocked = false}) {
    _changing = changing;
    _blocked = blocked;
    notifyListeners();
  }
}

class _Lock extends AppLockProvider {
  bool locked = false;
  @override
  bool get isLocked => locked;
}

class _Update extends AppUpdateService {
  _Update() : super(repo: 'duoyi/duoyi', currentVersion: '1.0.0');
  bool requiredUpdate = false;
  @override
  bool get mustUpdate => requiredUpdate;
}

class _Sync extends CalendarSyncProvider {
  final List<List<CalendarEvent>> pushes = [];
  Completer<int>? _held;
  @override
  CalDavWriteTarget? get writeTarget => _target;
  final _target = const CalDavWriteTarget(
    collectionUrl: 'https://caldav.test/calendar/',
    authorizationHeader: 'Basic synthetic',
  );
  @override
  Future<int> pushEventsToCalDav(
    Iterable<CalendarEvent> events, {
    bool Function()? isCurrent,
  }) {
    pushes.add(events.toList());
    _held = Completer<int>();
    return _held!.future;
  }

  void complete() {
    _held!.complete(pushes.single.length);
  }
}

class _Harness {
  _Harness({
    CalendarSyncProvider? sync,
    this.textScale = 1,
    this.screenshot = false,
  }) : sync = sync ?? CalendarSyncProvider();
  final ann = _Anniversaries();
  final cal = CalendarProvider();
  final auth = _Auth();
  final lock = _Lock();
  final update = _Update();
  final theme = ThemeProvider();
  final todo = TodoProvider();
  final habit = HabitProvider();
  final focus = PomodoroProvider();
  final course = CourseProvider();
  final diary = DiaryProvider();
  final countdown = CountdownProvider();
  final goal = GoalProvider();
  final CalendarSyncProvider sync;
  final double textScale;
  final bool screenshot;
  final navigator = GlobalKey<NavigatorState>();
  final captureKey = GlobalKey();
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    // Load a real persisted local event and independent imported anniversary.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duoyi_local_calendar_events_v1', [
      jsonEncode(
        CalendarEvent(
          id: 'local-A',
          title: 'Local original',
          date: DateTime(2099, 1, 1),
          type: CalendarEventType.event,
          color: Colors.blue,
        ).toJson(),
      ),
    ]);
    await cal.loadFromStorage();
    cal.setExternalEvents([
      CalendarEvent(
        id: 'external-anniversary',
        title: 'External anniversary',
        date: DateTime(2099, 1, 1),
        type: CalendarEventType.anniversary,
        color: Colors.pink,
      ),
      CalendarEvent(
        id: 'anniversary_birthday-A',
        sourceId: 'birthday-A',
        title: 'External original',
        date: DateTime(2099, 1, 1),
        type: CalendarEventType.anniversary,
        color: Colors.pink,
      ),
    ]);
    var appTheme = theme.brand.theme;
    if (screenshot) {
      appTheme = appTheme.copyWith(
        textTheme: appTheme.textTheme.apply(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: ['DuoyiScreenshot'],
        ),
        primaryTextTheme: appTheme.primaryTextTheme.apply(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: ['DuoyiScreenshot'],
        ),
      );
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AppUpdateService>.value(value: update),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AnniversaryProvider>.value(value: ann),
          ChangeNotifierProvider<CalendarProvider>.value(value: cal),
          ChangeNotifierProvider<TodoProvider>.value(value: todo),
          ChangeNotifierProvider<HabitProvider>.value(value: habit),
          ChangeNotifierProvider<PomodoroProvider>.value(value: focus),
          ChangeNotifierProvider<CourseProvider>.value(value: course),
          ChangeNotifierProvider<DiaryProvider>.value(value: diary),
          ChangeNotifierProvider<CountdownProvider>.value(value: countdown),
          ChangeNotifierProvider<GoalProvider>.value(value: goal),
          ChangeNotifierProvider<CalendarSyncProvider>.value(value: sync),
        ],
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            navigatorKey: navigator,
            debugShowCheckedModeBanner: false,
            theme: appTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const BrandRouteSurface(child: ExportScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final p in [
      ann,
      cal,
      auth,
      lock,
      update,
      theme,
      todo,
      habit,
      focus,
      course,
      diary,
      countdown,
      goal,
      sync,
    ]) {
      p.dispose();
    }
    tester.view.reset();
  }
}
