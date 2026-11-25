import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _platformAnniversariesKey = 'flutter.duoyi_anniversaries_v2';
const _storageAnniversariesKey = 'duoyi_anniversaries_v2';

enum _EditorTestCaseMode { create, edit }

class _EditorTestCaseConfig {
  final _EditorTestCaseMode mode;
  final String initialBrand;
  final String intermediateBrand;
  final String finalBrand;
  final AppLocale locale;
  final bool shouldSubmit;

  const _EditorTestCaseConfig({
    required this.mode,
    required this.initialBrand,
    required this.intermediateBrand,
    required this.finalBrand,
    required this.locale,
    required this.shouldSubmit,
  });

  String get testName {
    final modeLabel = mode == _EditorTestCaseMode.create ? 'create' : 'edit';
    final transitionLabel = '$initialBrand->$intermediateBrand->$finalBrand';
    final actionLabel = shouldSubmit ? 'submit' : 'cancel';
    return 'anniversary editor $modeLabel $transitionLabel ${locale.name} $actionLabel';
  }

  Size get screenSize => mode == _EditorTestCaseMode.create
      ? const Size(320, 844)
      : const Size(568, 320);
}

class _CountingStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _data = <String, Object>{};
  final Map<String, int> _writeCounts = <String, int>{};

  _CountingStore([Map<String, Object>? initialValues]) {
    if (initialValues != null) {
      _data.addAll(initialValues);
    }
  }

  int writeCount(String key) => _writeCounts[key] ?? 0;

  void resetWrites() => _writeCounts.clear();

  @override
  Future<bool> clear() {
    _data.clear();
    return Future.value(true);
  }

  @override
  Future<Map<String, Object>> getAll() {
    return Future.value(Map<String, Object>.from(_data));
  }

  @override
  Future<bool> remove(String key) {
    _writeCounts[key] = (_writeCounts[key] ?? 0) + 1;
    _data.remove(key);
    return Future.value(true);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    _writeCounts[key] = (_writeCounts[key] ?? 0) + 1;
    _data[key] = value;
    return Future.value(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadWeeklyReviewScreenshotFonts();
  });

  final cases = <_EditorTestCaseConfig>[
    // 4 Create mode cases (320x844, 200% font): 2 directions x 2 locales; exactly 1 positive submit, 3 cancel
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.create,
      initialBrand: 'defaultBrand',
      intermediateBrand: 'liquidGlass',
      finalBrand: 'defaultBrand',
      locale: AppLocale.zh,
      shouldSubmit: true,
    ),
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.create,
      initialBrand: 'defaultBrand',
      intermediateBrand: 'liquidGlass',
      finalBrand: 'defaultBrand',
      locale: AppLocale.en,
      shouldSubmit: false,
    ),
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.create,
      initialBrand: 'liquidGlass',
      intermediateBrand: 'defaultBrand',
      finalBrand: 'liquidGlass',
      locale: AppLocale.zh,
      shouldSubmit: false,
    ),
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.create,
      initialBrand: 'liquidGlass',
      intermediateBrand: 'defaultBrand',
      finalBrand: 'liquidGlass',
      locale: AppLocale.en,
      shouldSubmit: false,
    ),

    // 4 Edit mode cases (568x320, 200% font): 2 directions x 2 locales; exactly 1 positive submit, 3 cancel
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.edit,
      initialBrand: 'defaultBrand',
      intermediateBrand: 'liquidGlass',
      finalBrand: 'defaultBrand',
      locale: AppLocale.zh,
      shouldSubmit: true,
    ),
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.edit,
      initialBrand: 'defaultBrand',
      intermediateBrand: 'liquidGlass',
      finalBrand: 'defaultBrand',
      locale: AppLocale.en,
      shouldSubmit: false,
    ),
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.edit,
      initialBrand: 'liquidGlass',
      intermediateBrand: 'defaultBrand',
      finalBrand: 'liquidGlass',
      locale: AppLocale.zh,
      shouldSubmit: false,
    ),
    const _EditorTestCaseConfig(
      mode: _EditorTestCaseMode.edit,
      initialBrand: 'liquidGlass',
      intermediateBrand: 'defaultBrand',
      finalBrand: 'liquidGlass',
      locale: AppLocale.en,
      shouldSubmit: false,
    ),
  ];

  for (final testCase in cases) {
    testWidgets(testCase.testName, (tester) async {
      final originalLocale = I18n.current;
      addTearDown(() => I18n.setLocale(originalLocale));

      tester.view.physicalSize = testCase.screenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      I18n.setLocale(testCase.locale);

      final initialItem = testCase.mode == _EditorTestCaseMode.edit
          ? Anniversary.create(
              id: 'fixed-edit-synthetic-id',
              title: '原始测试纪念日',
              description: '原始测试说明备注',
              solarDate: DateTime(2023, 5, 20),
              type: AnniversaryType.memorial,
              calendarType: AnniversaryCalendarType.solar,
            )
          : null;

      final initialStoredList = initialItem != null
          ? [jsonEncode(initialItem.toJson())]
          : <String>[];

      // Reset mock singleton first, then install the seeded CountingStore
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = _CountingStore(<String, Object>{
        'flutter.active_brand': testCase.initialBrand,
        'flutter.theme_unlocked_brands': <String>[
          'defaultBrand',
          'liquidGlass',
        ],
        'flutter.theme_shop_state': jsonEncode(<String, dynamic>{
          'activeBrand': testCase.initialBrand,
          'unlockedBrandIds': <String>['defaultBrand', 'liquidGlass'],
        }),
        if (initialStoredList.isNotEmpty)
          _platformAnniversariesKey: List<String>.from(initialStoredList),
      });
      SharedPreferencesStorePlatform.instance = store;

      late ThemeProvider themeProvider;
      late AnniversaryProvider anniversaryProvider;
      late SharedPreferences preferences;

      // ThemeProvider construction and storage loading in real-async zone
      await tester.runAsync(() async {
        preferences = await SharedPreferences.getInstance();
        themeProvider = ThemeProvider();
        await themeProvider.loadFromStorage();
        anniversaryProvider = AnniversaryProvider();
        await anniversaryProvider.loadFromStorage();
      });

      addTearDown(() async {
        await tester.runAsync(() async {
          await AccountPreferenceWrites.drain();
        });
        anniversaryProvider.dispose();
        themeProvider.dispose();
      });

      // Clear setUp seed write counts so only test actions are tracked
      store.resetWrites();

      expect(themeProvider.isBrandUnlocked('defaultBrand'), isTrue);
      expect(themeProvider.isBrandUnlocked('liquidGlass'), isTrue);
      expect(themeProvider.brand.id, testCase.initialBrand);

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AnniversaryProvider>.value(
              value: anniversaryProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: Consumer<ThemeProvider>(
            builder: (context, theme, _) {
              return ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) {
                  return MaterialApp(
                    locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                    supportedLocales: const [Locale('en'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: theme.brand.theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(2.0)),
                      child: RepaintBoundary(key: repaintKey, child: child!),
                    ),
                    home: BrandRouteSurface(
                      child: Scaffold(
                        body: Center(
                          child: Builder(
                            builder: (buttonContext) => ElevatedButton(
                              key: const ValueKey(
                                'open_editor_launcher_button',
                              ),
                              onPressed: () {
                                showAnniversaryEditor(
                                  buttonContext,
                                  item: initialItem,
                                  fixedType:
                                      initialItem?.type ??
                                      AnniversaryType.birthday,
                                );
                              },
                              child: const Text('Launch Editor'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );

      await _pumpBounded(tester);

      // Open anniversary editor
      await tester.tap(
        find.byKey(const ValueKey('open_editor_launcher_button')),
      );
      await _pumpBounded(tester);

      final sheetFinder = find.byType(AppModalSheet);
      expect(sheetFinder, findsOneWidget);

      final sheetElement = tester.element(sheetFinder);
      final editorState = _findEditorState(sheetElement);
      expect(editorState, isNotNull);
      final sheetRoute = ModalRoute.of(sheetElement);

      expect(
        appSurfaceStyleOf(sheetElement),
        _expectedSurfaceStyle(themeProvider),
      );
      expect(
        Theme.of(sheetElement).brightness,
        themeProvider.brand.theme.brightness,
      );

      // Text input fields: Title and Note/Description
      final textFields = find.descendant(
        of: sheetFinder,
        matching: find.byType(TextField),
      );
      expect(textFields, findsAtLeastNWidgets(2));

      final titleFinder = textFields.at(0);
      final noteFinder = textFields.at(1);

      final titleController = tester.widget<TextField>(titleFinder).controller!;
      final noteController = tester.widget<TextField>(noteFinder).controller!;

      const authoredTitle = '稳定跨主题纪念日标题 Authored Title';
      const authoredNote =
          '长篇作者备注内容 Note that remains authored across live theme round trips';

      titleController.value = const TextEditingValue(
        text: authoredTitle,
        selection: TextSelection(baseOffset: 2, extentOffset: 8),
      );
      noteController.value = const TextEditingValue(
        text: authoredNote,
        selection: TextSelection(baseOffset: 4, extentOffset: 12),
      );
      await _pumpBounded(tester);

      // Calendar type selection: toggle to lunar using real widget translation key
      final calendarSegments = find.byKey(
        const ValueKey('anniversary_calendar_type_segments'),
      );
      expect(calendarSegments, findsOneWidget);
      final lunarSegment = find.descendant(
        of: calendarSegments,
        matching: find.text(I18n.tr('calendar.lunar')),
      );
      await _scrollAndTap(tester, lunarSegment);
      expect(
        tester
            .widget<SegmentedButton<AnniversaryCalendarType>>(calendarSegments)
            .selected,
        {AnniversaryCalendarType.lunar},
      );

      await _captureRetainedIfRequested(
        tester,
        repaintKey,
        testCase.testName,
        '01-initial',
      );

      // --- Live theme transition 1: initialBrand -> intermediateBrand ---
      await tester.runAsync(() async {
        final switched = await themeProvider.setBrand(
          testCase.intermediateBrand,
        );
        expect(switched, isTrue);
      });
      await _pumpThemeTransition(tester);

      expect(themeProvider.brand.id, testCase.intermediateBrand);
      final intermediateElement = tester.element(sheetFinder);
      expect(intermediateElement, same(sheetElement));
      expect(_findEditorState(intermediateElement), same(editorState));
      expect(ModalRoute.of(intermediateElement), same(sheetRoute));

      expect(
        appSurfaceStyleOf(intermediateElement),
        _expectedSurfaceStyle(themeProvider),
      );
      expect(
        Theme.of(intermediateElement).brightness,
        themeProvider.brand.theme.brightness,
      );

      // Local state preserved: controllers, text, selection, calendar type
      expect(
        tester.widget<TextField>(titleFinder).controller,
        same(titleController),
      );
      expect(
        tester.widget<TextField>(noteFinder).controller,
        same(noteController),
      );
      expect(titleController.text, authoredTitle);
      expect(
        titleController.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      expect(noteController.text, authoredNote);
      expect(
        noteController.selection,
        const TextSelection(baseOffset: 4, extentOffset: 12),
      );
      expect(
        tester
            .widget<SegmentedButton<AnniversaryCalendarType>>(calendarSegments)
            .selected,
        {AnniversaryCalendarType.lunar},
      );

      // Verify draft and state survive a live locale change round trip
      final otherLocale = testCase.locale == AppLocale.zh
          ? AppLocale.en
          : AppLocale.zh;
      I18n.setLocale(otherLocale);
      await _pumpBounded(tester);
      expect(titleController.text, authoredTitle);
      expect(
        titleController.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      expect(noteController.text, authoredNote);
      expect(
        noteController.selection,
        const TextSelection(baseOffset: 4, extentOffset: 12),
      );
      expect(
        tester
            .widget<SegmentedButton<AnniversaryCalendarType>>(calendarSegments)
            .selected,
        {AnniversaryCalendarType.lunar},
      );
      I18n.setLocale(testCase.locale);
      await _pumpBounded(tester);

      await _captureRetainedIfRequested(
        tester,
        repaintKey,
        testCase.testName,
        '02-intermediate',
      );

      // --- Live theme transition 2: intermediateBrand -> finalBrand (round trip) ---
      await tester.runAsync(() async {
        final switched = await themeProvider.setBrand(testCase.finalBrand);
        expect(switched, isTrue);
      });
      await _pumpThemeTransition(tester);

      expect(themeProvider.brand.id, testCase.finalBrand);
      final finalElement = tester.element(sheetFinder);
      expect(finalElement, same(sheetElement));
      expect(_findEditorState(finalElement), same(editorState));
      expect(ModalRoute.of(finalElement), same(sheetRoute));

      expect(
        appSurfaceStyleOf(finalElement),
        _expectedSurfaceStyle(themeProvider),
      );
      expect(
        Theme.of(finalElement).brightness,
        themeProvider.brand.theme.brightness,
      );

      // Assert preservation after completing the round trip
      expect(
        tester.widget<TextField>(titleFinder).controller,
        same(titleController),
      );
      expect(
        tester.widget<TextField>(noteFinder).controller,
        same(noteController),
      );
      expect(titleController.text, authoredTitle);
      expect(
        titleController.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      expect(noteController.text, authoredNote);
      expect(
        noteController.selection,
        const TextSelection(baseOffset: 4, extentOffset: 12),
      );
      expect(
        tester
            .widget<SegmentedButton<AnniversaryCalendarType>>(calendarSegments)
            .selected,
        {AnniversaryCalendarType.lunar},
      );

      await _captureRetainedIfRequested(
        tester,
        repaintKey,
        testCase.testName,
        '03-roundtrip',
      );

      // --- Action: Positive Submit vs Cancel Zero-Persistence ---
      if (testCase.shouldSubmit) {
        final saveButton = find.byKey(
          const ValueKey('anniversary_editor_save_button'),
        );
        await _scrollAndTap(tester, saveButton, realAsync: true);

        await tester.runAsync(() async {
          await AccountPreferenceWrites.drain();
        });
        await _pumpBounded(tester);

        expect(find.byType(AppModalSheet), findsNothing);

        // Positive submit asserts exactly 1 setValue write on platform store
        expect(store.writeCount(_platformAnniversariesKey), 1);

        if (testCase.mode == _EditorTestCaseMode.create) {
          expect(anniversaryProvider.items.length, 1);
          final created = anniversaryProvider.items.single;
          expect(created.title, authoredTitle);
          expect(created.description, authoredNote);
          expect(created.calendarType, AnniversaryCalendarType.lunar);

          final stored = preferences.getStringList(_storageAnniversariesKey);
          expect(stored, isNotNull);
          expect(stored!.length, 1);
          final map = jsonDecode(stored.first) as Map<String, dynamic>;
          expect(map['title'], authoredTitle);
          expect(map['description'], authoredNote);
        } else {
          expect(anniversaryProvider.items.length, 1);
          final updated = anniversaryProvider.items.single;
          expect(updated.id, initialItem!.id);
          expect(updated.title, authoredTitle);
          expect(updated.description, authoredNote);
          expect(updated.calendarType, AnniversaryCalendarType.lunar);

          final stored = preferences.getStringList(_storageAnniversariesKey);
          expect(stored, isNotNull);
          expect(stored!.length, 1);
          final map = jsonDecode(stored.first) as Map<String, dynamic>;
          expect(map['id'], initialItem.id);
          expect(map['title'], authoredTitle);
          expect(map['description'], authoredNote);
        }
      } else {
        final cancelButton = find.descendant(
          of: sheetFinder,
          matching: find.text(I18n.tr('action.cancel')),
        );
        await _scrollAndTap(tester, cancelButton);
        await tester.runAsync(() async {
          await AccountPreferenceWrites.drain();
        });
        await _pumpBounded(tester);

        expect(find.byType(AppModalSheet), findsNothing);

        // Cancel asserts zero setValue write on platform store
        expect(store.writeCount(_platformAnniversariesKey), 0);

        if (testCase.mode == _EditorTestCaseMode.create) {
          expect(anniversaryProvider.items, isEmpty);
          final stored = preferences.getStringList(_storageAnniversariesKey);
          expect(stored, anyOf(isNull, isEmpty));
        } else {
          expect(anniversaryProvider.items.length, 1);
          final current = anniversaryProvider.items.single;
          expect(current.title, initialItem!.title);
          expect(current.description, initialItem.description);
          expect(current.calendarType, initialItem.calendarType);

          final stored = preferences.getStringList(_storageAnniversariesKey);
          expect(stored, isNotNull);
          expect(stored!.length, 1);
          final map = jsonDecode(stored.first) as Map<String, dynamic>;
          expect(map['title'], initialItem.title);
          expect(map['description'], initialItem.description);
        }
      }

      expect(tester.takeException(), isNull);
    });
  }
}

State<StatefulWidget>? _findEditorState(Element element) {
  State<StatefulWidget>? result;
  element.visitAncestorElements((ancestor) {
    if (ancestor is StatefulElement) {
      result = ancestor.state;
      return false;
    }
    return true;
  });
  return result;
}

AppSurfaceStyle _expectedSurfaceStyle(ThemeProvider themeProvider) {
  return themeProvider.brand.theme.extension<AppSurfaceStyle>() ??
      (themeProvider.brand.id == 'liquidGlass'
          ? AppSurfaceStyle.liquidGlass
          : AppSurfaceStyle.ios);
}

Future<void> _pumpBounded(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 50),
  int maxTicks = 40,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    await tester.pump(step);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

Future<void> _pumpThemeTransition(WidgetTester tester) async {
  final totalDuration =
      kThemeAnimationDuration + const Duration(milliseconds: 100);
  const step = Duration(milliseconds: 50);
  final ticks = (totalDuration.inMilliseconds / step.inMilliseconds).ceil() + 2;
  for (var i = 0; i < ticks; i++) {
    await tester.pump(step);
  }
  await _pumpBounded(tester);
}

Future<void> _scrollAndTap(
  WidgetTester tester,
  Finder target, {
  bool realAsync = false,
}) async {
  if (target.hitTestable().evaluate().isEmpty) {
    try {
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 50));
    } catch (_) {}
  }

  // Vertical scroll down
  if (target.hitTestable().evaluate().isEmpty) {
    final verticalScrollables = find.descendant(
      of: find.byType(AppModalSheet),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    if (verticalScrollables.evaluate().isNotEmpty) {
      final scrollable = verticalScrollables.first;
      final rect = tester.getRect(scrollable);
      for (
        var attempt = 0;
        attempt < 40 && target.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.dragFrom(
          Offset(rect.left + 8, rect.center.dy),
          Offset(0, -(rect.height * 0.5).clamp(40.0, 160.0)),
        );
        await _pumpBounded(tester);
        try {
          await tester.ensureVisible(target);
          await tester.pump(const Duration(milliseconds: 50));
        } catch (_) {}
      }
    }
  }

  // Vertical scroll up
  if (target.hitTestable().evaluate().isEmpty) {
    final verticalScrollables = find.descendant(
      of: find.byType(AppModalSheet),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    if (verticalScrollables.evaluate().isNotEmpty) {
      final scrollable = verticalScrollables.first;
      final rect = tester.getRect(scrollable);
      for (
        var attempt = 0;
        attempt < 40 && target.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.dragFrom(
          Offset(rect.left + 8, rect.center.dy),
          Offset(0, (rect.height * 0.5).clamp(40.0, 160.0)),
        );
        await _pumpBounded(tester);
        try {
          await tester.ensureVisible(target);
          await tester.pump(const Duration(milliseconds: 50));
        } catch (_) {}
      }
    }
  }

  // Horizontal scroll
  if (target.hitTestable().evaluate().isEmpty) {
    final horizontalScrollables = find.descendant(
      of: find.byType(AppModalSheet),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.right ||
                widget.axisDirection == AxisDirection.left),
      ),
    );
    if (horizontalScrollables.evaluate().isNotEmpty) {
      final scrollable = horizontalScrollables.first;
      final rect = tester.getRect(scrollable);
      for (
        var attempt = 0;
        attempt < 10 && target.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.dragFrom(
          Offset(rect.right - 8, rect.center.dy),
          Offset(-(rect.width * 0.5).clamp(30.0, 120.0), 0),
        );
        await _pumpBounded(tester);
        try {
          await tester.ensureVisible(target);
          await tester.pump(const Duration(milliseconds: 50));
        } catch (_) {}
      }
    }
  }

  expect(target.hitTestable(), findsOneWidget);
  if (realAsync) {
    await tester.runAsync(() async {
      await tester.tap(target);
      await AccountPreferenceWrites.drain();
    });
  } else {
    await tester.tap(target);
  }
  await _pumpBounded(tester);
}

Future<void> _captureRetainedIfRequested(
  WidgetTester tester,
  GlobalKey repaintKey,
  String testName,
  String stage,
) async {
  final targetDir = Platform.environment['DUOYI_RETAINED_CAPTURE'];
  if (targetDir == null || targetDir.trim().isEmpty) return;

  await tester.runAsync(() async {
    ui.Image? image;
    try {
      final boundary =
          repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      expect(boundary, isNotNull);
      image = await boundary!.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(byteData, isNotNull);
      final dir = Directory(targetDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${dir.path}/$safeName-$stage.png');
      await file.writeAsBytes(byteData!.buffer.asUint8List());
    } finally {
      image?.dispose();
    }
  });
}
