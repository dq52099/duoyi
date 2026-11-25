import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/time_audit_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'all four time entry pickers translate live while retaining selection and State',
    (tester) async {
      final fixture = await _mountEditor(tester);
      final screenState = tester.state(
        find.byType(TimeAuditScreen, skipOffstage: false),
      );
      final editorState = tester.state(_privateWidget('_TimeEntrySheet'));
      final titleController = tester
          .widget<TextField>(_textField('time_audit.field.title'))
          .controller!;
      titleController.text = 'Literal 混合 picker draft';

      final originalStart = _endpointSubtitle(tester, _Endpoint.start);
      final originalEnd = _endpointSubtitle(tester, _Endpoint.end);
      await tester.tap(_endpointTile(_Endpoint.start));
      await tester.pumpAndSettle();
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
      }
      await _cancelPicker(tester, _Endpoint.start.dateTitleKey);
      for (final endpoint in _Endpoint.values) {
        expect(
          tester.widget<ListTile>(_endpointTile(endpoint)).onTap,
          isNotNull,
          reason:
              'Cancelling a translated date picker must re-enable endpoints',
        );
      }

      await tester.tap(_endpointTile(_Endpoint.start));
      await tester.pumpAndSettle();
      await _confirmPicker(tester);
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
      }
      await _cancelPicker(tester, _Endpoint.start.timeTitleKey);
      for (final endpoint in _Endpoint.values) {
        expect(
          tester.widget<ListTile>(_endpointTile(endpoint)).onTap,
          isNotNull,
          reason:
              'Cancelling a translated time picker must re-enable endpoints',
        );
      }
      expect(_endpointSubtitle(tester, _Endpoint.start), originalStart);
      expect(_endpointSubtitle(tester, _Endpoint.end), originalEnd);

      for (final endpoint in _Endpoint.values) {
        final chosenDate = DateTime(
          2026,
          5,
          endpoint == _Endpoint.start ? 19 : 20,
        );
        final chosenTime = endpoint == _Endpoint.start
            ? const TimeOfDay(hour: 20, minute: 0)
            : const TimeOfDay(hour: 12, minute: 0);
        await tester.tap(_endpointTile(endpoint));
        await tester.pumpAndSettle();
        final dateState = tester.state(_privateWidget('_AppDatePickerSheet'));
        final selectedDay = find.byKey(
          ValueKey('solar-day-2026-05-${chosenDate.day}'),
        );
        await tester.ensureVisible(selectedDay);
        await tester.tap(selectedDay);
        await tester.pumpAndSettle();

        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(
            tester.state(_privateWidget('_AppDatePickerSheet')),
            same(dateState),
          );
          expect(_modalWithTitle(endpoint.dateTitleKey), findsOneWidget);
          expect(find.text(I18nDateFormat.date(chosenDate)), findsOneWidget);
          expect(
            tester.state(find.byType(TimeAuditScreen, skipOffstage: false)),
            same(screenState),
          );
          expect(
            tester.state(_privateWidget('_TimeEntrySheet')),
            same(editorState),
          );
          expect(
            tester
                .widget<TextField>(_textField('time_audit.field.title'))
                .controller,
            same(titleController),
          );
        }

        await _confirmPicker(tester);
        final timeState = tester.state(_privateWidget('_AppTimePickerSheet'));
        await tester.tap(
          find.text(
            I18n.tr(
              endpoint == _Endpoint.start
                  ? 'picker.time.preset_evening'
                  : 'picker.time.preset_noon',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final wheels = _timeWheels(tester);
        final hourController =
            wheels[0].controller! as FixedExtentScrollController;
        final minuteController =
            wheels[1].controller! as FixedExtentScrollController;

        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(
            tester.state(_privateWidget('_AppTimePickerSheet')),
            same(timeState),
          );
          expect(_modalWithTitle(endpoint.timeTitleKey), findsOneWidget);
          final currentWheels = _timeWheels(tester);
          expect(currentWheels[0].controller, same(hourController));
          expect(currentWheels[1].controller, same(minuteController));
          expect(hourController.selectedItem, chosenTime.hour);
          expect(minuteController.selectedItem, 0);
          expect(
            find.descendant(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.header == true &&
                    widget.properties.label == AppTimePicker.format(chosenTime),
              ),
              matching: find.text(AppTimePicker.format(chosenTime)),
            ),
            findsOneWidget,
          );
          expect(
            tester.state(_privateWidget('_TimeEntrySheet')),
            same(editorState),
          );
          expect(titleController.text, 'Literal 混合 picker draft');
        }

        await _confirmPicker(tester);
        expect(
          _endpointSubtitle(tester, endpoint),
          I18nDateFormat.shortDateTime(
            DateTime(
              chosenDate.year,
              chosenDate.month,
              chosenDate.day,
              chosenTime.hour,
            ),
          ),
        );
      }

      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pumpAndSettle();
      expect(fixture.original.entries.single.title, 'Literal 混合 picker draft');
      expect(
        fixture.original.entries.single.startAt,
        DateTime(2026, 5, 19, 20),
      );
      expect(fixture.original.entries.single.endAt, DateTime(2026, 5, 20, 12));
      expect(tester.takeException(), isNull);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'retained endpoint callbacks reject reset replacement and account invalidation',
    (tester) async {
      for (final invalidation in _Invalidation.values) {
        final fixture = await _mountEditor(tester);
        final start = tester
            .widget<ListTile>(_endpointTile(_Endpoint.start))
            .onTap!;
        final end = tester
            .widget<ListTile>(_endpointTile(_Endpoint.end))
            .onTap!;
        await fixture.invalidate(tester, invalidation);
        final entries = fixture.snapshots;
        final pushes = fixture.observer.pushes;

        start();
        end();
        await tester.pumpAndSettle();

        expect(fixture.observer.pushes, pushes, reason: invalidation.name);
        expect(_privateWidget('_AppDatePickerSheet'), findsNothing);
        expect(_privateWidget('_AppTimePickerSheet'), findsNothing);
        expect(fixture.snapshots, entries, reason: invalidation.name);
        expect(tester.takeException(), isNull);
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'date results cannot open a time picker after their editor source expires',
    (tester) async {
      for (final invalidation in _Invalidation.values) {
        for (final endpoint in _Endpoint.values) {
          final fixture = await _mountEditor(tester);
          final editorState = tester.state(_privateWidget('_TimeEntrySheet'));
          final originalSubtitle = _endpointSubtitle(tester, endpoint);
          await tester.tap(_endpointTile(endpoint));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('solar-day-2026-05-19')));
          await tester.pumpAndSettle();
          await fixture.invalidate(tester, invalidation);
          final pushes = fixture.observer.pushes;
          final entries = fixture.snapshots;

          await _confirmPicker(tester);

          expect(fixture.observer.pushes, pushes, reason: invalidation.name);
          expect(_privateWidget('_AppTimePickerSheet'), findsNothing);
          if (editorState.mounted) {
            expect(_endpointSubtitle(tester, endpoint), originalSubtitle);
          }
          expect(fixture.snapshots, entries, reason: invalidation.name);
          expect(tester.takeException(), isNull);
          await fixture.dispose(tester);
        }
      }
    },
  );

  testWidgets(
    'time results cannot change an old draft after reset replacement or cleanup',
    (tester) async {
      for (final invalidation in _Invalidation.values) {
        for (final endpoint in _Endpoint.values) {
          final fixture = await _mountEditor(tester);
          final editorState = tester.state(_privateWidget('_TimeEntrySheet'));
          final originalStart = _endpointSubtitle(tester, _Endpoint.start);
          final originalEnd = _endpointSubtitle(tester, _Endpoint.end);
          await tester.tap(_endpointTile(endpoint));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('solar-day-2026-05-19')));
          await tester.pumpAndSettle();
          await _confirmPicker(tester);
          await tester.tap(find.text(I18n.tr('picker.time.preset_evening')));
          await tester.pumpAndSettle();
          await fixture.invalidate(tester, invalidation);
          final entries = fixture.snapshots;

          await _confirmPicker(tester);

          if (editorState.mounted) {
            expect(_endpointSubtitle(tester, _Endpoint.start), originalStart);
            expect(_endpointSubtitle(tester, _Endpoint.end), originalEnd);
          }
          expect(fixture.snapshots, entries, reason: invalidation.name);
          expect(tester.takeException(), isNull);
          await fixture.dispose(tester);
        }
      }
    },
  );

  testWidgets(
    'covered editor callbacks cannot pop write or open another picker',
    (tester) async {
      final fixture = await _mountEditor(tester);
      final editorState = tester.state(_privateWidget('_TimeEntrySheet'));
      final cancel = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          )
          .onPressed!;
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, I18n.tr('action.save')),
          )
          .onPressed!;
      final start = tester
          .widget<ListTile>(_endpointTile(_Endpoint.start))
          .onTap!;
      final end = tester.widget<ListTile>(_endpointTile(_Endpoint.end)).onTap!;
      final navigator = Navigator.of(
        tester.element(_privateWidget('_TimeEntrySheet')),
      );
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering route')),
        ),
      );
      await tester.pumpAndSettle();
      final pushes = fixture.observer.pushes;
      final pops = fixture.observer.pops;
      final entries = fixture.snapshots;

      cancel();
      save();
      start();
      end();
      await tester.pumpAndSettle();

      expect(find.text('Covering route'), findsOneWidget);
      expect(fixture.observer.pushes, pushes);
      expect(fixture.observer.pops, pops);
      expect(fixture.snapshots, entries);
      expect(editorState.mounted, isTrue);

      navigator.pop();
      await tester.pumpAndSettle();
      cancel();
      await tester.pumpAndSettle();
      expect(editorState.mounted, isFalse);
      expect(find.byType(TimeAuditScreen), findsOneWidget);
      expect(fixture.original.entries, hasLength(1));
      expect(tester.takeException(), isNull);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'retained date picker actions preserve a covering route and the next time picker',
    (tester) async {
      final fixture = await _mountEditor(tester);
      final editorState = tester.state(_privateWidget('_TimeEntrySheet'));
      final originalStart = _endpointSubtitle(tester, _Endpoint.start);
      final originalEnd = _endpointSubtitle(tester, _Endpoint.end);
      final entries = fixture.snapshots;
      final chosenDate = DateTime(2026, 5, 19);
      await tester.tap(_endpointTile(_Endpoint.start));
      await tester.pumpAndSettle();
      final selectedDay = find.byKey(const ValueKey('solar-day-2026-05-19'));
      await tester.ensureVisible(selectedDay);
      await tester.tap(selectedDay);
      await tester.pumpAndSettle();

      final datePicker = _privateWidget('_AppDatePickerSheet');
      final dateState = tester.state(datePicker);
      final dateRoute = ModalRoute.of(tester.element(datePicker))!;
      final dateActions = _pickerActions(tester, _Endpoint.start.dateTitleKey);
      var dateCompletions = 0;
      AppDatePickerResult? dateResult;
      final dateCompletion = dateRoute.popped.then<void>((value) {
        dateCompletions++;
        dateResult = value as AppDatePickerResult?;
      });

      await _exerciseCoveredPickerActions(
        tester,
        fixture,
        picker: datePicker,
        actions: dateActions,
        hasCompleted: () => dateCompletions != 0,
      );

      dateActions.confirm();
      await tester.pumpAndSettle();
      expect(dateCompletions, 1);
      await dateCompletion;
      expect(dateResult?.date, chosenDate);
      expect(dateState.mounted, isFalse);
      expect(_modalWithTitle(_Endpoint.start.timeTitleKey), findsOneWidget);
      expect(
        tester.state(_privateWidget('_TimeEntrySheet')),
        same(editorState),
      );

      final timePicker = _privateWidget('_AppTimePickerSheet');
      final timeState = tester.state(timePicker);
      final timeRoute = ModalRoute.of(tester.element(timePicker))!;
      var timeCompletions = 0;
      final timeCompletion = timeRoute.popped.then<void>((_) {
        timeCompletions++;
      });
      final pushes = fixture.observer.pushes;
      final pops = fixture.observer.pops;

      for (final callback in [dateActions.cancel, dateActions.confirm]) {
        callback();
        await tester.pumpAndSettle();

        expect(timeRoute.isActive, isTrue);
        expect(timeRoute.isCurrent, isTrue);
        expect(tester.state(timePicker), same(timeState));
        expect(timeCompletions, 0);
        expect(dateCompletions, 1);
        expect(fixture.observer.pushes, pushes);
        expect(fixture.observer.pops, pops);
        expect(_endpointSubtitle(tester, _Endpoint.start), originalStart);
        expect(_endpointSubtitle(tester, _Endpoint.end), originalEnd);
        expect(fixture.snapshots, entries);
        expect(tester.takeException(), isNull);
      }

      await _cancelPicker(tester, _Endpoint.start.timeTitleKey);
      expect(timeCompletions, 1);
      await timeCompletion;
      expect(
        tester.state(_privateWidget('_TimeEntrySheet')),
        same(editorState),
      );
      expect(_endpointSubtitle(tester, _Endpoint.start), originalStart);
      expect(_endpointSubtitle(tester, _Endpoint.end), originalEnd);
      expect(fixture.snapshots, entries);
      expect(tester.takeException(), isNull);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'retained time picker actions preserve cover and reject an invalidated editor',
    (tester) async {
      final fixture = await _mountEditor(tester);
      final editor = _privateWidget('_TimeEntrySheet');
      final editorState = tester.state(editor);
      final editorRoute = ModalRoute.of(tester.element(editor))!;
      final originalStart = _endpointSubtitle(tester, _Endpoint.start);
      final originalEnd = _endpointSubtitle(tester, _Endpoint.end);
      final titleController = tester
          .widget<TextField>(_textField('time_audit.field.title'))
          .controller!;
      titleController.text = 'Invalidated picker draft';
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, I18n.tr('action.save')),
          )
          .onPressed!;
      final entries = fixture.snapshots;
      await tester.tap(_endpointTile(_Endpoint.start));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('solar-day-2026-05-19')));
      await tester.pumpAndSettle();
      await _confirmPicker(tester);
      await tester.tap(find.text(I18n.tr('picker.time.preset_evening')));
      await tester.pumpAndSettle();

      final timePicker = _privateWidget('_AppTimePickerSheet');
      final timeState = tester.state(timePicker);
      final timeRoute = ModalRoute.of(tester.element(timePicker))!;
      final timeActions = _pickerActions(tester, _Endpoint.start.timeTitleKey);
      var timeCompletions = 0;
      TimeOfDay? timeResult;
      final timeCompletion = timeRoute.popped.then<void>((value) {
        timeCompletions++;
        timeResult = value as TimeOfDay?;
      });

      await _exerciseCoveredPickerActions(
        tester,
        fixture,
        picker: timePicker,
        actions: timeActions,
        hasCompleted: () => timeCompletions != 0,
      );

      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      await fixture.invalidate(tester, _Invalidation.accountCleanup);
      expect(
        AccountLocalDataCleaner.accountDataGeneration,
        isNot(accountGeneration),
      );
      expect(tester.state(timePicker), same(timeState));
      expect(timeCompletions, 0);
      timeActions.confirm();
      await tester.pumpAndSettle();
      expect(timeCompletions, 1);
      await timeCompletion;
      expect(timeResult, const TimeOfDay(hour: 20, minute: 0));
      expect(timeState.mounted, isFalse);
      expect(editorRoute.isActive, isTrue);
      expect(editorRoute.isCurrent, isTrue);
      expect(tester.state(editor), same(editorState));
      expect(_endpointSubtitle(tester, _Endpoint.start), originalStart);
      expect(_endpointSubtitle(tester, _Endpoint.end), originalEnd);
      expect(titleController.text, 'Invalidated picker draft');
      expect(fixture.snapshots, entries);
      expect(tester.takeException(), isNull);
      final pushes = fixture.observer.pushes;
      final pops = fixture.observer.pops;

      for (final callback in [timeActions.cancel, timeActions.confirm, save]) {
        callback();
        await tester.pumpAndSettle();

        expect(editorRoute.isActive, isTrue);
        expect(editorRoute.isCurrent, isTrue);
        expect(tester.state(editor), same(editorState));
        expect(_privateWidget('_AppDatePickerSheet'), findsNothing);
        expect(_privateWidget('_AppTimePickerSheet'), findsNothing);
        expect(timeCompletions, 1);
        expect(fixture.observer.pushes, pushes);
        expect(fixture.observer.pops, pops);
        expect(_endpointSubtitle(tester, _Endpoint.start), originalStart);
        expect(_endpointSubtitle(tester, _Endpoint.end), originalEnd);
        expect(titleController.text, 'Invalidated picker draft');
        expect(fixture.snapshots, entries);
        expect(tester.takeException(), isNull);
      }
      await fixture.dispose(tester);
    },
  );
}

enum _Endpoint {
  start,
  end;

  String get labelKey => 'time_audit.field.$name';
  String get dateTitleKey => 'time_audit.picker.${name}_date';
  String get timeTitleKey => 'time_audit.picker.${name}_time';
}

enum _Invalidation { reset, replacement, accountCleanup }

Finder _privateWidget(String name) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == name,
  skipOffstage: false,
);

Finder _textField(String labelKey) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == I18n.tr(labelKey),
  skipOffstage: false,
);

Finder _endpointTile(_Endpoint endpoint) => find.byWidgetPredicate(
  (widget) =>
      widget is ListTile &&
      widget.title is Text &&
      (widget.title! as Text).data == I18n.tr(endpoint.labelKey),
  skipOffstage: false,
);

String _endpointSubtitle(WidgetTester tester, _Endpoint endpoint) =>
    (tester.widget<ListTile>(_endpointTile(endpoint)).subtitle! as Text).data!;

Finder _modalWithTitle(String titleKey) => find.byWidgetPredicate(
  (widget) => widget is AppModalSheet && widget.title == I18n.tr(titleKey),
  skipOffstage: false,
);

List<ListWheelScrollView> _timeWheels(WidgetTester tester) => tester
    .widgetList<ListWheelScrollView>(
      find.descendant(
        of: _privateWidget('_AppTimePickerSheet'),
        matching: find.byType(ListWheelScrollView),
      ),
    )
    .toList();

Future<void> _confirmPicker(WidgetTester tester) async {
  final confirm = find.widgetWithText(FilledButton, I18n.tr('action.confirm'));
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

Future<void> _cancelPicker(WidgetTester tester, String titleKey) async {
  final cancel = find.descendant(
    of: _modalWithTitle(titleKey),
    matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
  );
  await tester.ensureVisible(cancel);
  await tester.tap(cancel);
  await tester.pumpAndSettle();
}

({VoidCallback cancel, VoidCallback confirm}) _pickerActions(
  WidgetTester tester,
  String titleKey,
) {
  final modal = _modalWithTitle(titleKey);
  return (
    cancel: tester
        .widget<TextButton>(
          find.descendant(
            of: modal,
            matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          ),
        )
        .onPressed!,
    confirm: tester
        .widget<FilledButton>(
          find.descendant(
            of: modal,
            matching: find.widgetWithText(
              FilledButton,
              I18n.tr('action.confirm'),
            ),
          ),
        )
        .onPressed!,
  );
}

Future<void> _exerciseCoveredPickerActions(
  WidgetTester tester,
  _Fixture fixture, {
  required Finder picker,
  required ({VoidCallback cancel, VoidCallback confirm}) actions,
  required bool Function() hasCompleted,
}) async {
  final pickerState = tester.state(picker);
  final pickerRoute = ModalRoute.of(tester.element(picker))!;
  final navigator = pickerRoute.navigator!;
  final cover = MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('Picker covering route')),
  );
  navigator.push<void>(cover);
  await tester.pumpAndSettle();
  final pushes = fixture.observer.pushes;
  final pops = fixture.observer.pops;
  final entries = fixture.snapshots;

  for (final callback in [actions.cancel, actions.confirm]) {
    callback();
    await tester.pumpAndSettle();

    expect(find.text('Picker covering route'), findsOneWidget);
    expect(cover.isActive, isTrue);
    expect(cover.isCurrent, isTrue);
    expect(pickerRoute.isActive, isTrue);
    expect(pickerRoute.isCurrent, isFalse);
    expect(pickerState.mounted, isTrue);
    expect(tester.state(picker), same(pickerState));
    expect(hasCompleted(), isFalse);
    expect(fixture.observer.pushes, pushes);
    expect(fixture.observer.pops, pops);
    expect(fixture.snapshots, entries);
    expect(tester.takeException(), isNull);
  }

  navigator.pop();
  await tester.pumpAndSettle();
  expect(cover.isActive, isFalse);
  expect(pickerRoute.isCurrent, isTrue);
  expect(tester.state(picker), same(pickerState));
  expect(hasCompleted(), isFalse);
  expect(tester.takeException(), isNull);
}

Future<_Fixture> _mountEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = TimeAuditProvider();
  final fixture = _Fixture(provider);
  await provider.add(
    TimeEntry(
      id: 'picker-entry',
      title: 'Original picker entry',
      startAt: DateTime(2026, 5, 17, 9, 15),
      endAt: DateTime(2026, 5, 17, 10, 30),
    ),
  );
  await tester.pumpWidget(
    ValueListenableBuilder<TimeAuditProvider>(
      valueListenable: fixture.selected,
      builder: (_, current, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: fixture.theme),
          ChangeNotifierProvider<TimeAuditProvider>.value(value: current),
        ],
        child: MaterialApp(
          navigatorObservers: [fixture.observer],
          home: const BrandRouteSurface(
            child: TimeAuditScreen(initialEntryId: 'picker-entry'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(_privateWidget('_TimeEntrySheet'), findsOneWidget);
  return fixture;
}

class _Fixture {
  _Fixture(this.original) : selected = ValueNotifier(original);

  final TimeAuditProvider original;
  final ValueNotifier<TimeAuditProvider> selected;
  final theme = ThemeProvider();
  final observer = _RouteObserver();
  TimeAuditProvider? replacement;

  List<Object> get snapshots => [
    original.entries.map((entry) => entry.toJson()).toList(),
    if (replacement != null)
      replacement!.entries.map((entry) => entry.toJson()).toList(),
  ];

  Future<void> invalidate(
    WidgetTester tester,
    _Invalidation invalidation,
  ) async {
    switch (invalidation) {
      case _Invalidation.reset:
        original.resetLocalState();
      case _Invalidation.replacement:
        replacement = TimeAuditProvider();
        selected.value = replacement!;
      case _Invalidation.accountCleanup:
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    }
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    selected.dispose();
    theme.dispose();
    original.dispose();
    replacement?.dispose();
  }
}

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}
