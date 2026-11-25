import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

enum _DetailObject { note, goal }

enum _ContractOutcome { discard, save }

class _BrandPriorityScenario {
  final String name;
  final _DetailObject object;
  final String initialBrand;
  final String targetBrand;
  final AppLocale locale;
  final Size size;
  final TextScaler scaler;
  final double scaleFactor;
  final _ContractOutcome outcome;

  const _BrandPriorityScenario({
    required this.name,
    required this.object,
    required this.initialBrand,
    required this.targetBrand,
    required this.locale,
    required this.size,
    required this.scaler,
    required this.scaleFactor,
    required this.outcome,
  });

  String get probeName => 'note-goal-$name';
}

const _scenarios = <_BrandPriorityScenario>[
  // Scenario 1: Note forward roundtrip, zh, 1.0x portrait, discard contract
  _BrandPriorityScenario(
    name: 'note-roundtrip-zh-100-discard',
    object: _DetailObject.note,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    locale: AppLocale.zh,
    size: Size(390, 844),
    scaler: TextScaler.noScaling,
    scaleFactor: 1.0,
    outcome: _ContractOutcome.discard,
  ),
  // Scenario 2: Note forward roundtrip, en, 2.0x short landscape 568x320, save contract
  _BrandPriorityScenario(
    name: 'note-roundtrip-en-200-landscape-save',
    object: _DetailObject.note,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    locale: AppLocale.en,
    size: Size(568, 320),
    scaler: TextScaler.linear(2.0),
    scaleFactor: 2.0,
    outcome: _ContractOutcome.save,
  ),
  // Scenario 3: Goal forward roundtrip with milestone/progress edit, zh, 1.0x portrait, discard contract
  _BrandPriorityScenario(
    name: 'goal-roundtrip-zh-100-discard',
    object: _DetailObject.goal,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    locale: AppLocale.zh,
    size: Size(390, 844),
    scaler: TextScaler.noScaling,
    scaleFactor: 1.0,
    outcome: _ContractOutcome.discard,
  ),
  // Scenario 4: Goal forward roundtrip with milestone/progress edit, en, 2.0x portrait 320x844, save contract
  _BrandPriorityScenario(
    name: 'goal-roundtrip-en-200-save',
    object: _DetailObject.goal,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    locale: AppLocale.en,
    size: Size(320, 844),
    scaler: TextScaler.linear(2.0),
    scaleFactor: 2.0,
    outcome: _ContractOutcome.save,
  ),
  // Scenario 5: Note reverse roundtrip (liquidGlass -> defaultBrand -> liquidGlass), en, 1.0x portrait, save contract
  _BrandPriorityScenario(
    name: 'note-reverse-en-100-save',
    object: _DetailObject.note,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    locale: AppLocale.en,
    size: Size(390, 844),
    scaler: TextScaler.noScaling,
    scaleFactor: 1.0,
    outcome: _ContractOutcome.save,
  ),
  // Scenario 6: Goal reverse roundtrip (liquidGlass -> defaultBrand -> liquidGlass), zh, 2.0x short landscape 568x320, discard contract
  _BrandPriorityScenario(
    name: 'goal-reverse-zh-200-landscape-discard',
    object: _DetailObject.goal,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    locale: AppLocale.zh,
    size: Size(568, 320),
    scaler: TextScaler.linear(2.0),
    scaleFactor: 2.0,
    outcome: _ContractOutcome.discard,
  ),
];

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int noteWrites = 0;
  int noteRemoves = 0;
  int goalWrites = 0;
  int goalRemoves = 0;

  bool _isNoteKey(String key) =>
      key == 'flutter.duoyi_notes' ||
      key == 'duoyi_notes' ||
      key.endsWith('duoyi_notes');

  bool _isGoalKey(String key) =>
      key == 'flutter.duoyi_goals' ||
      key == 'duoyi_goals' ||
      key.endsWith('duoyi_goals');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isNoteKey(key)) noteWrites++;
    if (_isGoalKey(key)) goalWrites++;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isNoteKey(key)) noteRemoves++;
    if (_isGoalKey(key)) goalRemoves++;
    return super.remove(key);
  }
}

Future<void> _pumpAndSettle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

class _NoteGoalPriorityProbe extends RouteRenderProbe {
  _NoteGoalPriorityProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> capture(String stage) async {
    await super.capture(stage);
    final explicitDir =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    final captureEnabled =
        Platform.environment['DUOYI_CAPTURE_NOTE_GOAL_BRAND'] == '1' ||
        (explicitDir != null && explicitDir.isNotEmpty);
    if (!captureEnabled) return;

    final targetDir = (explicitDir != null && explicitDir.isNotEmpty)
        ? explicitDir
        : 'evidence/screenshots/widget-live-parallel-20261023/note-goal-brand';

    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('$targetDir/$name-$stage.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

Future<void> _scrollToMilestones(WidgetTester tester, Finder route) async {
  final sectionTitle = find.descendant(
    of: route,
    matching: find.text(
      I18n.current == AppLocale.en ? 'Milestones and progress' : '里程碑与进度',
    ),
  );
  final scrollable = find
      .descendant(
        of: find.descendant(of: route, matching: find.byType(ListView)),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    sectionTitle,
    200,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await _pumpAndSettle(tester);
  // ListView can dispose an offscreen expansion after the probe returns to
  // the title. Reopen it through the UI before inspecting the retained draft.
  if (find
      .descendant(of: route, matching: find.byType(CheckboxListTile))
      .evaluate()
      .isEmpty) {
    await tester.tap(sectionTitle);
    await _pumpAndSettle(tester);
  }
  final position = tester.state<ScrollableState>(scrollable).position;
  for (
    var step = 0;
    step < 30 && find.byType(CheckboxListTile).evaluate().isEmpty;
    step++
  ) {
    position.jumpTo(
      (position.pixels + position.viewportDimension * 0.6).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await _pumpAndSettle(tester);
  }
  final checkbox = find.descendant(
    of: route,
    matching: find.byType(CheckboxListTile),
  );
  expect(checkbox, findsOneWidget);
  await tester.ensureVisible(checkbox);
  await _pumpAndSettle(tester);
}

Future<void> _scrollToTop(WidgetTester tester, Finder route) async {
  final scrollable = find
      .descendant(
        of: find.descendant(of: route, matching: find.byType(ListView)),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await _pumpAndSettle(tester);
}

void _expectDateTextFits(WidgetTester tester) {
  for (final key in ['goal_start_date_field', 'goal_target_date_field']) {
    final field = find.byKey(ValueKey(key));
    if (field.evaluate().isEmpty) continue;
    final fieldElement = tester.element(field);
    for (final element
        in find
            .descendant(of: field, matching: find.byType(RichText))
            .evaluate()) {
      var isIcon = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is Icon) isIcon = true;
        return !isIcon && !identical(ancestor, fieldElement);
      });
      if (isIcon) continue;
      final paragraph = element.renderObject! as RenderParagraph;
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        locale: paragraph.locale,
        maxLines: paragraph.maxLines,
        ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
      )..layout(maxWidth: paragraph.size.width);
      expect(
        painter.didExceedMaxLines,
        isFalse,
        reason:
            '$key must display the full date label/value: ${paragraph.text.toPlainText()}',
      );
      expect(
        painter.height,
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason: '$key must not clip wrapped date text vertically',
      );
      expect(
        paragraph.textScaler.scale(11),
        closeTo(MediaQuery.textScalerOf(fieldElement).scale(11), 0.01),
        reason: '$key preserves requested text scaling',
      );
      expect(
        paragraph.text.style?.fontSize ??
            DefaultTextStyle.of(element).style.fontSize ??
            14,
        greaterThanOrEqualTo(11),
        reason: '$key must not shrink its existing date typography',
      );
      painter.dispose();
    }
  }
}

void main() {
  for (final scenario in _scenarios) {
    testWidgets(
      'Live brand priority roundtrip retains draft and route: ${scenario.name}',
      (tester) async {
        final previousShadows = debugDisableShadows;
        final initialLocale = I18n.current;

        SharedPreferencesStorePlatform? originalStore;
        NoteProvider? notes;
        GoalProvider? goals;
        CustomFocusSoundProvider? sounds;
        ThemeProvider? theme;
        AuthProvider? auth;
        ShareProvider? share;
        PomodoroProvider? pomodoro;
        PreferencesProvider? preferences;

        try {
          debugDisableShadows = false;

          final date = DateTime(2026, 6, 29);
          final note = NoteItem(
            id: 'note/synthetic-widget-note-1',
            content: '# Original Note 原始便签\nInitial note body content 初始正文',
            createdAt: date,
            updatedAt: date,
          );
          final goal = GoalItem(
            id: 'goal/synthetic-widget-goal-1',
            title: 'Original Goal 原始目标',
            description: 'Initial goal description 初始说明',
            startDate: DateTime(2026, 6, 29),
            targetDate: DateTime(2026, 12, 31),
            autoProgress: false,
            progress: 0.25,
            milestones: [
              GoalMilestone(
                id: 'm1',
                title: 'Initial milestone 初始里程碑',
                isCompleted: false,
              ),
            ],
            createdAt: date,
            updatedAt: date,
          );

          final storedNotes = [jsonEncode(note.toJson())];
          final storedGoals = [jsonEncode(goal.toJson())];

          final rawMockData = <String, Object>{
            'active_brand': scenario.initialBrand,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'duoyi_notes': storedNotes,
            'duoyi_goals': storedGoals,
          };
          SharedPreferences.setMockInitialValues(rawMockData);

          final recordingStore = _RecordingPreferencesStore({
            for (final entry in rawMockData.entries)
              'flutter.${entry.key}': entry.value,
          });
          originalStore = SharedPreferencesStorePlatform.instance;
          SharedPreferencesStorePlatform.instance = recordingStore;

          I18n.setLocale(scenario.locale);

          notes = NoteProvider();
          goals = GoalProvider();
          sounds = CustomFocusSoundProvider();
          theme = ThemeProvider();
          auth = AuthProvider();
          share = ShareProvider();
          pomodoro = PomodoroProvider();
          preferences = PreferencesProvider();

          await notes.loadFromStorage();
          await goals.loadFromStorage();
          await tester.runAsync(() async {
            await theme!.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });

          expect(theme.brand.id, scenario.initialBrand);
          expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();
          final probe = _NoteGoalPriorityProbe(
            tester,
            boundary,
            scenario.probeName,
          );

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<NoteProvider>.value(value: notes),
                ChangeNotifierProvider<GoalProvider>.value(value: goals),
                ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                  value: sounds,
                ),
                ChangeNotifierProvider<ShareProvider>.value(value: share),
                ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: AnimatedBuilder(
                animation: Listenable.merge([theme, I18n.localeListenable]),
                builder: (context, _) => MaterialApp(
                  locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme!.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: scenario.scaler),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => TodayDetailRouter.open(
                            context,
                            scenario.object == _DetailObject.note
                                ? TodaySectionKind.notes
                                : TodaySectionKind.goals,
                            id: scenario.object == _DetailObject.note
                                ? note.id
                                : goal.id,
                          ),
                          child: const Text('Open object'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _pumpAndSettle(tester);

          await tester.tap(find.text('Open object'));
          await _pumpAndSettle(tester);

          final route = scenario.object == _DetailObject.note
              ? find.byType(NoteEditScreen)
              : find.byType(GoalEditScreen);
          expect(route, findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          expect(find.byType(BrandBackground), findsOneWidget);

          final initialRouteState = tester.state(route);
          final initialModalRoute = ModalRoute.of(tester.element(route));
          expect(initialModalRoute, isNotNull);
          expect(tester.takeException(), isNull);

          final initialCs = Theme.of(tester.element(route)).colorScheme;
          expect(
            initialCs.primary,
            equals(
              AppBrands.byId(scenario.initialBrand).theme.colorScheme.primary,
            ),
          );

          // Snapshot baseline writes and provider storage generations
          final initialNoteWrites = recordingStore.noteWrites;
          final initialNoteRemoves = recordingStore.noteRemoves;
          final initialGoalWrites = recordingStore.goalWrites;
          final initialGoalRemoves = recordingStore.goalRemoves;
          final initialNoteGeneration = notes.storageGeneration;
          final initialGoalGeneration = goals.storageGeneration;

          final prefs = await SharedPreferences.getInstance();

          void assertZeroImplicitWrites() {
            expect(recordingStore.noteWrites, initialNoteWrites);
            expect(recordingStore.noteRemoves, initialNoteRemoves);
            expect(recordingStore.goalWrites, initialGoalWrites);
            expect(recordingStore.goalRemoves, initialGoalRemoves);
            expect(notes!.storageGeneration, initialNoteGeneration);
            expect(goals!.storageGeneration, initialGoalGeneration);
            expect(prefs.getStringList('duoyi_notes'), storedNotes);
            expect(prefs.getStringList('duoyi_goals'), storedGoals);
            expect(notes.notes.single.toJson(), note.toJson());
            expect(goals.goals.single.toJson(), goal.toJson());
          }

          final field = find
              .descendant(of: route, matching: find.byType(TextField))
              .first;
          await tester.ensureVisible(field);
          var fieldElement = tester.element(field);

          const editedNoteDraft =
              '# Edited Draft 便签草稿\nDraft body content for theme switch test';
          const editedGoalTitle = 'Edited Goal Title 编辑目标草稿';

          TextEditingController? noteController;
          TextEditingController? goalTitleController;

          if (scenario.object == _DetailObject.note) {
            await tester.enterText(field, editedNoteDraft);
            noteController = tester.widget<TextField>(field).controller!;
            noteController.selection = const TextSelection(
              baseOffset: 2,
              extentOffset: 8,
            );
          } else {
            await tester.enterText(field, editedGoalTitle);
            goalTitleController = tester.widget<TextField>(field).controller!;
            goalTitleController.selection = const TextSelection(
              baseOffset: 2,
              extentOffset: 8,
            );

            await _scrollToMilestones(tester, route);
            final milestoneCheckbox = find.descendant(
              of: route,
              matching: find.byType(CheckboxListTile),
            );
            expect(milestoneCheckbox, findsOneWidget);
            expect(
              tester.widget<CheckboxListTile>(milestoneCheckbox).value,
              isFalse,
            );
            await tester.tap(milestoneCheckbox);
            await _pumpAndSettle(tester);
            expect(
              tester.widget<CheckboxListTile>(milestoneCheckbox).value,
              isTrue,
            );

            await _scrollToTop(tester, route);
            if (scenario.scaleFactor >= 2.0) {
              _expectDateTextFits(tester);
            }
          }

          await _pumpAndSettle(tester);
          assertZeroImplicitWrites();
          await probe.capture('01-initial-draft');
          fieldElement = tester.element(field);

          // Live brand switch 1: scenario.initialBrand -> scenario.targetBrand
          await tester.runAsync(() async {
            final switched = await theme!.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.targetBrand);
          expect(prefs.getString('active_brand'), scenario.targetBrand);

          final switchedCs = Theme.of(tester.element(route)).colorScheme;
          expect(
            switchedCs.primary,
            equals(
              AppBrands.byId(scenario.targetBrand).theme.colorScheme.primary,
            ),
          );

          expect(tester.state(route), same(initialRouteState));
          expect(ModalRoute.of(tester.element(route)), same(initialModalRoute));
          expect(tester.element(field), same(fieldElement));

          if (scenario.object == _DetailObject.note) {
            expect(tester.element(field), same(fieldElement));
            expect(
              tester.widget<TextField>(field).controller,
              same(noteController),
            );
            expect(noteController!.text, editedNoteDraft);
            expect(
              noteController.selection,
              const TextSelection(baseOffset: 2, extentOffset: 8),
            );
          } else {
            // Unconditionally reveal and assert milestone checkbox retained as true
            await _scrollToMilestones(tester, route);
            final milestoneAfterSwitch1 = find.descendant(
              of: route,
              matching: find.byType(CheckboxListTile),
            );
            expect(milestoneAfterSwitch1, findsOneWidget);
            expect(
              tester.widget<CheckboxListTile>(milestoneAfterSwitch1).value,
              isTrue,
            );
            // Restore intended measurement position
            await _scrollToTop(tester, route);

            expect(
              tester.widget<TextField>(field).controller,
              same(goalTitleController),
            );
            expect(goalTitleController!.text, editedGoalTitle);
            expect(
              goalTitleController.selection,
              const TextSelection(baseOffset: 2, extentOffset: 8),
            );

            if (scenario.scaleFactor >= 2.0) {
              _expectDateTextFits(tester);
            }
          }

          // Zero implicit writes verified across first switch
          assertZeroImplicitWrites();
          await probe.capture('02-switched-brand');
          fieldElement = tester.element(field);

          // Live brand switch 2: scenario.targetBrand -> scenario.initialBrand (revert)
          await tester.runAsync(() async {
            final reverted = await theme!.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.initialBrand);
          expect(prefs.getString('active_brand'), scenario.initialBrand);

          final revertedCs = Theme.of(tester.element(route)).colorScheme;
          expect(
            revertedCs.primary,
            equals(
              AppBrands.byId(scenario.initialBrand).theme.colorScheme.primary,
            ),
          );

          expect(tester.state(route), same(initialRouteState));
          expect(ModalRoute.of(tester.element(route)), same(initialModalRoute));
          expect(tester.element(field), same(fieldElement));

          if (scenario.object == _DetailObject.note) {
            expect(tester.element(field), same(fieldElement));
            expect(
              tester.widget<TextField>(field).controller,
              same(noteController),
            );
            expect(noteController!.text, editedNoteDraft);
            expect(
              noteController.selection,
              const TextSelection(baseOffset: 2, extentOffset: 8),
            );
          } else {
            // Unconditionally reveal and assert milestone checkbox retained as true
            await _scrollToMilestones(tester, route);
            final milestoneAfterSwitch2 = find.descendant(
              of: route,
              matching: find.byType(CheckboxListTile),
            );
            expect(milestoneAfterSwitch2, findsOneWidget);
            expect(
              tester.widget<CheckboxListTile>(milestoneAfterSwitch2).value,
              isTrue,
            );
            // Restore intended measurement position
            await _scrollToTop(tester, route);

            expect(
              tester.widget<TextField>(field).controller,
              same(goalTitleController),
            );
            expect(goalTitleController!.text, editedGoalTitle);
            expect(
              goalTitleController.selection,
              const TextSelection(baseOffset: 2, extentOffset: 8),
            );

            if (scenario.scaleFactor >= 2.0) {
              _expectDateTextFits(tester);
            }
          }

          // Zero implicit writes verified across roundtrip revert
          assertZeroImplicitWrites();
          await probe.capture('03-reverted-brand');

          // Explicit contract outcome: Discard vs Save
          if (scenario.outcome == _ContractOutcome.discard) {
            final back = find.byType(BackButton);
            expect(back.hitTestable(), findsOneWidget);
            await tester.tap(back);
            await _pumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(find.text('Open object'), findsOneWidget);
            expect(route, findsNothing);

            // Discard contract: zero writes to stores and providers remain pristine
            assertZeroImplicitWrites();
            await probe.capture('04-discarded');
          } else {
            if (scenario.object == _DetailObject.note) {
              final saveButton = find.byKey(const ValueKey('note-editor-save'));
              expect(saveButton.hitTestable(), findsOneWidget);
              await tester.tap(saveButton);
              await _pumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              expect(find.text('Open object'), findsOneWidget);
              expect(route, findsNothing);

              // Explicit save: note store updated, goal store pristine
              expect(recordingStore.noteWrites, initialNoteWrites + 1);
              expect(recordingStore.noteRemoves, initialNoteRemoves);
              expect(recordingStore.goalWrites, initialGoalWrites);
              expect(recordingStore.goalRemoves, initialGoalRemoves);
              expect(notes.storageGeneration, initialNoteGeneration);
              expect(goals.storageGeneration, initialGoalGeneration);

              final rawNotes = prefs.getStringList('duoyi_notes');
              expect(rawNotes, isNotNull);
              expect(rawNotes, isNot(equals(storedNotes)));
              final decodedNote =
                  jsonDecode(rawNotes!.single) as Map<String, dynamic>;
              expect(decodedNote['content'], equals(editedNoteDraft));
              expect(notes.notes.single.content, equals(editedNoteDraft));
            } else {
              final goalSaveButton = find.descendant(
                of: find.byType(AppBar),
                matching: find.byIcon(Icons.check),
              );
              expect(goalSaveButton.hitTestable(), findsOneWidget);
              await tester.tap(goalSaveButton);
              await _pumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              expect(find.text('Open object'), findsOneWidget);
              expect(route, findsNothing);

              // Explicit save: goal store updated, note store pristine
              expect(recordingStore.goalWrites, initialGoalWrites + 1);
              expect(recordingStore.goalRemoves, initialGoalRemoves);
              expect(recordingStore.noteWrites, initialNoteWrites);
              expect(recordingStore.noteRemoves, initialNoteRemoves);
              expect(goals.storageGeneration, initialGoalGeneration);
              expect(notes.storageGeneration, initialNoteGeneration);

              final rawGoals = prefs.getStringList('duoyi_goals');
              expect(rawGoals, isNotNull);
              expect(rawGoals, isNot(equals(storedGoals)));
              final decodedGoal =
                  jsonDecode(rawGoals!.single) as Map<String, dynamic>;
              expect(decodedGoal['title'], equals(editedGoalTitle));
              final decodedMilestones =
                  (decodedGoal['milestones'] as List<dynamic>?)
                      ?.cast<Map<String, dynamic>>();
              expect(decodedMilestones, isNotNull);
              expect(decodedMilestones!.first['isCompleted'], isTrue);
              expect(goals.goals.single.title, equals(editedGoalTitle));
              expect(goals.goals.single.milestones.first.isCompleted, isTrue);
            }
            await probe.capture('04-saved');
          }
        } finally {
          try {
            await tester.pumpWidget(const SizedBox.shrink());
            await _pumpAndSettle(tester);
          } finally {
            debugDisableShadows = previousShadows;
            I18n.setLocale(initialLocale);
            tester.view.reset();
            SharedPreferences.resetStatic();
            if (originalStore != null) {
              SharedPreferencesStorePlatform.instance = originalStore;
            }
            notes?.dispose();
            goals?.dispose();
            sounds?.dispose();
            theme?.dispose();
            auth?.dispose();
            share?.dispose();
            pomodoro?.dispose();
            preferences?.dispose();
          }
        }
      },
    );
  }
}
