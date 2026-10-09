import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:duoyi/widgets/surface_components.dart';

void main() {
  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  testWidgets(
    'date picker keeps selection, viewed month, mode, and ignore-year state across locale changes',
    (tester) async {
      Future<AppDatePickerResult?>? resultFuture;
      var completionCount = 0;
      await _pumpHost(tester, (context) {
        resultFuture =
            AppDatePicker.show(
              context,
              initialDate: DateTime(2026, 5, 17),
              firstDate: DateTime(2026, 1, 1),
              lastDate: DateTime(2026, 12, 31),
              title: 'Literal date title',
              subtitle: 'Literal date subtitle',
              allowIgnoreYear: true,
            ).then((value) {
              completionCount++;
              return value;
            });
      });

      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(_headerText('Literal date title'), findsOneWidget);
      expect(_headerText('Literal date subtitle'), findsOneWidget);

      final selectedDay = find.byKey(const ValueKey('solar-day-2026-05-19'));
      await tester.ensureVisible(selectedDay);
      await tester.tap(selectedDay);
      await tester.pumpAndSettle();
      expect(
        find.text(I18nDateFormat.date(DateTime(2026, 5, 19))),
        findsOneWidget,
      );

      final nextMonth = find.byTooltip('下个月');
      await tester.ensureVisible(nextMonth);
      await tester.tap(nextMonth);
      await tester.pumpAndSettle();
      expect(find.text('2026年6月'), findsOneWidget);

      final lunarSegment = find.text(I18n.tr('calendar.lunar'));
      await tester.ensureVisible(lunarSegment);
      await tester.tap(lunarSegment);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      _expectDatePickerState(
        tester,
        mode: AppDatePickerMode.lunar,
        ignoreYear: true,
        date: DateTime(2026, 5, 19),
      );

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(completionCount, 0);
      expect(_headerText('Literal date title'), findsOneWidget);
      expect(_headerText('Literal date subtitle'), findsOneWidget);
      expect(find.text(I18n.tr('calendar.solar')), findsOneWidget);
      expect(find.text(I18n.tr('calendar.lunar')), findsOneWidget);
      expect(find.textContaining(RegExp(r'[\u3400-\u9fff]')), findsNothing);
      expect(
        AppDatePickerResult(
          date: DateTime(2026, 5, 19),
          mode: AppDatePickerMode.lunar,
          ignoreYear: true,
        ).lunarText,
        contains('Bing-Wu'),
      );
      _expectDatePickerState(
        tester,
        mode: AppDatePickerMode.lunar,
        ignoreYear: true,
        date: DateTime(2026, 5, 19),
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(completionCount, 0);
      expect(_headerText('Literal date title'), findsOneWidget);
      expect(_headerText('Literal date subtitle'), findsOneWidget);
      _expectDatePickerState(
        tester,
        mode: AppDatePickerMode.lunar,
        ignoreYear: true,
        date: DateTime(2026, 5, 19),
      );

      final solarSegment = find.text(I18n.tr('calendar.solar'));
      await tester.ensureVisible(solarSegment);
      await tester.tap(solarSegment);
      await tester.pumpAndSettle();
      expect(find.text('2026年6月'), findsOneWidget);
      expect(
        find.text(I18nDateFormat.date(DateTime(2026, 5, 19))),
        findsOneWidget,
      );

      await tester.ensureVisible(lunarSegment);
      await tester.tap(lunarSegment);
      await tester.pumpAndSettle();
      final confirm = find.text(I18n.tr('action.confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final result = await resultFuture!;
      expect(result, isNotNull);
      expect(result!.date, DateTime(2026, 5, 19));
      expect(result.mode, AppDatePickerMode.lunar);
      expect(result.ignoreYear, isTrue);
      expect(completionCount, 1);
    },
  );

  testWidgets('date picker resolves semantic title and subtitle keys live', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (context) => AppDatePicker.show(
        context,
        initialDate: DateTime(2026, 5, 17),
        titleKey: 'calendar.solar',
        subtitleKey: 'calendar.lunar',
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(_headerText(I18n.tr('calendar.solar')), findsOneWidget);
    expect(_headerText(I18n.tr('calendar.lunar')), findsOneWidget);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(_headerText(I18n.tr('calendar.solar')), findsOneWidget);
    expect(_headerText(I18n.tr('calendar.lunar')), findsOneWidget);
    expect(_headerText('公历'), findsNothing);
    expect(_headerText('农历'), findsNothing);

    final cancel = find.text(I18n.tr('action.cancel'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
  });

  testWidgets('time picker resolves semantic title and subtitle keys live', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (context) => AppTimePicker.show(
        context,
        initialTime: const TimeOfDay(hour: 9, minute: 15),
        titleKey: 'calendar.solar',
        subtitleKey: 'calendar.lunar',
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(_headerText(I18n.tr('calendar.solar')), findsOneWidget);
    expect(_headerText(I18n.tr('calendar.lunar')), findsOneWidget);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(_headerText(I18n.tr('calendar.solar')), findsOneWidget);
    expect(_headerText(I18n.tr('calendar.lunar')), findsOneWidget);
    expect(_headerText('公历'), findsNothing);
    expect(_headerText('农历'), findsNothing);

    final cancel = find.text(I18n.tr('action.cancel'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'time picker keeps wheel controllers and rounded selection across locale changes',
    (tester) async {
      Future<TimeOfDay?>? resultFuture;
      await _pumpHost(
        tester,
        (context) => resultFuture = AppTimePicker.show(
          context,
          initialTime: const TimeOfDay(hour: 9, minute: 13),
          minuteStep: 5,
          title: 'Literal time title',
          subtitle: 'Literal time subtitle',
        ),
      );

      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(
        find.text(AppTimePicker.format(const TimeOfDay(hour: 9, minute: 15))),
        findsOneWidget,
      );
      expect(_headerText('Literal time title'), findsOneWidget);
      expect(_headerText('Literal time subtitle'), findsOneWidget);

      final wheels = _timeWheels(tester);
      final hourController =
          wheels[0].controller! as FixedExtentScrollController;
      final minuteController =
          wheels[1].controller! as FixedExtentScrollController;
      expect(hourController.selectedItem, 9);
      expect(minuteController.selectedItem, 3);

      final eveningPreset = find.text('晚上 20:00');
      await tester.ensureVisible(eveningPreset);
      await tester.tap(eveningPreset);
      await tester.pumpAndSettle();
      expect(hourController.selectedItem, 20);
      expect(minuteController.selectedItem, 0);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(_headerText('Literal time title'), findsOneWidget);
      expect(_headerText('Literal time subtitle'), findsOneWidget);
      expect(
        _selectedTimeText(
          AppTimePicker.format(const TimeOfDay(hour: 20, minute: 0)),
        ),
        findsOneWidget,
      );

      final englishWheels = _timeWheels(tester);
      expect(identical(englishWheels[0].controller, hourController), isTrue);
      expect(identical(englishWheels[1].controller, minuteController), isTrue);
      expect(hourController.selectedItem, 20);
      expect(minuteController.selectedItem, 0);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      final chineseWheels = _timeWheels(tester);
      expect(identical(chineseWheels[0].controller, hourController), isTrue);
      expect(identical(chineseWheels[1].controller, minuteController), isTrue);
      expect(hourController.selectedItem, 20);
      expect(minuteController.selectedItem, 0);

      final confirm = find.text(I18n.tr('action.confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(await resultFuture, const TimeOfDay(hour: 20, minute: 0));
    },
  );

  testWidgets(
    'cancel returns null and disposed pickers release locale listeners',
    (tester) async {
      Future<AppDatePickerResult?>? dateResult;
      await _pumpHost(
        tester,
        (context) => dateResult = AppDatePicker.show(
          context,
          initialDate: DateTime(2026, 5, 17),
        ),
      );

      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      final dateCancel = find.text(I18n.tr('action.cancel'));
      await tester.ensureVisible(dateCancel);
      await tester.tap(dateCancel);
      await tester.pumpAndSettle();
      expect(await dateResult, isNull);

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.takeException(), isNull);

      Future<TimeOfDay?>? timeResult;
      await _pumpHost(
        tester,
        (context) => timeResult = AppTimePicker.show(
          context,
          initialTime: const TimeOfDay(hour: 9, minute: 15),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      final timeCancel = find.text(I18n.tr('action.cancel'));
      await tester.ensureVisible(timeCancel);
      await tester.tap(timeCancel);
      await tester.pumpAndSettle();
      expect(await timeResult, isNull);

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpHost(
  WidgetTester tester,
  void Function(BuildContext context) openPicker,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2563EB),
          primaryContainer: Color(0xFFDCE8FF),
          onPrimary: Colors.white,
          onSurface: Color(0xFF111827),
          onSurfaceVariant: Color(0xFF6B7280),
          surface: Colors.white,
          outlineVariant: Color(0xFFE5E7EB),
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openPicker(context),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _headerText(String text) => find.descendant(
  of: find.byType(AppSectionHeader),
  matching: find.text(text),
);

Finder _selectedTimeText(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.header == true &&
        widget.properties.label == text,
  ),
  matching: find.text(text),
);

List<ListWheelScrollView> _timeWheels(WidgetTester tester) => tester
    .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
    .toList();

void _expectDatePickerState(
  WidgetTester tester, {
  required AppDatePickerMode mode,
  required bool ignoreYear,
  required DateTime date,
}) {
  final picker = tester.widget<SegmentedButton<AppDatePickerMode>>(
    find.byType(SegmentedButton<AppDatePickerMode>),
  );
  expect(picker.selected, {mode});
  expect(
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
    ignoreYear,
  );
  expect(find.text(I18nDateFormat.date(date)), findsOneWidget);
}
