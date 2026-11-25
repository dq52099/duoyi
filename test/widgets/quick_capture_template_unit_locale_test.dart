import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/quick_capture_ui_copy.dart';
import 'package:duoyi/models/quick_capture_template.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(previousLocale));

  testWidgets(
    'generated habit unit hint follows count and locale while editor drafts survive zh-en-zh and save as null',
    (tester) async {
      final templates = QuickCaptureTemplateProvider();
      final fixture = await _mount(tester, templates);
      await _openHabitTemplateEditor(tester);
      final screenshotDirectory =
          Platform.environment['DUOYI_SHARE_SCREENSHOT_DIR'];

      final name = _field(tester, 'quick.template.name');
      final prefix = _field(tester, 'quick.template.prefix');
      final tags = _field(tester, QuickCaptureUiCopy.templateTagsLabel);
      final category = _field(tester, 'quick.template.habit_category');
      final target = _field(tester, 'quick.template.habit_target');
      final unit = _field(tester, 'quick.template.habit_unit');
      final controllers = [
        name.controller!,
        prefix.controller!,
        tags.controller!,
        category.controller!,
        target.controller!,
        unit.controller!,
      ];

      await tester.enterText(
        _fieldFinder('quick.template.name'),
        'Draft template',
      );
      await tester.enterText(_fieldFinder('quick.template.prefix'), '每日');
      await tester.enterText(
        _fieldFinder(QuickCaptureUiCopy.templateTagsLabel),
        '原始标签',
      );
      await tester.enterText(
        _fieldFinder('quick.template.habit_category'),
        '原始分组',
      );
      await tester.enterText(_fieldFinder('quick.template.habit_target'), '1');
      await tester.pump();
      category.controller!.selection = const TextSelection.collapsed(offset: 2);

      expect(unit.controller!.text, isEmpty);
      expect(unit.decoration!.hintText, '次');
      expect(
        unit.decoration!.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(find.text('次'), findsOneWidget);
      _expectHabitSelected(tester, true);
      if (screenshotDirectory != null) {
        await _captureScreenshot(
          tester,
          fixture.screenshotKey,
          screenshotDirectory,
          'quick-capture-habit-template-zh-320-scale-1.6.png',
        );
      }

      final categorySelection = category.controller!.selection;
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectDraftControllers(
        tester,
        controllers,
        categorySelection: categorySelection,
      );
      expect(
        _field(tester, 'quick.template.habit_unit').decoration!.hintText,
        'time',
      );
      _expectHabitSelected(tester, true);

      await tester.enterText(_fieldFinder('quick.template.habit_target'), '2');
      await tester.pump();
      expect(
        _field(tester, 'quick.template.habit_unit').decoration!.hintText,
        'times',
      );
      expect(find.text('times'), findsOneWidget);
      final targetSelection = target.controller!.selection;
      if (screenshotDirectory != null) {
        await _captureScreenshot(
          tester,
          fixture.screenshotKey,
          screenshotDirectory,
          'quick-capture-habit-template-en-320-scale-1.6.png',
        );
      }

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      _expectDraftControllers(
        tester,
        controllers,
        categorySelection: categorySelection,
        targetSelection: targetSelection,
        targetText: '2',
      );
      expect(
        _field(tester, 'quick.template.habit_unit').decoration!.hintText,
        '次',
      );
      _expectHabitSelected(tester, true);

      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pumpAndSettle();

      expect(templates.customTemplates, hasLength(1));
      final saved = templates.customTemplates.single;
      expect(saved.name, 'Draft template');
      expect(saved.titlePrefix, '每日');
      expect(saved.tags, ['原始标签']);
      expect(saved.habitCategory, '原始分组');
      expect(saved.habitTargetCount, 2);
      expect(saved.habitUnit, isNull);

      final preferences = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(preferences.getString('duoyi_quick_capture_templates_v1')!)
              as List<dynamic>;
      expect((persisted.single as Map<String, dynamic>)['habitUnit'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clearing a custom habit unit restores the generated hint and authored 次 remains literal',
    (tester) async {
      final templates = QuickCaptureTemplateProvider();
      await _mount(tester, templates);
      await _openHabitTemplateEditor(tester);

      await tester.enterText(
        _fieldFinder('quick.template.name'),
        'Literal unit',
      );
      await tester.enterText(_fieldFinder('quick.template.habit_target'), '2');
      await tester.pump();
      final unitFinder = _fieldFinder('quick.template.habit_unit');
      await tester.enterText(unitFinder, '次');
      final unitController = _field(
        tester,
        'quick.template.habit_unit',
      ).controller!;

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        _field(tester, 'quick.template.habit_unit').controller,
        same(unitController),
      );
      expect(unitController.text, '次');

      await tester.enterText(unitFinder, '');
      expect(unitController.text, isEmpty);
      expect(
        _field(tester, 'quick.template.habit_unit').decoration!.hintText,
        'times',
      );
      await tester.enterText(_fieldFinder('quick.template.habit_target'), '1');
      await tester.pump();
      expect(
        _field(tester, 'quick.template.habit_unit').decoration!.hintText,
        'time',
      );
      await tester.enterText(_fieldFinder('quick.template.habit_target'), '2');
      await tester.pump();
      expect(
        _field(tester, 'quick.template.habit_unit').decoration!.hintText,
        'times',
      );

      await tester.enterText(unitFinder, '次');
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(
        _field(tester, 'quick.template.habit_unit').controller,
        same(unitController),
      );
      expect(unitController.text, '次');
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(unitController.text, '次');

      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pumpAndSettle();

      expect(templates.customTemplates, hasLength(1));
      expect(templates.customTemplates.single.habitUnit, '次');
      expect(
        QuickCaptureUiCopy.templateSummary(templates.customTemplates.single),
        'Habit · 2 次',
      );
      final preferences = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(preferences.getString('duoyi_quick_capture_templates_v1')!)
              as List<dynamic>;
      expect((persisted.single as Map<String, dynamic>)['habitUnit'], '次');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held template save from the previous account cannot publish after invalidation',
    (tester) async {
      final templates = _HeldTemplates();
      await _mount(tester, templates);
      await _openHabitTemplateEditor(tester);
      await tester.enterText(
        _fieldFinder('quick.template.name'),
        'Old account draft',
      );

      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pump();
      await templates.saveStarted.future;
      expect(templates.saveAttempts, hasLength(1));

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('quick.template.save')), findsNothing);
      expect(find.text('home screen'), findsOneWidget);

      templates.saveRelease.complete();
      await templates.saveFinished.future;
      await tester.pumpAndSettle();

      expect(templates.saved, isEmpty);
      expect(templates.customTemplates, isEmpty);
      expect(find.text(I18n.tr('quick.template.save')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_QuickCaptureFixture> _mount(
  WidgetTester tester,
  QuickCaptureTemplateProvider templates,
) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWeeklyReviewScreenshotFonts);

  final notes = NoteProvider();
  final ai = AiService();
  final routeGate = AppAccessRouteGate();
  final screenshotKey = GlobalKey();
  final fixture = _QuickCaptureFixture(
    templates: templates,
    notes: notes,
    ai: ai,
    routeGate: routeGate,
    screenshotKey: screenshotKey,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<AiService>.value(value: ai),
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: templates,
        ),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        navigatorObservers: [routeGate],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: RepaintBoundary(
            key: screenshotKey,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: child!,
            ),
          ),
        ),
        home: Scaffold(
          body: const Center(child: Text('home screen')),
          floatingActionButton: const QuickCaptureFab(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => fixture.dispose(tester));
  return fixture;
}

Future<void> _openHabitTemplateEditor(WidgetTester tester) async {
  await tester.tap(_mainFab());
  await tester.pumpAndSettle();
  await tester.tap(find.text(I18n.tr('quick.menu.template')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(OutlinedButton, I18n.tr('quick.template.save')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(I18n.tr('quick.template.kind.habit')));
  await tester.pumpAndSettle();
}

Finder _mainFab() => find.byWidgetPredicate(
  (widget) =>
      widget is FloatingActionButton && widget.heroTag == 'quick_capture',
);

Finder _fieldFinder(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText ==
          (label.startsWith('quick.template.') ? I18n.tr(label) : label),
);

TextField _field(WidgetTester tester, String label) =>
    tester.widget<TextField>(_fieldFinder(label));

void _expectDraftControllers(
  WidgetTester tester,
  List<TextEditingController> controllers, {
  TextSelection? categorySelection,
  TextSelection? targetSelection,
  String targetText = '1',
}) {
  final labels = [
    I18n.tr('quick.template.name'),
    I18n.tr('quick.template.prefix'),
    QuickCaptureUiCopy.templateTagsLabel,
    I18n.tr('quick.template.habit_category'),
    I18n.tr('quick.template.habit_target'),
    I18n.tr('quick.template.habit_unit'),
  ];
  final fields = [for (final label in labels) _field(tester, label)];
  expect(fields.map((field) => field.controller), orderedEquals(controllers));
  expect(fields.map((field) => field.controller!.text), [
    'Draft template',
    '每日',
    '原始标签',
    '原始分组',
    targetText,
    '',
  ]);
  if (categorySelection != null) {
    expect(fields[3].controller!.selection, categorySelection);
  }
  if (targetSelection != null) {
    expect(fields[4].controller!.selection, targetSelection);
  }
}

void _expectHabitSelected(WidgetTester tester, bool selected) {
  final label = find.text(I18n.tr('quick.template.kind.habit'));
  final chip = find.ancestor(of: label, matching: find.byType(ChoiceChip));
  expect(chip, findsOneWidget);
  expect(tester.widget<ChoiceChip>(chip).selected, selected);
}

class _QuickCaptureFixture {
  const _QuickCaptureFixture({
    required this.templates,
    required this.notes,
    required this.ai,
    required this.routeGate,
    required this.screenshotKey,
  });

  final QuickCaptureTemplateProvider templates;
  final NoteProvider notes;
  final AiService ai;
  final AppAccessRouteGate routeGate;
  final GlobalKey screenshotKey;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    routeGate.dispose();
    notes.dispose();
    ai.dispose();
    templates.dispose();
  }
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String directory,
  String fileName,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$fileName');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _HeldTemplates extends QuickCaptureTemplateProvider {
  final saveStarted = Completer<void>();
  final saveRelease = Completer<void>();
  final saveFinished = Completer<void>();
  final saveAttempts = <QuickCaptureTemplate>[];
  final saved = <QuickCaptureTemplate>[];

  @override
  List<QuickCaptureTemplate> get customTemplates => const [];

  @override
  List<QuickCaptureTemplate> get templates => QuickCaptureTemplate.builtIns();

  @override
  Future<void> saveTemplate(QuickCaptureTemplate template) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    saveAttempts.add(template);
    saveStarted.complete();
    try {
      await saveRelease.future;
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        throw const AccountPreferenceWriteCanceled();
      }
      saved.add(template);
    } finally {
      saveFinished.complete();
    }
  }
}
