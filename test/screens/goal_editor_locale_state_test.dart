import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    testWidgets('advance reminders require a target date ${locale.name}', (
      tester,
    ) async {
      final f = await _pumpEditor(
        tester,
        initialGoal: GoalItem(
          id: 'goal-needs-target',
          title: 'Original goal',
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'advance-rule',
                type: ReminderRuleType.relativeToDue,
                kind: ReminderKind.push,
                hour: 9,
                minute: 0,
                offsetMinutes: -30,
              ),
            ],
          ),
        ),
      );
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Edited goal');
      await _saveAndDrain(tester);
      expect(
        f.store.writes,
        0,
        reason:
            'A relative reminder without a target must not be saved silently',
      );
      expect(f.provider.goals.single.title, 'Original goal');
      expect(find.byType(GoalEditScreen), findsOneWidget);
      expect(
        _feedback(tester),
        locale == AppLocale.en
            ? 'Set a target date for advance reminders.'
            : '请先设置目标日期，再使用提前提醒。',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Edited goal',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Goal editor locale retains its route, draft, selection and focus',
    (tester) async {
      final f = await _pumpEditor(tester);
      final route = find.byType(GoalEditScreen);
      final state = tester.state<State<GoalEditScreen>>(route);
      await tester.enterText(
        find.byType(TextField).first,
        'Literal / 自定义 draft',
      );
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      final controller = editable.controller;
      final focus = editable.focusNode;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 7,
      );
      await tester.pump();
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        final retained = tester.widget<EditableText>(
          find.byType(EditableText).first,
        );
        expect(tester.state<State<GoalEditScreen>>(route), same(state));
        expect(retained.controller, same(controller));
        expect(retained.focusNode, same(focus));
        expect(controller.text, 'Literal / 自定义 draft');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 7),
        );
        expect(focus.hasFocus, isTrue);
        final title = tester.widget<AppBar>(find.byType(AppBar)).title! as Text;
        if (locale == AppLocale.en) {
          expect(title.data, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        } else {
          expect(title.data, matches(RegExp(r'[\u3400-\u9fff]')));
        }
        expect(tester.takeException(), isNull);
      }
      expect(f.store.writes, 0);
    },
  );

  testWidgets(
    'Rejected Goal save retains its form and permits a single retry',
    (tester) async {
      final f = await _pumpEditor(tester);
      await tester.enterText(find.byType(TextField).first, 'Synthetic goal');
      f.store.rejectOnce = true;
      await _saveAndDrain(tester);
      expect(tester.takeException(), isNull);
      expect(f.provider.goals, isEmpty);
      expect(find.byType(GoalEditScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Synthetic goal',
      );
      expect(find.byType(SnackBar), findsOneWidget);
      final before = _feedback(tester);
      expect(before, isNot(contains('StateError')));
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(_feedback(tester), isNot(before));
      expect(_feedback(tester), isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      await _saveAndDrain(tester);
      expect(f.provider.goals, hasLength(1));
      expect(f.provider.goals.single.title, 'Synthetic goal');
      expect(find.text('Editor parent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Covered retained Goal save cannot persist or pop a newer route',
    (tester) async {
      final f = await _pumpEditor(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Synthetic covered goal',
      );
      final callback = tester.widget<IconButton>(_saveButton()).onPressed!;
      unawaited(
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Newer Goal route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        callback();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(f.store.writes, 0);
      expect(f.provider.goals, isEmpty);
      expect(find.text('Newer Goal route'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Retained Goal save rejects a reset on the same provider', (
    tester,
  ) async {
    final f = await _pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Old account draft');
    final callback = tester.widget<IconButton>(_saveButton()).onPressed!;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    f.provider.resetLocalState();
    await tester.pump();
    await tester.runAsync(() async {
      callback();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(f.store.writes, 0);
    expect(f.provider.goals, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Goal icon picker changes language without losing the draft', (
    tester,
  ) async {
    final f = await _pumpEditor(tester);
    final state = tester.state(find.byType(GoalEditScreen));
    final title = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    await tester.enterText(find.byType(TextField).first, 'Literal / 自定义 goal');
    await _openIcons(tester);
    final scrollable = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    final gridState = tester.state(scrollable);
    for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(tester.state(scrollable), same(gridState));
      expect(tester.state(find.byType(GoalEditScreen)), same(state));
      expect(title.text, 'Literal / 自定义 goal');
      expect(
        find.text(locale == AppLocale.en ? 'Choose an icon' : '选择图标'),
        findsOneWidget,
      );
      if (locale == AppLocale.en) {
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Text),
          ),
        )) {
          expect(text.data ?? '', isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        }
      }
    }
    await tester.tap(_iconChoice('Target'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.ancestor(of: find.text('Target'), matching: find.byType(InkWell)),
      findsOneWidget,
    );
    expect(title.text, 'Literal / 自定义 goal');
    expect(f.store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retained Goal icon choice rejects an account reset', (
    tester,
  ) async {
    final f = await _pumpEditor(tester);
    await _openIcons(tester);
    final choose = tester.widget<InkWell>(_iconChoice('靶心')).onTap!;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    f.provider.resetLocalState();
    await tester.runAsync(AccountLocalDataCleaner.clearSharedPreferences);
    choose();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(f.store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retained Goal icon choice cannot pop a covering route', (
    tester,
  ) async {
    final f = await _pumpEditor(tester);
    await _openIcons(tester);
    final choose = tester.widget<InkWell>(_iconChoice('靶心')).onTap!;
    unawaited(
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering icon picker')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    choose();
    await tester.pumpAndSettle();
    expect(find.text('Covering icon picker'), findsOneWidget);
    expect(f.store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retained Goal icon opener and choice ignore lock', (
    tester,
  ) async {
    final f = await _pumpEditor(tester);
    final iconField = find.ancestor(
      of: find.text('旗帜'),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(iconField);
    final open = tester.widget<InkWell>(iconField).onTap!;
    f.lock.setLocked(true);
    open();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    f.lock.setLocked(false);
    open();
    await tester.pumpAndSettle();
    final choose = tester.widget<InkWell>(_iconChoice('靶心')).onTap!;
    f.lock.setLocked(true);
    choose();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    f.lock.setLocked(false);
    choose();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('靶心'), findsOneWidget);
    expect(f.store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 844), const Size(568, 320)]) {
    testWidgets('English Goal icon grid fits $size with large text', (
      tester,
    ) async {
      I18n.setLocale(AppLocale.en);
      await _pumpEditor(tester, size: size, textScale: 1.6);
      await _openIcons(tester);
      expect(find.text('Choose an icon'), findsOneWidget);
      final choice = _iconChoice('Target');
      expect(choice, findsOneWidget);
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        grid.gridDelegate,
        isA<SliverGridDelegateWithMaxCrossAxisExtent>(),
      );
      expect(tester.getRect(choice).width, greaterThan(90));
      expect(tester.takeException(), isNull);
      if (_captureGoalIcons) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('goal_editor_evidence')),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final path = File(
            'evidence/screenshots/goal-icons-20261013/v50/en-${size.width.toInt()}x${size.height.toInt()}-large.png',
          );
          path.parent.createSync(recursive: true);
          path.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  for (final covered in [false, true]) {
    testWidgets(
      'Milestone edits during held save remain pending on a ${covered ? 'covered' : 'current'} route',
      (tester) async {
        final f = await _pumpEditor(tester);
        await tester.enterText(find.byType(TextField).first, 'Held goal');
        addTearDown(() async {
          await tester.runAsync(() async {
            if (!f.store.release.isCompleted) f.store.release.complete();
            await AccountPreferenceWrites.drain();
          });
        });
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('里程碑与进度'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('里程碑与进度'));
        await tester.pumpAndSettle();
        final milestoneField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '添加里程碑',
        );
        await tester.ensureVisible(milestoneField);
        await tester.enterText(milestoneField, 'Submitted step');
        await tester.ensureVisible(find.byIcon(Icons.add));
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        final save = tester.widget<IconButton>(_saveButton()).onPressed!;
        await tester.runAsync(() async {
          f.store.armHold();
          save();
          await f.store.started.future.timeout(const Duration(seconds: 5));
        });
        await tester.pump();
        await tester.enterText(milestoneField, 'Step added during saving');
        await tester.ensureVisible(find.byIcon(Icons.add));
        await tester.tap(find.byIcon(Icons.add));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        if (covered) {
          unawaited(
            f.navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Cover pending save')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          f.store.release.complete();
          await AccountPreferenceWrites.drain();
        });
        await tester.pumpAndSettle();
        if (covered) {
          expect(find.text('Cover pending save'), findsOneWidget);
        } else {
          expect(find.byType(GoalEditScreen), findsOneWidget);
          expect(find.byType(SnackBar), findsOneWidget);
          I18n.setLocale(AppLocale.en);
          await tester.pump();
          expect(_feedback(tester), isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        }
        expect(f.provider.goals.single.milestones.map((m) => m.title), [
          'Submitted step',
        ]);
        final id = f.provider.goals.single.id;
        if (covered) {
          f.navigator.currentState!.pop();
          await tester.pumpAndSettle();
        }
        await _saveAndDrain(tester);
        expect(f.store.writes, 2);
        expect(f.provider.goals.single.id, id);
        expect(f.provider.goals.single.milestones.map((m) => m.title), [
          'Submitted step',
          'Step added during saving',
        ]);
        expect(find.text('Editor parent'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _saveButton() => find.ancestor(
  of: find.byIcon(Icons.check),
  matching: find.byType(IconButton),
);

Finder _iconChoice(String label) => find.ancestor(
  of: find.descendant(of: find.byType(BottomSheet), matching: find.text(label)),
  matching: find.byType(InkWell),
);

Future<void> _openIcons(WidgetTester tester) async {
  final label = I18n.current == AppLocale.en ? 'Flag' : '旗帜';
  final icon = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  await tester.ensureVisible(icon);
  await tester.pumpAndSettle();
  await tester.tap(icon);
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
}

bool get _captureGoalIcons =>
    Platform.environment['DUOYI_CAPTURE_GOAL_ICON_SCREENSHOTS'] == '1';

Future<void> _saveAndDrain(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(_saveButton());
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pumpAndSettle();
}

String _feedback(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(of: find.byType(SnackBar), matching: find.byType(Text))
          .first,
    )
    .data!;

class _EditorFixture {
  final provider = GoalProvider();
  final sounds = CustomFocusSoundProvider();
  final store = _GoalStore();
  final navigator = GlobalKey<NavigatorState>();
  final lock = _EditorLock();
}

Future<_EditorFixture> _pumpEditor(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  GoalItem? initialGoal,
}) async {
  final f = _EditorFixture();
  if (_captureGoalIcons) await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final baseTheme = AppBrands.defaultBrand.theme;
  final theme = _captureGoalIcons
      ? baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
          primaryTextTheme: baseTheme.primaryTextTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
        )
      : baseTheme;
  SharedPreferencesStorePlatform.instance = f.store;
  await tester.runAsync(f.provider.loadFromStorage);
  if (initialGoal != null) {
    await tester.runAsync(() => f.provider.add(initialGoal));
    f.store.writes = 0;
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    f.provider.dispose();
    f.sounds.dispose();
    f.lock.dispose();
    tester.view.reset();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GoalProvider>.value(value: f.provider),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(value: f.sounds),
        ChangeNotifierProvider<AppLockProvider>.value(value: f.lock),
      ],
      child: MaterialApp(
        navigatorKey: f.navigator,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(
            key: const ValueKey('goal_editor_evidence'),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GoalEditScreen(goal: initialGoal),
                ),
              ),
              child: const Text('Editor parent'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Editor parent'));
  await tester.pumpAndSettle();
  expect(find.byType(GoalEditScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
  return f;
}

class _EditorLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _GoalStore extends InMemorySharedPreferencesStore {
  _GoalStore() : super.withData({});
  bool rejectOnce = false;
  bool holdNext = false;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();
  int writes = 0;

  void armHold() {
    holdNext = true;
    started = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_goals') {
      writes++;
      if (holdNext) {
        holdNext = false;
        started.complete();
        await release.future;
      }
      await super.setValue(type, key, value);
      if (rejectOnce) {
        rejectOnce = false;
        return false;
      }
      return true;
    }
    return super.setValue(type, key, value);
  }
}
