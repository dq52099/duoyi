import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/almanac_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

const _openKey = ValueKey('open-almanac-hour-dialog');
const _summaryKey = ValueKey('selected_date_almanac_summary_card');
const _timeout = Duration(seconds: 5);
final _selectedDay = DateTime(2026, 6, 3);
final _expectedPage = DateTime.utc(2026, 6, 3)
    .difference(DateTime.utc(1900, 1, 1)).inDays;
final _fortune = LunarCalendar.hourFortunes(_selectedDay)
    .singleWhere((fortune) => fortune.branch == '子');

Finder get _dialog => find.byType(Dialog);
Finder get _dialogMaterial => find.descendant(
  of: _dialog,
  matching: find.byType(Material),
).first;
Finder _dialogText(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));
Finder get _hiddenAlmanac => find.byType(AlmanacScreen, skipOffstage: false);
Finder get _hiddenPager => find.byType(PageView, skipOffstage: false);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
}

void main() {
  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    for (final initialLocale in [AppLocale.zh, AppLocale.en]) {
      for (final size in [const Size(320, 844), const Size(568, 320)]) {
        final name = 'almanac-hour-$initialBrand-${initialLocale.name}-'
            '${size.width.toInt()}x${size.height.toInt()}-2x';
        testWidgets(name, (tester) async {
          final fixture = await _mount(
            tester,
            initialBrand: initialBrand,
            initialLocale: initialLocale,
            size: size,
            name: name,
          );
          final probe = fixture.probe;
          final previousShadows = debugDisableShadows;
          try {
            debugDisableShadows = false;
            await tester.tap(find.byKey(_openKey));
            await _settle(tester);
            probe.frameworkErrors('opened calendar');
            final mainElement = tester.element(_hiddenAlmanac);
            final mainState = tester.state(_hiddenAlmanac);
            final mainRoute = ModalRoute.of(mainElement)!;
            // Select through the production calendar rather than initialDate.
            await tester.tap(find.byTooltip(AlmanacUiCopy.nextDayTooltip));
            await _settle(tester);
            await _openDetail(tester);
            probe.frameworkErrors('selected day and opened detail');
            expect(_hiddenPager, findsOneWidget);
            final pagerElement = tester.element(_hiddenPager);
            final controller = tester.widget<PageView>(_hiddenPager).controller!;
            final detailRoute = ModalRoute.of(pagerElement)!;
            expect(controller.page, _expectedPage.toDouble());

            await tester.ensureVisible(find.text(_fortune.branch));
            await _settle(tester);
            await tester.tap(find.text(_fortune.branch));
            await _settle(tester);
            probe.frameworkErrors('opened hour dialog');
            expect(_dialog, findsOneWidget);
            final dialogElement = tester.element(_dialog);
            final dialogRoute = ModalRoute.of(dialogElement)!;

            Future<void> stage(String phase, String brand, AppLocale locale) async {
              // Capture before probing or scrolling: baseline contract failures
              // must not prevent later live-switch screenshots from being saved.
              await fixture.capture(tester, phase);
              probe.frameworkErrors(phase);
              probe.check('$phase retained route/state', () {
                expect(tester.element(_dialog), same(dialogElement));
                expect(ModalRoute.of(tester.element(_dialog)), same(dialogRoute));
                expect(dialogRoute.isCurrent, isTrue);
                expect(tester.element(_hiddenAlmanac), same(mainElement));
                expect(tester.state(_hiddenAlmanac), same(mainState));
                expect(ModalRoute.of(mainElement), same(mainRoute));
                expect(tester.element(_hiddenPager), same(pagerElement));
                expect(tester.widget<PageView>(_hiddenPager).controller,
                    same(controller));
                expect(ModalRoute.of(pagerElement), same(detailRoute));
                expect(controller.page, _expectedPage.toDouble());
              });
              probe.rows.add({
                'stage': phase,
                'brand': brand,
                'locale': locale.name,
                'selectedPage': controller.hasClients ? controller.page : null,
                'expectedPage': _expectedPage,
                'range': _fortune.range,
                'ganzhi': _fortune.ganzhi,
                'deity': _fortune.deity,
              });
              final expectedTheme = AppBrands.byId(brand).theme;
              final expectedFill = expectedTheme.dialogTheme.backgroundColor ??
                  expectedTheme.colorScheme.surface;
              probe.check('$phase live theme and material', () {
                expect(fixture.theme.brand.id, brand);
                // Also prove that the underlying app really changed theme.
                expect(appSurfaceStyleOf(pagerElement),
                    expectedTheme.extension<AppSurfaceStyle>());
                final actual = Theme.of(tester.element(_dialog));
                expect(actual.colorScheme.primary,
                    expectedTheme.colorScheme.primary);
                expect(actual.colorScheme.surface,
                    expectedTheme.colorScheme.surface);
                expect(appSurfaceStyleOf(tester.element(_dialog)),
                    expectedTheme.extension<AppSurfaceStyle>());
                final material = tester.widget<Material>(_dialogMaterial);
                expect(material.color, expectedFill);
              });

              final title = AlmanacUiCopy.hourFortuneDialogTitle(
                _fortune.branch, _fortune.isAuspicious, locale: locale,
              );
              final texts = [
                title,
                AlmanacUiCopy.hourDetailTime(locale: locale),
                _fortune.range,
                AlmanacUiCopy.hourDetailGanzhi(locale: locale),
                _fortune.ganzhi,
                AlmanacUiCopy.hourDetailDeity(locale: locale),
                _fortune.deity,
                AlmanacUiCopy.dialogConfirm(locale: locale),
              ];
              for (final text in texts) {
                await probe.inspectText(
                  _dialogText(text), expected: text, role: '$phase $text',
                );
              }
              probe.check('$phase title follows live ink and painted fill', () {
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(
                    of: _dialogText(title), matching: find.byType(RichText),
                  ),
                );
                expect(paragraph.text.style!.color,
                    expectedTheme.colorScheme.onSurface);
                // Material color alone can miss an old opaque Container drawn
                // on top. The reusable probe sampled a blank gap at the title.
                final titleRow = probe.rows.lastWhere(
                  (row) => row['role'] == '$phase $title',
                );
                expect(titleRow['backgroundARGB'], expectedFill.toARGB32());
              });
              final otherLocale = locale == AppLocale.zh ? AppLocale.en : AppLocale.zh;
              probe.check('$phase obsolete translations are absent', () {
                for (final old in [
                  AlmanacUiCopy.hourFortuneDialogTitle(
                    _fortune.branch, _fortune.isAuspicious, locale: otherLocale,
                  ),
                  AlmanacUiCopy.hourDetailTime(locale: otherLocale),
                  AlmanacUiCopy.hourDetailGanzhi(locale: otherLocale),
                  AlmanacUiCopy.hourDetailDeity(locale: otherLocale),
                  AlmanacUiCopy.dialogConfirm(locale: otherLocale),
                ]) {
                  expect(_dialogText(old), findsNothing);
                }
              });
              probe.frameworkErrors('$phase text probes');
              // Restore the natural opening position before the next capture.
              for (final scroll in find.descendant(
                of: _dialog, matching: find.byType(Scrollable),
              ).evaluate()) {
                final position = (scroll as StatefulElement).state as ScrollableState;
                position.position.jumpTo(position.position.minScrollExtent);
              }
              await tester.pump();
            }

            await stage('01-original', initialBrand, initialLocale);
            final targetBrand = initialBrand == 'defaultBrand'
                ? 'liquidGlass' : 'defaultBrand';
            await fixture.switchBrand(tester, targetBrand);
            await stage('02-live-brand', targetBrand, initialLocale);
            final targetLocale = initialLocale == AppLocale.zh ? AppLocale.en : AppLocale.zh;
            I18n.setLocale(targetLocale);
            await _settle(tester);
            await stage('03-live-locale', targetBrand, targetLocale);
            I18n.setLocale(initialLocale);
            await fixture.switchBrand(tester, initialBrand);
            await stage('04-return', initialBrand, initialLocale);

            final confirm = find.descendant(
              of: _dialog,
              matching: find.widgetWithText(TextButton,
                  AlmanacUiCopy.dialogConfirm(locale: initialLocale)),
            );
            await tester.ensureVisible(confirm);
            await tester.pump();
            probe.check('confirm is reachable', () {
              expect(confirm.hitTestable(), findsOneWidget);
              final rect = tester.getRect(confirm);
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(size.height));
            });
            // Continue retention diagnostics even if the old overflowing
            // dialog's action is unreachable. Only the fallback uses Navigator.
            if (confirm.hitTestable().evaluate().isNotEmpty) {
              await tester.tap(confirm);
            } else {
              Navigator.of(tester.element(_dialog)).pop();
            }
            await _settle(tester);
            probe.check('dismissal retains detail selection', () {
              expect(_dialog, findsNothing);
              expect(detailRoute.isCurrent, isTrue);
              expect(tester.element(_hiddenPager), same(pagerElement));
              expect(tester.widget<PageView>(_hiddenPager).controller,
                  same(controller));
              expect(controller.page, _expectedPage.toDouble());
            });
            await tester.tap(find.byTooltip(AlmanacUiCopy.backTooltip));
            await _settle(tester);
            probe.check('return retains original calendar state', () {
              expect(tester.element(_hiddenAlmanac), same(mainElement));
              expect(tester.state(_hiddenAlmanac), same(mainState));
              expect(mainRoute.isCurrent, isTrue);
            });
            // Reentering through the same summary proves its selected day was
            // retained without reading private State fields or guessing copy.
            await _openDetail(tester);
            probe.check('calendar retains June 3 when reopened', () {
              expect(tester.widget<PageView>(_hiddenPager).controller!.page,
                  _expectedPage.toDouble());
            });
            probe.frameworkErrors('dismissed and reopened detail');
            await fixture.writeDiagnostics(tester);
          } catch (error) {
            probe.errors.add('test interrupted: $error');
            await fixture.capture(tester, 'failure');
            await fixture.writeDiagnostics(tester);
            rethrow;
          } finally {
            debugDisableShadows = previousShadows;
          }
          // The baseline may fail here after all 32 planned captures. Reserve
          // the extra failure screenshot for an interrupted production flow.
          expect(probe.errors, isEmpty, reason: name);
        });
      }
    }
  }
}

Future<void> _openDetail(WidgetTester tester) async {
  final summary = find.byKey(_summaryKey);
  // The enlarged summary can be taller than the short landscape viewport.
  // Center its tap target instead of aligning only the card's top edge.
  await Scrollable.ensureVisible(tester.element(summary), alignment: .5);
  await _settle(tester);
  await tester.tap(summary);
  await _settle(tester);
}

class _HourProbe extends RouteRenderProbe {
  _HourProbe(super.tester, super.boundary, super.name);

  void check(String role, void Function() assertion) {
    try {
      assertion();
    } catch (error) {
      errors.add('$role: $error');
    }
  }

  void frameworkErrors(String stage) {
    Object? error;
    while ((error = tester.takeException()) != null) {
      errors.add('$stage framework: $error');
    }
  }

  Future<void> inspectText(
    Finder finder, {required String expected, required String role}
  ) async {
    try {
      await text(finder, role: role, minimumGeometricScale: .999);
      final rich = find.descendant(of: finder, matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      expect(paragraph.text.toPlainText(), expected);
      expect(paragraph.textScaler.scale(14), 28,
          reason: 'The dialog must preserve the enlarged text setting');
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: expected.length),
      );
      expect(boxes, isNotEmpty);
      for (final word in RegExp(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*")
          .allMatches(expected)) {
        final wordBoxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        );
        expect(wordBoxes, isNotEmpty);
        expect(wordBoxes.map((box) => box.top.round()).toSet(), hasLength(1),
            reason: 'Word ${word.group(0)} must remain intact');
      }
      final scroll = Scrollable.maybeOf(tester.element(rich), axis: Axis.vertical);
      // Dialog's outer padding/semantics can occupy the entire window; the
      // first Material is the actual card for both Dialog and AlertDialog.
      final dialogRect = tester.getRect(_dialogMaterial);
      final viewport = scroll == null ? dialogRect : tester.getRect(find.byWidget(scroll.widget));
      final visible = viewport.intersect(dialogRect).intersect(
        Offset.zero & MediaQuery.sizeOf(tester.element(finder)),
      );
      for (final box in boxes) {
        Rect global() => Rect.fromPoints(
          paragraph.localToGlobal(Offset(box.left, box.top)),
          paragraph.localToGlobal(Offset(box.right, box.bottom)),
        );
        if (scroll != null) {
          final position = scroll.position;
          position.jumpTo((position.pixels + global().center.dy - visible.center.dy)
              .clamp(position.minScrollExtent, position.maxScrollExtent));
          await tester.pump(const Duration(milliseconds: 20));
        }
        final actual = global();
        expect(actual.left, greaterThanOrEqualTo(visible.left - .5));
        expect(actual.right, lessThanOrEqualTo(visible.right + .5));
        expect(actual.top, greaterThanOrEqualTo(visible.top - .5));
        expect(actual.bottom, lessThanOrEqualTo(visible.bottom + .5));
      }
    } catch (error) {
      errors.add('$role: $error');
    }
  }
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  required String initialBrand,
  required AppLocale initialLocale,
  required Size size,
  required String name,
}) async {
  final previousLocale = I18n.current;
  final previousStore = SharedPreferencesStorePlatform.instance;
  SharedPreferences.setMockInitialValues({
    'active_brand': initialBrand,
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'theme_shop_state': jsonEncode({
      'activeBrand': initialBrand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
  });
  I18n.setLocale(initialLocale);
  final fixture = (await tester.runAsync(() async => _Fixture(tester, name)))!;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(_timeout));
    } finally {
      fixture.theme.dispose();
      SharedPreferencesStorePlatform.instance = previousStore;
      I18n.setLocale(previousLocale);
      tester.view.reset();
    }
  });
  await tester.runAsync(() async {
    // Geometry and pixels need readable real fonts even without PNG output.
    await loadWeeklyReviewScreenshotFonts().timeout(_timeout);
    await fixture.theme.loadFromStorage().timeout(_timeout);
    await AccountPreferenceWrites.drain().timeout(_timeout);
  });
  expect(fixture.theme.brand.id, initialBrand);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: fixture.theme,
      child: Consumer<ThemeProvider>(
        builder: (context, theme, child) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, child) => MaterialApp(
            locale: locale.flutterLocale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
              child: RepaintBoundary(key: fixture.boundaryKey, child: child!),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    key: _openKey,
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => BrandRouteSurface(
                          child: AlmanacScreen(initialDate: DateTime(2026, 6, 2)),
                        ),
                      ),
                    ),
                    child: const Text('Open almanac'),
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
  return fixture;
}

class _Fixture {
  _Fixture(WidgetTester tester, this.name) {
    probe = _HourProbe(tester, boundaryKey, name);
  }

  final String name;
  final theme = ThemeProvider();
  final boundaryKey = GlobalKey();
  late final _HourProbe probe;
  final String? evidenceDirectory = Platform.environment['DUOYI_THEME_DIALOG_EVIDENCE_DIR'];

  Future<void> switchBrand(WidgetTester tester, String brand) async {
    await tester.runAsync(() async {
      expect(await theme.setBrand(brand), isTrue);
      await AccountPreferenceWrites.drain().timeout(_timeout);
    });
    await _settle(tester);
  }

  Future<void> capture(WidgetTester tester, String phase) async {
    final directory = evidenceDirectory;
    if (directory == null || directory.isEmpty) return;
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final output = File('$directory/$name-$phase.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> writeDiagnostics(WidgetTester tester) async {
    final directory = evidenceDirectory;
    if (directory == null || directory.isEmpty) return;
    await tester.runAsync(() async {
      final output = File('$directory/$name.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'name': name,
        'measurements': probe.rows,
        'errors': probe.errors,
      }));
    });
  }
}
