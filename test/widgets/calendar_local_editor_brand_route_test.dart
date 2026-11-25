// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_event_sheet_ui_copy.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _calendarKey = 'duoyi_local_calendar_events_v1';
const _openRoute = ValueKey('open-calendar-brand-route');
const _openEditor = ValueKey('open-calendar-editor');
final _evidenceDirectory =
    Platform.environment['DUOYI_THEME_DIALOG_EVIDENCE_DIR'];

class _CalendarWriteStore extends InMemorySharedPreferencesStore {
  _CalendarWriteStore(super.data) : super.withData();

  int calendarWrites = 0;
  int calendarRemoves = 0;

  bool _isCalendarKey(String key) =>
      key == _calendarKey || key == 'flutter.$_calendarKey';

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isCalendarKey(key)) calendarWrites++;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isCalendarKey(key)) calendarRemoves++;
    return super.remove(key);
  }
}

// CalendarScreen's quick-add action supplies its page context to this same
// production function. Keep the actual pushed surface (and its local Theme),
// without loading unrelated calendar aggregation providers into this test.
class _CalendarEditorHost extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final CalendarEvent? event;

  const _CalendarEditorHost({required this.event});

  @override
  State<_CalendarEditorHost> createState() => _CalendarEditorHostState();
}

class _CalendarEditorHostState extends State<_CalendarEditorHost> {
  Future<void>? editorClosed;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calendar editor route')),
    body: Center(
      child: FilledButton(
        key: _openEditor,
        onPressed: () {
          editorClosed = showLocalCalendarEventEditor(
            context,
            initialDate: DateTime(2027, 6, 15),
            event: widget.event,
          );
        },
        child: const Text('Open editor'),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _captureBrandDialog(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String stage,
) async {
  final directory = _evidenceDirectory;
  if (directory == null || directory.isEmpty) return;

  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode calendar dialog PNG');
      final file = File('$directory/calendar-local-editor-new-$stage.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? "edit" : "new"} event follows pushed route brand roundtrip '
      'and cancels without saving',
      (tester) async {
        final previousLocale = I18n.current;
        final previousStore = SharedPreferencesStorePlatform.instance;
        late final ThemeProvider theme;
        late final CalendarProvider calendar;
        var providersCreated = false;
        final boundaryKey = GlobalKey();
        final existing = CalendarEvent(
          id: 'retained-local-event',
          title: 'Existing event',
          note: 'Existing notes',
          date: DateTime(2027, 6, 15, 10),
          endDate: DateTime(2027, 6, 15, 11),
          time: const TimeOfDay(hour: 10, minute: 0),
          type: CalendarEventType.event,
          color: const Color(0xFF26A69A),
          workspaceId: 'private',
        );
        final initialValues = <String, Object>{
          'active_brand': 'defaultBrand',
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          _calendarKey: [if (editing) jsonEncode(existing.toJson())],
        };
        SharedPreferences.setMockInitialValues(initialValues);
        final store = _CalendarWriteStore({
          for (final entry in initialValues.entries)
            'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;
        I18n.setLocale(AppLocale.en);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;

        try {
          late SharedPreferences preferences;
          final initialized = await tester.runAsync<bool>(() async {
            // Both providers create Future.value() write-queue tails. Construct
            // them in the same real async zone as load/setBrand: a tail created
            // in testWidgets' fake zone cannot complete while runAsync waits.
            theme = ThemeProvider();
            calendar = CalendarProvider();
            providersCreated = true;
            if (!editing &&
                _evidenceDirectory != null &&
                _evidenceDirectory!.isNotEmpty) {
              await loadWeeklyReviewScreenshotFonts().timeout(
                const Duration(seconds: 5),
              );
            }
            preferences = await SharedPreferences.getInstance();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await calendar.loadFromStorage().timeout(const Duration(seconds: 5));
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
            return true;
          });
          expect(
            tester.takeException(),
            isNull,
            reason: 'Provider initialization must complete before mounting UI',
          );
          expect(initialized, isTrue);
          final storedBefore = List<String>.of(
            preferences.getStringList(_calendarKey)!,
          );
          final eventsBefore = calendar.localEvents
              .map((event) => event.toJson())
              .toList();
          final revisionBefore = calendar.sourceRevision;
          final writesBefore = store.calendarWrites;
          final removesBefore = store.calendarRemoves;

          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
                ],
                child: Consumer<ThemeProvider>(
                  builder: (context, selectedTheme, _) => MaterialApp(
                    theme: selectedTheme.brand.theme,
                    locale: const Locale('en'),
                    supportedLocales: const [Locale('en')],
                    localizationsDelegates: GlobalMaterialLocalizations.delegates,
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: FilledButton(
                            key: _openRoute,
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => BrandRouteSurface(
                                  child: _CalendarEditorHost(
                                    event: editing ? existing : null,
                                  ),
                                ),
                              ),
                            ),
                            child: const Text('Open calendar route'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _settle(tester);
          await tester.tap(find.byKey(_openRoute));
          await _settle(tester);
          final hostFinder = find.byType(_CalendarEditorHost);
          final host = tester.state<_CalendarEditorHostState>(hostFinder);
          final hostRoute = ModalRoute.of(host.context)!;
          expect(
            host.context
                .findAncestorWidgetOfExactType<AppSecondaryControlTheme>(),
            isNotNull,
            reason: 'The opener must inherit the production route local Theme',
          );
          expect(theme.brand.id, 'defaultBrand');
          await tester.tap(find.byKey(_openEditor));
          await _settle(tester);

          final dialogFinder = find.byType(AppDialog);
          final dialogElement = tester.element(dialogFinder);
          final dialogRoute = ModalRoute.of(dialogElement)!;
          final titleFinder = find.widgetWithText(
            TextField,
            CalendarEventSheetUiCopy.eventTitleLabel,
          );
          final noteFinder = find.widgetWithText(
            TextField,
            CalendarEventSheetUiCopy.noteLabel,
          );
          await tester.enterText(titleFinder, 'Retained event draft');
          await tester.ensureVisible(noteFinder);
          await tester.enterText(noteFinder, 'Retained note draft');
          final titleController = tester
              .widget<TextField>(titleFinder)
              .controller!;
          final noteController = tester.widget<TextField>(noteFinder).controller!;
          final allDaySwitch = find.descendant(
            of: dialogFinder,
            matching: find.byType(Switch),
          );
          await tester.ensureVisible(allDaySwitch);
          await tester.tap(allDaySwitch);
          await _settle(tester);
          final draftAllDay = tester.widget<Switch>(allDaySwitch).value;
          const selection = TextSelection(baseOffset: 2, extentOffset: 8);
          titleController.selection = selection;
          await tester.pump();

          void assertRetainedBrand(AppBrand expected) {
            expect(theme.brand.id, expected.id);
            expect(tester.element(dialogFinder), same(dialogElement));
            expect(ModalRoute.of(dialogElement), same(dialogRoute));
            expect(dialogRoute.isCurrent, isTrue);
            final dialogTheme = Theme.of(dialogElement);
            expect(
              dialogTheme.colorScheme.primary,
              expected.theme.colorScheme.primary,
            );
            expect(
              dialogTheme.colorScheme.surface,
              expected.theme.colorScheme.surface,
            );
            expect(
              appSurfaceStyleOf(dialogElement),
              expected.theme.extension<AppSurfaceStyle>(),
              reason:
                  'Captured route Theme must not freeze the dialog surface style',
            );
            expect(
              tester.widget<TextField>(titleFinder).controller,
              same(titleController),
            );
            expect(
              tester.widget<TextField>(noteFinder).controller,
              same(noteController),
            );
            expect(titleController.text, 'Retained event draft');
            expect(titleController.selection, selection);
            expect(noteController.text, 'Retained note draft');
            expect(tester.widget<Switch>(allDaySwitch).value, draftAllDay);
            expect(store.calendarWrites, writesBefore);
            expect(store.calendarRemoves, removesBefore);
            expect(calendar.sourceRevision, revisionBefore);
            expect(tester.takeException(), isNull);
          }

          assertRetainedBrand(AppBrands.defaultBrand);
          if (!editing) {
            await _captureBrandDialog(tester, boundaryKey, '01-defaultBrand');
          }
          var brandStage = 2;
          for (final brand in [AppBrands.liquidGlass, AppBrands.defaultBrand]) {
            await tester.runAsync(() async {
              expect(
                await theme.setBrand(brand.id).timeout(const Duration(seconds: 5)),
                isTrue,
              );
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _settle(tester);
            assertRetainedBrand(brand);
            if (!editing) {
              await _captureBrandDialog(
                tester,
                boundaryKey,
                '0${brandStage++}-${brand.id}',
              );
            }
          }

          final cancel = find.widgetWithText(
            TextButton,
            CalendarEventSheetUiCopy.cancel,
          );
          await tester.ensureVisible(cancel);
          await tester.tap(cancel);
          await _settle(tester);
          await host.editorClosed!.timeout(const Duration(seconds: 5));
          await tester.runAsync(
            () => AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            ),
          );
          expect(dialogFinder, findsNothing);
          expect(tester.state<_CalendarEditorHostState>(hostFinder), same(host));
          expect(ModalRoute.of(host.context), same(hostRoute));
          expect(hostRoute.isCurrent, isTrue);
          expect(
            calendar.localEvents.map((event) => event.toJson()).toList(),
            eventsBefore,
          );
          expect(calendar.sourceRevision, revisionBefore);
          expect(preferences.getStringList(_calendarKey), storedBefore);
          expect(store.calendarWrites, writesBefore);
          expect(store.calendarRemoves, removesBefore);
          expect(tester.takeException(), isNull);
        } finally {
          try {
            await tester.pumpWidget(const SizedBox.shrink());
            await _settle(tester);
            await tester.runAsync(
              () => AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              ),
            );
          } finally {
            if (providersCreated) {
              theme.dispose();
              calendar.dispose();
            }
            tester.view.reset();
            SharedPreferencesStorePlatform.instance = previousStore;
            I18n.setLocale(previousLocale);
          }
        }
      },
    );
  }
}
