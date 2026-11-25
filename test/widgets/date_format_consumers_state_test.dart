import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/calendar_month_grid.dart';
import 'package:duoyi/widgets/calendar_week_strip.dart';
import 'package:duoyi/widgets/habit_date_range_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

const _phoneSize = Size(390, 844);
const _datePatterns = <String>[
  'yyyy-MM-dd',
  'MM/dd/yyyy',
  'dd/MM/yyyy',
  'yyyy年M月d日',
];
const _formattedMay15 = <String, String>{
  'yyyy-MM-dd': '2026-05-15',
  'MM/dd/yyyy': '05/15/2026',
  'dd/MM/yyyy': '15/05/2026',
  'yyyy年M月d日': '2026年5月15日',
};
const _formattedMay19 = <String, String>{
  'yyyy-MM-dd': '2026-05-19',
  'MM/dd/yyyy': '05/19/2026',
  'dd/MM/yyyy': '19/05/2026',
  'yyyy年M月d日': '2026年5月19日',
};
const _formattedMay17 = <String, String>{
  'yyyy-MM-dd': '2026-05-17',
  'MM/dd/yyyy': '05/17/2026',
  'dd/MM/yyyy': '17/05/2026',
  'yyyy年M月d日': '2026年5月17日',
};
const _captureEnvKey = 'DUOYI_CAPTURE_DATE_SETTINGS_SCREENSHOTS';

bool get _captureScreenshots => Platform.environment[_captureEnvKey] == '1';

Future<PreferencesProvider> _createPreferences(
  WidgetTester tester, {
  String dateFormat = 'yyyy-MM-dd',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  late PreferencesProvider preferences;
  await tester.runAsync(() async {
    preferences = PreferencesProvider();
    await preferences.loadFromStorage();
    await preferences.setDateFormat(dateFormat);
  });
  addTearDown(preferences.dispose);
  return preferences;
}

Future<void> _setDateFormat(
  WidgetTester tester,
  PreferencesProvider preferences,
  String pattern,
) async {
  await tester.runAsync(() => preferences.setDateFormat(pattern));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _setPhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_phoneSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _loadScreenshotFontsIfRequested(WidgetTester tester) async {
  if (_captureScreenshots) {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
  }
}

ThemeData _themeForCurrentFixture() => widgetPolishScreenshotTheme();

Widget _preferencesApp(
  PreferencesProvider preferences, {
  required Widget home,
  required GlobalKey captureKey,
}) {
  return RepaintBoundary(
    key: captureKey,
    child: ChangeNotifierProvider<PreferencesProvider>.value(
      value: preferences,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _themeForCurrentFixture(),
        home: home,
      ),
    ),
  );
}

Widget _habitRangeHome() {
  return Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: HabitDateRangeFields(
          startDate: DateTime(2026, 5, 15),
          endDate: DateTime(2026, 5, 19),
          onStartChanged: (_) {},
          onEndChanged: (_) {},
        ),
      ),
    ),
  );
}

class _PickerHost extends StatelessWidget {
  final ValueChanged<Future<AppDatePickerResult?>?> onOpened;

  const _PickerHost({required this.onOpened});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => onOpened(
              AppDatePicker.show(
                context,
                initialDate: DateTime(2026, 5, 17),
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime(2026, 12, 31),
                title: 'Date format fixture',
              ),
            ),
            child: const Text('Open picker'),
          ),
        ),
      ),
    );
  }
}

Widget _calendarSemanticsHome(CalendarProvider calendarProvider) {
  final selectedDay = DateTime(2026, 5, 15);
  return Scaffold(
    body: Column(
      children: [
        SizedBox(
          height: 360,
          child: CalendarMonthGrid(
            focusedMonth: DateTime(2026, 5),
            selectedDay: selectedDay,
            dateEventTypes: const <String, List<CalendarEventType>>{},
            showLunar: false,
            onDaySelected: (_) {},
          ),
        ),
        Expanded(
          child: CalendarWeekStrip(
            selectedDay: selectedDay,
            dateEventTypes: const <String, List<CalendarEventType>>{},
            calendarProvider: calendarProvider,
            onDaySelected: (_) {},
          ),
        ),
      ],
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey captureKey,
  String name,
) async {
  if (!_captureScreenshots) return;
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/date-settings-20261014/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

List<Semantics> _selectedDateSemantics(
  WidgetTester tester,
  Finder scope,
  String formattedDate,
) {
  return tester
      .widgetList<Semantics>(
        find.descendant(of: scope, matching: find.byType(Semantics)),
      )
      .where(
        (node) =>
            node.properties.selected == true &&
            (node.properties.label?.contains(formattedDate) ?? false),
      )
      .toList();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    testWidgets(
      '${locale.name} HabitDateRangeFields refreshes for all saved patterns',
      (tester) async {
        I18n.setLocale(locale);
        await _setPhoneSurface(tester);
        await _loadScreenshotFontsIfRequested(tester);
        final preferences = await _createPreferences(tester);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          _preferencesApp(
            preferences,
            home: _habitRangeHome(),
            captureKey: captureKey,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(HabitDateRangeFields)).height,
          lessThan(220),
        );
        for (final pattern in _datePatterns) {
          await _setDateFormat(tester, preferences, pattern);
          expect(find.text(_formattedMay15[pattern]!), findsOneWidget);
          expect(find.text(_formattedMay19[pattern]!), findsOneWidget);
        }
        await _capture(tester, captureKey, 'habit-range-${locale.name}');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('${locale.name} open date picker reformats solar preview '
        'without changing selection', (tester) async {
      I18n.setLocale(locale);
      await _setPhoneSurface(tester);
      await _loadScreenshotFontsIfRequested(tester);
      final preferences = await _createPreferences(
        tester,
        dateFormat: 'MM/dd/yyyy',
      );
      final captureKey = GlobalKey();
      Future<AppDatePickerResult?>? resultFuture;
      await tester.pumpWidget(
        _preferencesApp(
          preferences,
          home: _PickerHost(onOpened: (result) => resultFuture = result),
          captureKey: captureKey,
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();

      expect(find.text(_formattedMay17['MM/dd/yyyy']!), findsOneWidget);
      final selectedDay = find.byKey(const ValueKey('solar-day-2026-05-19'));
      await tester.ensureVisible(selectedDay);
      await tester.tap(selectedDay);
      await tester.pumpAndSettle();
      expect(find.text('05/19/2026'), findsOneWidget);

      await _capture(tester, captureKey, 'picker-${locale.name}');
      await _setDateFormat(tester, preferences, 'dd/MM/yyyy');
      expect(find.text('19/05/2026'), findsOneWidget);
      expect(find.text(_formattedMay17['MM/dd/yyyy']!), findsNothing);

      await tester.ensureVisible(selectedDay);
      final selectedSemantics = tester.widget<Semantics>(
        find.ancestor(of: selectedDay, matching: find.byType(Semantics)).first,
      );
      expect(selectedSemantics.properties.selected, isTrue);
      final originalDay = find.byKey(const ValueKey('solar-day-2026-05-17'));
      final originalSemantics = tester.widget<Semantics>(
        find.ancestor(of: originalDay, matching: find.byType(Semantics)).first,
      );
      expect(originalSemantics.properties.selected, isFalse);

      final confirm = find.text(I18n.tr('action.confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.date, DateTime(2026, 5, 19));
      expect(result.mode, AppDatePickerMode.solar);
      expect(result.ignoreYear, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'account reset and A-B-A format changes preserve the open picker date',
    (tester) async {
      I18n.setLocale(AppLocale.zh);
      await _setPhoneSurface(tester);
      final preferences = await _createPreferences(
        tester,
        dateFormat: 'MM/dd/yyyy',
      );
      final captureKey = GlobalKey();
      Future<AppDatePickerResult?>? resultFuture;
      await tester.pumpWidget(
        _preferencesApp(
          preferences,
          home: _PickerHost(onOpened: (result) => resultFuture = result),
          captureKey: captureKey,
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      final selectedDay = find.byKey(const ValueKey('solar-day-2026-05-19'));
      await tester.ensureVisible(selectedDay);
      await tester.tap(selectedDay);
      await tester.pumpAndSettle();
      expect(find.text('05/19/2026'), findsOneWidget);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      preferences.resetLocalState();
      await tester.pumpAndSettle();
      expect(find.text(_formattedMay19['yyyy-MM-dd']!), findsOneWidget);
      expect(find.text(_formattedMay17['MM/dd/yyyy']!), findsNothing);

      await _setDateFormat(tester, preferences, 'MM/dd/yyyy');
      expect(find.text('05/19/2026'), findsOneWidget);
      await _setDateFormat(tester, preferences, 'yyyy-MM-dd');
      expect(find.text(_formattedMay19['yyyy-MM-dd']!), findsOneWidget);

      await tester.ensureVisible(selectedDay);
      final selectedSemantics = tester.widget<Semantics>(
        find.ancestor(of: selectedDay, matching: find.byType(Semantics)).first,
      );
      expect(selectedSemantics.properties.selected, isTrue);
      await tester.ensureVisible(find.text(I18n.tr('action.confirm')));
      await tester.tap(find.text(I18n.tr('action.confirm')));
      await tester.pumpAndSettle();
      final result = await resultFuture;
      expect(result?.date, DateTime(2026, 5, 19));
      expect(result?.mode, AppDatePickerMode.solar);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in AppLocale.values) {
    testWidgets(
      '${locale.name} month grid and week strip semantics follow the saved '
      'date pattern',
      (tester) async {
        I18n.setLocale(locale);
        await _setPhoneSurface(tester);
        final preferences = await _createPreferences(tester);
        final calendar = CalendarProvider();
        addTearDown(calendar.dispose);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
              ChangeNotifierProvider(create: (_) => CourseProvider()),
              ChangeNotifierProvider(create: (_) => DiaryProvider()),
              ChangeNotifierProvider(create: (_) => TodoProvider()),
            ],
            child: _preferencesApp(
              preferences,
              home: _calendarSemanticsHome(calendar),
              captureKey: captureKey,
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final pattern in _datePatterns) {
          await _setDateFormat(tester, preferences, pattern);
          expect(
            _selectedDateSemantics(
              tester,
              find.byType(CalendarMonthGrid),
              _formattedMay15[pattern]!,
            ),
            hasLength(1),
            reason:
                'The month grid should announce the selected civil day '
                'using $pattern.',
          );
          expect(
            _selectedDateSemantics(
              tester,
              find.byType(CalendarWeekStrip),
              _formattedMay15[pattern]!,
            ),
            hasLength(1),
            reason:
                'The week strip should announce the selected civil day '
                'using $pattern.',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
