import 'dart:async';

import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/focus_sound_catalog.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _roomNameThatLooksBuiltIn = '深度工作自习室';
const _taskName = 'Plan Q3 launch';
const _tag = 'literal-tag-17';
final _start = DateTime(2026, 3, 14, 9, 35);

class _FixtureRooms extends FocusRoomProvider {
  final FocusRoom room = FocusRoom(
    id: 'custom-room-1',
    name: _roomNameThatLooksBuiltIn,
    description: 'A custom room with a built-in-looking name',
    weeklyTargetSeconds: 7200,
    accentColor: Colors.blue.toARGB32(),
    members: const [],
    createdAt: DateTime(2026, 1, 1),
  );

  @override
  List<FocusRoom> get rooms => [room];
}

class _CountingPomodoro extends PomodoroProvider {
  int saveCalls = 0;
  bool saveResult = true;
  Completer<bool>? heldSave;

  @override
  Future<bool> updateSession(PomodoroSession updated) async {
    saveCalls++;
    return heldSave?.future ?? saveResult;
  }
}

class _EditorHost extends StatelessWidget {
  const _EditorHost({required this.pomodoro, required this.rooms});

  final PomodoroProvider pomodoro;
  final FocusRoomProvider rooms;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
          ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
        ],
        child: MaterialApp(
          locale: locale.flutterLocale,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const ValueKey('open-session-editor'),
                  onPressed: () => showPomodoroSessionEditor(context, _session),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _session = PomodoroSession(
  id: 'session-1',
  startTime: _start,
  endTime: _start.add(const Duration(minutes: 45)),
  durationSeconds: 45 * 60,
  type: PomodoroType.shortBreak,
  taskName: _taskName,
  tag: _tag,
  whiteNoiseSound: 'rain',
  focusRoomId: 'custom-room-1',
);

void main() {
  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(originalLocale));

  testWidgets(
    'session editor refuses retained save after same-account ID is invalidated',
    (tester) async {
      final f = await _open(tester);
      final save = _saveCallback(tester);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      save();
      await tester.pumpAndSettle();
      expect(f.pomodoro.saveCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locale switch preserves editor fields, selection, focus and dropdown elements',
    (tester) async {
      await _open(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'unchanged draft');
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 6,
      );
      final focus = FocusManager.instance.primaryFocus;
      final dropdowns = find
          .byWidgetPredicate((widget) => widget is AppDropdownField)
          .evaluate()
          .toList();
      expect(dropdowns, isNotEmpty);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final next = find
          .byWidgetPredicate((widget) => widget is AppDropdownField)
          .evaluate()
          .toList();
      expect(next, hasLength(dropdowns.length));
      for (var i = 0; i < next.length; i++) {
        expect(identical(next[i], dropdowns[i]), isTrue);
      }
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(controller.text, 'unchanged draft');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 6),
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy editor suppresses duplicate saves and removes only its own route',
    (tester) async {
      final f = await _open(tester);
      f.pomodoro.heldSave = Completer<bool>();
      final save = _saveCallback(tester);
      save();
      save();
      await tester.pump();
      expect(f.pomodoro.saveCalls, 1);
      final editorContext = tester.element(find.byType(TextField).first);
      final ownRoute = ModalRoute.of(editorContext)!;
      Navigator.of(editorContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covering editor')),
        ),
      );
      await tester.pumpAndSettle();
      f.pomodoro.heldSave!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('covering editor'), findsOneWidget);
      expect(ownRoute.isActive, isFalse);
      expect(f.pomodoro.saveCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejected session keeps text selection and permits explicit retry',
    (tester) async {
      final f = await _open(tester);
      f.pomodoro.saveResult = false;
      await tester.enterText(
        find.byType(TextField).first,
        'retained literal draft',
      );
      final controller = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 7,
      );
      _saveCallback(tester)();
      await tester.pumpAndSettle();
      expect(controller.text, 'retained literal draft');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );
      expect(
        find.text(FocusRoomUiCopy.editSessionTitle(AppLocale.zh)),
        findsOneWidget,
      );
      f.pomodoro.saveResult = true;
      _saveCallback(tester)();
      await tester.pumpAndSettle();
      expect(f.pomodoro.saveCalls, 2);
      expect(
        find.text(FocusRoomUiCopy.editSessionTitle(AppLocale.zh)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open picker translates heading and stale account result cannot edit draft',
    (tester) async {
      final f = await _open(tester);
      await tester.tap(
        find.widgetWithText(
          ListTile,
          FocusRoomUiCopy.startTimeLabel(AppLocale.zh),
        ),
      );
      await tester.pumpAndSettle();
      final wheels = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      final selected = wheels
          .map(
            (wheel) =>
                (wheel.controller! as FixedExtentScrollController).selectedItem,
          )
          .toList();
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('picker.time.title')), findsOneWidget);
      final next = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      expect(
        next
            .map(
              (wheel) => (wheel.controller! as FixedExtentScrollController)
                  .selectedItem,
            )
            .toList(),
        selected,
      );
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(f.pomodoro.saveCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'session editor copy follows locale while all edited values stay selected',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pomodoro = _CountingPomodoro();
      final rooms = _FixtureRooms();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        pomodoro.dispose();
        rooms.dispose();
      });

      await tester.pumpWidget(_EditorHost(pomodoro: pomodoro, rooms: rooms));
      await tester.tap(find.byKey(const ValueKey('open-session-editor')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Edited task text');
      await tester.enterText(find.byType(TextField).at(1), 'Edited tag value');
      await tester.enterText(find.byType(TextField).at(2), '60');
      await tester.tap(find.text(FocusRoomUiCopy.focusTypeFocus(AppLocale.zh)));
      await tester.pumpAndSettle();

      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        expect(
          find.text(FocusRoomUiCopy.editSessionTitle(locale)),
          findsOneWidget,
        );
        expect(
          find.text(FocusRoomUiCopy.editSessionSubtitle(locale)),
          findsOneWidget,
        );
        expect(
          find.text(FocusRoomUiCopy.taskNameLabel(locale)),
          findsOneWidget,
        );
        expect(find.text(FocusRoomUiCopy.taskTagLabel(locale)), findsOneWidget);
        expect(find.text(FocusRoomUiCopy.dateLabel(locale)), findsOneWidget);
        expect(
          find.text(FocusRoomUiCopy.startTimeLabel(locale)),
          findsOneWidget,
        );
        expect(
          find.text(FocusRoomUiCopy.durationMinutesLabel(locale)),
          findsOneWidget,
        );
        expect(
          find.text(FocusRoomUiCopy.whiteNoiseLabel(locale)),
          findsOneWidget,
        );
        expect(find.text(FocusRoomUiCopy.cancel(locale)), findsOneWidget);
        expect(find.text(FocusRoomUiCopy.save(locale)), findsOneWidget);

        final fields = tester.widgetList<TextField>(find.byType(TextField));
        expect(fields.map((field) => field.controller?.text).toList(), [
          'Edited task text',
          'Edited tag value',
          '60',
        ]);

        final typeControl = tester.widget<SegmentedButton<PomodoroType>>(
          find.byType(SegmentedButton<PomodoroType>),
        );
        expect(typeControl.selected, {PomodoroType.focus});
        expect(
          typeControl.segments
              .map((segment) => (segment.label as Text).data)
              .toList(),
          [
            FocusRoomUiCopy.focusTypeFocus(locale),
            FocusRoomUiCopy.focusTypeShortBreak(locale),
            FocusRoomUiCopy.focusTypeLongBreak(locale),
          ],
        );

        final rainLabel = FocusSoundCatalog.options
            .singleWhere((option) => option.id == 'rain')
            .displayLabel(locale: locale);
        expect(find.text(rainLabel), findsOneWidget);
        expect(find.text(_roomNameThatLooksBuiltIn), findsOneWidget);
        expect(
          find.text(FocusRoomBuiltinKind.deepWork.nameFor(AppLocale.en)),
          findsNothing,
        );

        await tester.tap(
          find.widgetWithText(ListTile, FocusRoomUiCopy.dateLabel(locale)),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.text(I18nDateFormat.date(DateTime(2026, 3, 14))),
          ),
          findsOneWidget,
        );
        final selectedDateCell = find.byKey(
          const ValueKey('solar-day-2026-03-14'),
        );
        expect(selectedDateCell, findsOneWidget);
        final selectedDateSemantics = tester.widget<Semantics>(
          find
              .ancestor(of: selectedDateCell, matching: find.byType(Semantics))
              .first,
        );
        expect(selectedDateSemantics.properties.selected, isTrue);
        expect(
          selectedDateSemantics.properties.label,
          I18nDateFormat.date(DateTime(2026, 3, 14)),
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(ListTile, FocusRoomUiCopy.startTimeLabel(locale)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListWheelScrollView), findsNWidgets(2));
        expect(
          find.text(AppTimePicker.format(const TimeOfDay(hour: 9, minute: 35))),
          findsNWidgets(2),
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(pomodoro.saveCalls, 0);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text(FocusRoomUiCopy.cancel(AppLocale.zh)));
      await tester.pumpAndSettle();
      expect(
        find.text(FocusRoomUiCopy.editSessionTitle(AppLocale.zh)),
        findsNothing,
      );
      expect(pomodoro.saveCalls, 0);
    },
  );
}

Future<({_CountingPomodoro pomodoro, _FixtureRooms rooms})> _open(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pomodoro = _CountingPomodoro();
  final rooms = _FixtureRooms();
  addTearDown(() async {
    if (pomodoro.heldSave != null && !pomodoro.heldSave!.isCompleted) {
      pomodoro.heldSave!.complete(false);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    pomodoro.dispose();
    rooms.dispose();
  });
  await tester.pumpWidget(_EditorHost(pomodoro: pomodoro, rooms: rooms));
  await tester.tap(find.byKey(const ValueKey('open-session-editor')));
  await tester.pumpAndSettle();
  return (pomodoro: pomodoro, rooms: rooms);
}

VoidCallback _saveCallback(WidgetTester tester) {
  final finder = find
      .ancestor(
        of: find.text(FocusRoomUiCopy.save(I18n.current)),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      )
      .first;
  return tester.widget<ButtonStyleButton>(finder).onPressed!;
}
