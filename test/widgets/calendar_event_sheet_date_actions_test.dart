import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/date_item_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _countdownId = 'calendar-action-countdown';
const _anniversaryId = 'calendar-action-anniversary';
const _countdownStorageKey = 'duoyi_countdowns';
const _countdownPlatformKey = 'flutter.duoyi_countdowns';
const _anniversaryStorageKey = 'duoyi_anniversaries_v2';
const _anniversaryPlatformKey = 'flutter.duoyi_anniversaries_v2';
final _originalDate = DateTime(2026, 5, 18);

late _Store _store;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _store = _Store();
    SharedPreferencesStorePlatform.instance = _store;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() async {
    _store.releaseAll();
    await AccountPreferenceWrites.drain();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'countdown and anniversary rescheduling persist the confirmed date while the picker reverses',
    (tester) async {
      final fixture = await _pumpFixture(tester);
      _store.holdNext(_countdownPlatformKey);

      await _openSheet(tester, 'open_countdown_sheet');
      await _selectDate(tester, DateTime(2026, 5, 21));
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pump(const Duration(milliseconds: 1));

      await _store.heldWriteStarted.timeout(const Duration(seconds: 2));
      expect(find.text('调整日期'), findsOneWidget);
      expect(_store.writeCount(_countdownPlatformKey), 1);

      // Keep the write pending until after the picker's reverse animation has
      // begun. Confirmation must already have reached the provider write path.
      _store.releaseAll();
      await _pumpUntil(
        tester,
        () => fixture.countdownDate() == DateTime(2026, 5, 21),
      );
      expect(fixture.countdownDate(), DateTime(2026, 5, 21));
      expect(find.text('调整日期'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(
        _storedDate(fixture.preferences, _countdownStorageKey, 'targetDate'),
        DateTime(2026, 5, 21),
      );
      expect(find.text('Countdown for calendar sheet'), findsNothing);

      await _openSheet(tester, 'open_anniversary_sheet');
      await _selectDate(tester, DateTime(2026, 5, 22));
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();

      expect(fixture.anniversaryDate(), DateTime(2026, 5, 22));
      expect(
        _storedDate(fixture.preferences, _anniversaryStorageKey, 'originDate'),
        DateTime(2026, 5, 22),
      );
      expect(find.text('Anniversary for calendar sheet'), findsNothing);
    },
  );

  testWidgets(
    'false and throwing reschedule writes retain the date for Retry',
    (tester) async {
      final fixture = await _pumpFixture(tester);
      final failures = <({DateTime target, bool throws})>[
        (target: DateTime(2026, 5, 19), throws: false),
        (target: DateTime(2026, 5, 20), throws: true),
      ];
      final dateActions =
          <
            ({
              String openKey,
              String platformKey,
              String storageKey,
              String dateField,
              String title,
              DateTime Function() date,
            })
          >[
            (
              openKey: 'open_countdown_sheet',
              platformKey: _countdownPlatformKey,
              storageKey: _countdownStorageKey,
              dateField: 'targetDate',
              title: 'Countdown for calendar sheet',
              date: fixture.countdownDate,
            ),
            (
              openKey: 'open_anniversary_sheet',
              platformKey: _anniversaryPlatformKey,
              storageKey: _anniversaryStorageKey,
              dateField: 'originDate',
              title: 'Anniversary for calendar sheet',
              date: fixture.anniversaryDate,
            ),
          ];

      for (final action in dateActions) {
        for (final failure in failures) {
          final confirmedDate = action.date();
          await _openSheet(tester, action.openKey);
          await _selectDate(tester, failure.target);
          _store.rejectNext(action.platformKey, throws: failure.throws);
          await tester.tap(find.widgetWithText(FilledButton, '确定'));
          await _pumpUntil(
            tester,
            () => find.text(DateItemUiCopy.saveFailed).evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();

          expect(action.date(), confirmedDate);
          expect(
            _storedDate(
              fixture.preferences,
              action.storageKey,
              action.dateField,
            ),
            confirmedDate,
          );
          expect(find.text(action.title), findsOneWidget);
          expect(find.text(DateItemUiCopy.saveFailed), findsOneWidget);
          expect(find.text(I18n.tr('action.retry')), findsOneWidget);

          final retry = find.text(I18n.tr('action.retry'));
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await _pumpUntil(tester, () => action.date() == failure.target);
          await tester.pumpAndSettle();

          expect(action.date(), failure.target);
          expect(
            _storedDate(
              fixture.preferences,
              action.storageKey,
              action.dateField,
            ),
            failure.target,
          );
          expect(find.text(action.title), findsNothing);
        }
      }
    },
  );

  testWidgets('a rejected countdown delete keeps the calendar sheet open', (
    tester,
  ) async {
    final fixture = await _pumpFixture(tester);
    await _openSheet(tester, 'open_countdown_sheet');
    _store.rejectNext(_countdownPlatformKey, throws: false);

    await tester.tap(find.text('删除'));
    await _pumpUntil(
      tester,
      () => find.text(DateItemUiCopy.deleteFailed).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(fixture.countdownDate(), _originalDate);
    expect(
      _storedDate(fixture.preferences, _countdownStorageKey, 'targetDate'),
      _originalDate,
    );
    expect(find.text('Countdown for calendar sheet'), findsOneWidget);
    expect(find.text(DateItemUiCopy.deleteFailed), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets(
    'retained edit and detail actions do not pop a route covering the sheet',
    (tester) async {
      final fixture = await _pumpFixture(tester);
      await _openSheet(tester, 'open_countdown_sheet');

      final edit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '编辑'))
          .onPressed!;
      await _pushCoverRoute(fixture, tester, 'Cover route for edit');
      edit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cover route for edit'), findsOneWidget);

      Navigator.of(fixture.launchContext).pop();
      await tester.pumpAndSettle();
      expect(find.text('Countdown for calendar sheet'), findsOneWidget);
      final openDetails = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '跳转详情'))
          .onPressed!;
      await _pushCoverRoute(fixture, tester, 'Cover route for details');
      openDetails();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cover route for details'), findsOneWidget);

      Navigator.of(fixture.launchContext).pop();
      await tester.pumpAndSettle();
      expect(find.text('Countdown for calendar sheet'), findsOneWidget);
    },
  );
}

Future<_Fixture> _pumpFixture(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final preferences = await SharedPreferences.getInstance();
  await preferences.setStringList(_countdownStorageKey, [
    jsonEncode(
      CountdownItem(
        id: _countdownId,
        title: 'Countdown for calendar sheet',
        targetDate: _originalDate,
      ).toJson(),
    ),
  ]);
  await preferences.setStringList(_anniversaryStorageKey, [
    jsonEncode(
      Anniversary(
        id: _anniversaryId,
        title: 'Anniversary for calendar sheet',
        originDate: _originalDate,
        type: AnniversaryType.memorial,
      ).toJson(),
    ),
  ]);

  final countdowns = CountdownProvider();
  final anniversaries = AnniversaryProvider();
  await countdowns.loadFromStorage();
  await anniversaries.loadFromStorage();
  late BuildContext launchContext;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CountdownProvider>.value(value: countdowns),
        ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversaries),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              launchContext = context;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: const ValueKey('open_countdown_sheet'),
                      onPressed: () =>
                          showCalendarEventSheet(context, _countdownEvent()),
                      child: const Text('Open countdown'),
                    ),
                    TextButton(
                      key: const ValueKey('open_anniversary_sheet'),
                      onPressed: () =>
                          showCalendarEventSheet(context, _anniversaryEvent()),
                      child: const Text('Open anniversary'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  _store.resetWrites();

  addTearDown(() async {
    _store.releaseAll();
    await AccountPreferenceWrites.drain();
    await tester.pumpWidget(const SizedBox.shrink());
    countdowns.dispose();
    anniversaries.dispose();
  });

  return _Fixture(
    preferences: preferences,
    countdowns: countdowns,
    anniversaries: anniversaries,
    launchContext: launchContext,
  );
}

CalendarEvent _countdownEvent() => CalendarEvent(
  id: 'countdown_$_countdownId',
  sourceId: _countdownId,
  title: 'Countdown for calendar sheet',
  date: _originalDate,
  type: CalendarEventType.countdown,
  color: Colors.deepOrange,
);

CalendarEvent _anniversaryEvent() => CalendarEvent(
  id: 'anniversary_$_anniversaryId',
  sourceId: _anniversaryId,
  title: 'Anniversary for calendar sheet',
  date: _originalDate,
  type: CalendarEventType.anniversary,
  color: Colors.pink,
);

Future<void> _openSheet(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pumpAndSettle();
  expect(find.text('改期'), findsOneWidget);
}

Future<void> _selectDate(WidgetTester tester, DateTime date) async {
  await tester.tap(find.text('改期'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'solar-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pushCoverRoute(
  _Fixture fixture,
  WidgetTester tester,
  String label,
) async {
  unawaited(
    Navigator.of(fixture.launchContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: Center(child: Text(label))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(label), findsOneWidget);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

DateTime _storedDate(
  SharedPreferences preferences,
  String storageKey,
  String dateField,
) {
  final row =
      jsonDecode(preferences.getStringList(storageKey)!.single)
          as Map<String, dynamic>;
  return DateTime.parse(row[dateField] as String);
}

class _Fixture {
  const _Fixture({
    required this.preferences,
    required this.countdowns,
    required this.anniversaries,
    required this.launchContext,
  });

  final SharedPreferences preferences;
  final CountdownProvider countdowns;
  final AnniversaryProvider anniversaries;
  final BuildContext launchContext;

  DateTime countdownDate() => countdowns.items
      .singleWhere((item) => item.id == _countdownId)
      .targetDate;

  DateTime anniversaryDate() => anniversaries.items
      .singleWhere((item) => item.id == _anniversaryId)
      .originDate;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  final Map<String, int> _writes = <String, int>{};
  String? _rejectKey;
  bool _throwOnRejection = false;
  String? _heldKey;
  Completer<void>? _heldWriteStarted;
  Completer<void>? _heldWriteRelease;

  Future<void> get heldWriteStarted => _heldWriteStarted!.future;

  int writeCount(String key) => _writes[key] ?? 0;

  void resetWrites() => _writes.clear();

  void rejectNext(String key, {required bool throws}) {
    _rejectKey = key;
    _throwOnRejection = throws;
  }

  void holdNext(String key) {
    _heldKey = key;
    _heldWriteStarted = Completer<void>();
    _heldWriteRelease = Completer<void>();
  }

  void releaseAll() {
    final release = _heldWriteRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    _writes.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (_heldKey == key) {
      _heldKey = null;
      _heldWriteStarted!.complete();
      await _heldWriteRelease!.future;
    }

    // Simulate a platform that applies the value before rejecting the result.
    final saved = await super.setValue(type, key, value);
    if (_rejectKey == key) {
      final shouldThrow = _throwOnRejection;
      _rejectKey = null;
      _throwOnRejection = false;
      if (shouldThrow) throw StateError('injected platform write failure');
      return false;
    }
    return saved;
  }
}
