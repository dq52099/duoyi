import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/habit_unit_draft.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/widgets/habit_unit_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.en);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'untouched add unit follows locale and quantity without authored text',
    (tester) async {
      final f = _Fixture();
      await f.pump(tester);
      await f.openAdd(tester);
      final controller = _unit(tester).controller!;
      expect(controller.text, isEmpty);
      expect(_unit(tester).decoration!.hintText, 'time');
      expect(
        _unit(tester).decoration!.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      await _enter(tester, 'Daily target', '2');
      expect(_unit(tester).decoration!.hintText, 'times');
      final payloadBeforeLocale = f.habits.habits
          .map((h) => h.toJson())
          .toList();
      final remindersBeforeLocale = f.scheduler.habitSyncs.length;
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(_unit(tester).controller, same(controller));
      expect(_unit(tester).decoration!.hintText, '次');
      expect(
        f.habits.habits.map((h) => h.toJson()).toList(),
        payloadBeforeLocale,
      );
      expect(f.scheduler.habitSyncs.length, remindersBeforeLocale);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      await _enter(tester, 'Daily target', '1');
      await _enter(tester, 'Habit name', 'Untouched generated');
      await _saveAdd(tester);
      expect(f.habits.habits.single.unit, isNull);
      expect(f.habits.habits.single.generatedUnitKey, isNull);
      expect((await _saved()).generatedUnitKey, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'water recommendation keeps semantic cups through resize locale save and reload',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = _Fixture();
      await f.pump(tester);
      await f.openAdd(tester);
      await _water(tester);
      await _enter(tester, 'Daily target', '1');
      final controller = _unit(tester).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      expect(controller.text, isEmpty);
      expect(_unit(tester).decoration!.hintText, 'cup');
      tester.view.physicalSize = const Size(700, 844);
      await tester.pumpAndSettle();
      expect(_unit(tester).controller, same(controller));
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(_unit(tester).decoration!.hintText, '杯');
      expect(_field(tester, '习惯名称').controller!.text, 'Drink water');
      expect(_field(tester, '分组').controller!.text, 'Health');
      await _saveAdd(tester);
      final restored = await _saved();
      expect(restored.unit, isNull);
      expect(restored.generatedUnitKey, 'cup');
      expect(
        restored.formatCountForDate(DateTime.now(), locale: AppLocale.en),
        '0 cups / 1 cup',
      );
      expect(
        restored.formatCountForDate(DateTime.now(), locale: AppLocale.zh),
        '0 杯 / 1 杯',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final literal in ['cup', 'times', '次', 'ml']) {
    testWidgets(
      'explicitly authored $literal survives count and locale changes',
      (tester) async {
        final f = _Fixture();
        await f.pump(tester);
        await f.openAdd(tester);
        await _water(tester);
        await _enter(tester, 'Unit', literal);
        final controller = _unit(tester).controller!;
        final value = controller.value.copyWith(
          selection: TextSelection.collapsed(offset: literal.length),
          composing: TextRange(start: 0, end: literal.length),
        );
        controller.value = value;
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        expect(controller.value, value);
        expect(_unit(tester).decoration!.hintText, isNull);
        await _enter(tester, '每日目标', '1');
        await _saveAdd(tester);
        final restored = await _saved();
        expect(restored.unit, literal);
        expect(restored.generatedUnitKey, isNull);
        expect(
          restored.formatCountForDate(DateTime.now(), locale: AppLocale.en),
          '0 $literal / 1 $literal',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'clearing a recommended unit restores default instead of reviving cups',
    (tester) async {
      final f = _Fixture();
      await f.pump(tester);
      await f.openAdd(tester);
      await _water(tester);
      await _enter(tester, 'Unit', 'ml');
      await _enter(tester, 'Unit', '');
      await _enter(tester, 'Daily target', '1');
      expect(_unit(tester).decoration!.hintText, 'time');
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(_unit(tester).controller!.text, isEmpty);
      expect(_unit(tester).decoration!.hintText, '次');
      await _saveAdd(tester);
      expect((await _saved()).unit, isNull);
      expect((await _saved()).generatedUnitKey, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final sample in const [
    (literal: null, key: null, hint: 'time'),
    (literal: null, key: 'cup', hint: 'cup'),
    (literal: null, key: 'future-unit', hint: 'time'),
    (literal: '', key: 'cup', hint: null),
    (literal: '  ', key: 'future-unit', hint: null),
    (literal: '杯', key: null, hint: null),
  ]) {
    testWidgets('untouched editor preserves raw source $sample', (
      tester,
    ) async {
      final f = _Fixture();
      await f.pump(
        tester,
        habit: Habit(
          id: 'edit',
          name: 'Editor habit',
          unit: sample.literal,
          generatedUnitKey: sample.key,
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      final controller = _unit(tester).controller!;
      expect(controller.text, sample.literal ?? '');
      expect(_unit(tester).decoration!.hintText, sample.hint);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(_unit(tester).controller, same(controller));
      await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final restored = await _saved();
      expect(restored.unit, sample.literal);
      expect(restored.generatedUnitKey, sample.key);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('add freezes one candidate before gated reminder permission', (
    tester,
  ) async {
    final notification = _GateNotification();
    final f = _Fixture(notification: notification);
    await f.pump(tester);
    await f.openAdd(tester);
    await _water(tester);
    await _enter(tester, 'Daily target', '1');
    final name = _field(tester, 'Habit name').controller!;
    final target = _field(tester, 'Daily target').controller!;
    final unit = _unit(tester).controller!;
    final category = _field(tester, 'Group').controller!;
    final retainedRecommendation = tester
        .widget<ActionChip>(_waterFinder())
        .onPressed!;
    await _saveAdd(tester, settle: false);
    expect(notification.calls, 1);
    expect(_unit(tester).enabled, isFalse);
    expect(_field(tester, 'Habit name').enabled, isFalse);
    retainedRecommendation();
    // Even direct controller writes cannot alter the submitted snapshot.
    name.text = 'Later name';
    target.text = '9';
    unit.text = 'ml';
    category.text = 'Later category';
    I18n.setLocale(AppLocale.zh);
    await tester.pump();
    notification.pending.complete(true);
    await tester.pumpAndSettle();
    final saved = await _saved();
    expect(saved.name, 'Drink water');
    expect(saved.targetCount, 1);
    expect(saved.unit, isNull);
    expect(saved.generatedUnitKey, 'cup');
    expect(saved.category, 'Health');
    expect(saved.remind, isTrue);
    expect(f.habits.habits.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission denial preserves generated draft for retry', (
    tester,
  ) async {
    final notification = _GateNotification();
    final f = _Fixture(notification: notification);
    await f.pump(tester);
    await f.openAdd(tester);
    await _water(tester);
    await _saveAdd(tester, settle: false);
    notification.pending.complete(false);
    await tester.pumpAndSettle();
    expect(f.habits.habits, isEmpty);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_unit(tester).controller!.text, isEmpty);
    expect(_unit(tester).decoration!.hintText, 'cups');
    notification.pending = Completer<bool>();
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    await _saveAdd(tester, settle: false);
    expect(notification.calls, 2);
    notification.pending.complete(true);
    await tester.pumpAndSettle();
    expect((await _saved()).generatedUnitKey, 'cup');
    expect((await _saved()).unit, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor freezes candidate before permission without materializing units',
    (tester) async {
      final notification = _GateNotification();
      final f = _Fixture(notification: notification);
      await f.pump(
        tester,
        habit: Habit(
          id: 'edit',
          name: 'Before permission',
          generatedUnitKey: 'cup',
          remind: true,
          remindHour: 8,
          remindMinute: 0,
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      final name = _field(tester, 'Habit name').controller!;
      final unit = _unit(tester).controller!;
      final target = _field(
        tester,
        I18n.tr('habit.field.daily_target_count'),
      ).controller!;
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      expect(notification.calls, 1);
      name.text = 'After permission';
      target.text = '8';
      unit.text = 'ml';
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      notification.pending.complete(true);
      await tester.pumpAndSettle();
      final saved = await _saved();
      expect(saved.name, 'Before permission');
      expect(saved.targetCount, 1);
      expect(saved.unit, isNull);
      expect(saved.generatedUnitKey, 'cup');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unit field has readable default-brand hints at narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadWeeklyReviewScreenshotFonts);
      final f = _Fixture(scale: 1.6);
      await f.pump(tester);
      await f.openAdd(tester);
      await _water(tester);
      await _enter(tester, 'Daily target', '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await _capture(tester, f.captureKey, 'unit-field-en.png');
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      await _capture(tester, f.captureKey, 'unit-field-zh.png');
      expect(_unit(tester).decoration!.hintText, '杯');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'draft distinguishes real edits from generated labels and unchanged legacy blanks',
    () {
      for (final literal in ['', ' ', 'times', 'cup', '杯']) {
        final draft = HabitUnitDraft(
          authoredUnit: literal,
          generatedUnitKey: 'future',
        );
        expect(draft.authoredUnit, literal);
        expect(draft.generatedUnitKey, 'future');
        draft.selectGenerated('cup');
        expect(draft.controller.text, isEmpty);
        draft.controller.text = 'cup';
        draft.recordEdit('cup');
        expect(draft.authoredUnit, 'cup');
        expect(draft.generatedUnitKey, isNull);
        draft.controller.clear();
        draft.recordEdit('');
        expect(draft.authoredUnit, isNull);
        expect(draft.generatedUnitKey, isNull);
        draft.dispose();
      }
    },
  );
}

Finder _fieldFinder(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
TextField _field(WidgetTester tester, String label) =>
    tester.widget<TextField>(_fieldFinder(label));
TextField _unit(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byType(HabitUnitField),
    matching: find.byType(TextField),
  ),
);
Finder _waterFinder() => find.byWidgetPredicate(
  (w) =>
      w is ActionChip &&
      w.label is Text &&
      ((w.label as Text).data ?? '').startsWith('Drink water'),
);

Future<void> _water(WidgetTester tester) async {
  await tester.ensureVisible(_waterFinder());
  await tester.tap(_waterFinder());
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(_fieldFinder(label));
  await tester.enterText(_fieldFinder(label), value);
  await tester.pumpAndSettle();
}

Future<void> _saveAdd(WidgetTester tester, {bool settle = true}) async {
  final button = find.byWidgetPredicate(
    (w) =>
        w is ElevatedButton &&
        w.child is Text &&
        ['Start new habit', '开启新习惯'].contains((w.child as Text).data),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<Habit> _saved() async {
  final prefs = await SharedPreferences.getInstance();
  final rows = jsonDecode(prefs.getString('habits')!) as List;
  return Habit.fromJson(Map<String, dynamic>.from(rows.single as Map));
}

class _Fixture {
  final habits = HabitProvider();
  final scheduler = RecordingReminderScheduler();
  final audit = TimeAuditProvider();
  final theme = ThemeProvider();
  final GlobalKey captureKey = GlobalKey();
  final _GateNotification? notification;
  final double scale;

  _Fixture({this.notification, this.scale = 1});

  Future<void> pump(WidgetTester tester, {Habit? habit}) async {
    habits.timeAudit = audit;
    habits.scheduler = scheduler;
    if (habit != null) await habits.addHabit(habit);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      habits.dispose();
      audit.dispose();
      theme.dispose();
      notification?.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ListenableProvider<NotificationService?>.value(value: notification),
        ],
        child: MaterialApp(
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: captureKey, child: child!),
          ),
          home: habit == null
              ? const HabitScreen()
              : Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () =>
                            showHabitEditor(context, habits.habits.single),
                        child: const Text('Open editor'),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAdd(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }
}

class _GateNotification extends NotificationService {
  Completer<bool> pending = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) {
    calls++;
    return pending.future;
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['DUOYI_HABIT_UNIT_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
