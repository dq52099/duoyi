// Rendered regressions for natural-size focus controls and their interactions.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/focus_sound_catalog.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

final _folder = Platform.environment['DUOYI_FOCUS_STATE_EVIDENCE_DIRECTORY'];
final _imageFolder =
    Platform.environment['DUOYI_FOCUS_STATE_SCREENSHOT_DIRECTORY'];
const _scenarios = [
  (
    name: 'unsupported',
    supported: false,
    access: false,
    enabled: false,
    active: false,
    strict: false,
    count: 0,
  ),
  (
    name: 'permission',
    supported: true,
    access: false,
    enabled: true,
    active: false,
    strict: true,
    count: 0,
  ),
  (
    name: 'armed',
    supported: true,
    access: true,
    enabled: true,
    active: false,
    strict: true,
    count: 3,
  ),
  (
    name: 'active',
    supported: true,
    access: true,
    enabled: true,
    active: true,
    strict: true,
    count: 3,
  ),
  (
    name: 'manual',
    supported: true,
    access: true,
    enabled: false,
    active: false,
    strict: false,
    count: 0,
  ),
];

class _Timer extends PomodoroProvider {
  var scenario = _scenarios.first;
  int dndToggles = 0;
  int strictToggles = 0;

  @override
  PomodoroState get state => const PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    type: PomodoroType.focus,
    completedSessions: 0,
    focusRoomId: FocusRoomProvider.defaultRoomId,
  );

  @override
  PomodoroConfig get config => PomodoroConfig(
    autoEnableDnd: scenario.enabled,
    strictFocusMode: scenario.strict,
  );

  @override
  FocusDndStatus get focusDndStatus => FocusDndStatus(
    supported: scenario.supported,
    accessGranted: scenario.access,
  );

  @override
  bool get focusDndActive => scenario.active;

  @override
  List<PomodoroFocusPenalty> get todayPenalties => List.generate(
    scenario.count,
    (index) => PomodoroFocusPenalty(
      id: 'synthetic-$index',
      occurredAt: DateTime(2026, 1, 1),
      reason: FocusPenaltyReason.pause,
      affectedSeconds: 1,
    ),
  );

  void selectScenario(int index) {
    scenario = _scenarios[index];
    notifyListeners();
  }

  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async => focusDndStatus;

  @override
  Future<void> setAutoEnableDnd(bool enabled) async {
    dndToggles++;
  }

  @override
  Future<void> setStrictFocusMode(bool enabled) async {
    strictToggles++;
  }
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 14 ? 1.9 : 1.6);
  @override
  double get textScaleFactor => 1.9;
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (
          name: 'common',
          size: const Size(390, 844),
          scaler: TextScaler.noScaling,
        ),
        (
          name: 'small',
          size: const Size(390, 620),
          scaler: TextScaler.noScaling,
        ),
        (
          name: 'compact',
          size: const Size(320, 568),
          scaler: TextScaler.linear(1.6),
        ),
        (
          name: 'narrow',
          size: const Size(320, 844),
          scaler: TextScaler.linear(1.6),
        ),
        (
          name: 'landscape',
          size: const Size(568, 320),
          scaler: TextScaler.linear(2),
        ),
        (
          name: 'nonlinear',
          size: const Size(332, 844),
          scaler: const _NonlinearScaler(),
        ),
      ]) {
        final name = '$brand-${locale.name}-${layout.name}';
        testWidgets('dashboard complete copy, contrast and interactions $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          I18n.setLocale(locale);
          final timer = _Timer();
          final theme = ThemeProvider();
          final rooms = FocusRoomProvider();
          final sounds = CustomFocusSoundProvider();
          final auth = AuthProvider();
          final boundary = GlobalKey();
          final rows = <Map<String, Object?>>[];
          final errors = <String>[];
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            timer.dispose();
            theme.dispose();
            rooms.dispose();
            sounds.dispose();
            auth.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<PomodoroProvider>.value(value: timer),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
                ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                  value: sounds,
                ),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ],
              child: MaterialApp(
                theme: theme.brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: layout.scaler),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: const PomodoroScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          for (final label in [
            theme.brand.strings.focusTabTimer,
            theme.brand.strings.focusTabHistory,
            FocusRoomUiCopy.roomTab(locale),
          ]) {
            final tabText = find.descendant(
              of: find.byType(TabBar),
              matching: find.text(label),
            );
            expect(tabText, findsOneWidget);
            await tester.ensureVisible(tabText);
            await tester.pumpAndSettle();
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: tabText, matching: find.byType(RichText)),
            );
            if (paragraph.didExceedMaxLines ||
                paragraph.textSize.width > paragraph.size.width + 0.1) {
              errors.add('Incomplete top tab: $label');
            }
          }
          await _capture(tester, boundary, '$name-top');
          final tab = tester.widget<TabBar>(find.byType(TabBar)).controller;
          final element = tester.element(find.byType(PomodoroScreen));
          for (
            var scenarioIndex = 0;
            scenarioIndex < _scenarios.length;
            scenarioIndex++
          ) {
            timer.selectScenario(scenarioIndex);
            await tester.pumpAndSettle();
            final scenario = timer.scenario;
            final text = [
              MainUiCopy.pomodoroCountdownMode,
              MainUiCopy.pomodoroStatusNotStarted,
              '${theme.brand.strings.focusTabTimer} · 0 ${theme.brand.strings.focusCompletedSuffix}',
              '0 ${theme.brand.strings.focusCompletedSuffix}',
              FocusRoomUiCopy.focusTaskLabel(locale),
              FocusRoomUiCopy.selectTaskForRound(locale),
              FocusRoomUiCopy.whiteNoiseLabel(locale),
              FocusSoundCatalog.labelFor('none', locale: locale),
              FocusRoomUiCopy.focusDndTitle(locale),
              FocusRoomUiCopy.dndTileSubtitle(
                supported: scenario.supported,
                accessGranted: scenario.access,
                enabled: scenario.enabled,
                active: scenario.active,
                locale: locale,
              ),
              FocusRoomUiCopy.strictFocusTitle(locale),
              FocusRoomUiCopy.strictFocusTileSubtitle(
                scenario.strict,
                scenario.count,
                locale,
              ),
              FocusRoomUiCopy.studyRoomTitle(locale),
              rooms.activeRoom!.nameFor(locale),
              FocusRoomUiCopy.activeRoomTileSubtitle(true, locale),
            ];
            for (final value in text.toSet()) {
              final finder = find.text(value);
              expect(finder, findsWidgets, reason: value);
              for (final item in finder.evaluate()) {
                final one = find.byElementPredicate((e) => identical(e, item));
                // Measure the current mounted paragraph before scrolling can
                // rebuild an element. Reachability is checked on controls below.
                final paragraphFinder = find.descendant(
                  of: one,
                  matching: find.byType(RichText),
                );
                expect(paragraphFinder, findsOneWidget, reason: value);
                final paragraph = tester.renderObject<RenderParagraph>(
                  paragraphFinder,
                );
                final matrix = paragraph.getTransformTo(null).storage;
                final scaleX = math.sqrt(
                  matrix[0] * matrix[0] + matrix[1] * matrix[1],
                );
                final scaleY = math.sqrt(
                  matrix[4] * matrix[4] + matrix[5] * matrix[5],
                );
                rows.add({
                  'scenario': scenario.name,
                  'text': value,
                  'truncated': paragraph.didExceedMaxLines,
                  'scaleX': scaleX,
                  'scaleY': scaleY,
                });
                if (paragraph.didExceedMaxLines ||
                    paragraph.textSize.width > paragraph.size.width + 0.1 ||
                    paragraph.textSize.height > paragraph.size.height + 0.1) {
                  errors.add('${scenario.name}: incomplete $value');
                }
                if (scaleX < 0.99 || scaleY < 0.99) {
                  errors.add(
                    '${scenario.name}: scaled below natural size $value',
                  );
                }
                if (MediaQuery.textScalerOf(item).scale(13) !=
                    layout.scaler.scale(13)) {
                  errors.add(
                    '${scenario.name}: text scaling overridden $value',
                  );
                }
              }
            }
            for (final title in [
              FocusRoomUiCopy.focusTaskLabel(locale),
              FocusRoomUiCopy.whiteNoiseLabel(locale),
              FocusRoomUiCopy.focusDndTitle(locale),
              FocusRoomUiCopy.strictFocusTitle(locale),
              FocusRoomUiCopy.studyRoomTitle(locale),
            ]) {
              final target = find
                  .ancestor(
                    of: find.text(title),
                    matching: find.byType(InkWell),
                  )
                  .first;
              await _revealVertically(tester, target);
              final box = tester.renderObject<RenderBox>(target);
              final rect = MatrixUtils.transformRect(
                box.getTransformTo(null),
                Offset.zero & box.size,
              );
              if (rect.width < 43.99 || rect.height < 43.99) {
                errors.add('${scenario.name}: target below44 $title $rect');
              }
            }
          }
          // Exercise the actual painted switch and tile hit regions; providers
          // below intercept all device effects and count operation delivery.
          timer.selectScenario(2);
          await tester.pumpAndSettle();
          await _measureContrast(
            tester,
            boundary,
            {
              MainUiCopy.pomodoroCountdownMode,
              MainUiCopy.pomodoroStatusNotStarted,
              '0 ${theme.brand.strings.focusCompletedSuffix}',
              '${theme.brand.strings.focusTabTimer} · 0 ${theme.brand.strings.focusCompletedSuffix}',
              if (find
                  .text(MainUiCopy.pomodoroRemainingPercent(100))
                  .evaluate()
                  .isNotEmpty)
                MainUiCopy.pomodoroRemainingPercent(100),
              FocusRoomUiCopy.studyRoomTitle(locale),
              rooms.activeRoom!.nameFor(locale),
              FocusRoomUiCopy.activeRoomTileSubtitle(true, locale),
              FocusRoomUiCopy.focusTaskLabel(locale),
              FocusRoomUiCopy.selectTaskForRound(locale),
              FocusRoomUiCopy.whiteNoiseLabel(locale),
              FocusSoundCatalog.labelFor('none', locale: locale),
              FocusRoomUiCopy.focusDndTitle(locale),
              FocusRoomUiCopy.dndTileSubtitle(
                supported: true,
                accessGranted: true,
                enabled: true,
                active: false,
                locale: locale,
              ),
              FocusRoomUiCopy.strictFocusTitle(locale),
              FocusRoomUiCopy.strictFocusTileSubtitle(true, 3, locale),
            },
            rows,
            errors,
          );
          final semantics = tester.ensureSemantics();
          try {
            for (final title in [
              FocusRoomUiCopy.focusDndTitle(locale),
              FocusRoomUiCopy.strictFocusTitle(locale),
            ]) {
              final tile = find
                  .ancestor(
                    of: find.text(title),
                    matching: find.byType(InkWell),
                  )
                  .first;
              final toggle = find.descendant(
                of: tile,
                matching: find.byType(Switch),
              );
              expect(toggle, findsOneWidget);
              await _revealVertically(tester, toggle);
              expect(toggle.hitTestable(), findsOneWidget, reason: title);
              expect(
                tester
                    .getSemantics(toggle)
                    .getSemanticsData()
                    .hasAction(ui.SemanticsAction.tap),
                isTrue,
                reason: title,
              );
              await tester.tap(toggle, warnIfMissed: true);
              await tester.pumpAndSettle();
            }
            expect(timer.dndToggles, 1);
            expect(timer.strictToggles, 1);
            // Opening and dismissing each sheet must retain the timer page and
            // must not replay either intercepted operation.
            for (final title in [
              FocusRoomUiCopy.focusTaskLabel(locale),
              FocusRoomUiCopy.whiteNoiseLabel(locale),
              FocusRoomUiCopy.focusDndTitle(locale),
              FocusRoomUiCopy.strictFocusTitle(locale),
              FocusRoomUiCopy.studyRoomTitle(locale),
            ]) {
              final label = find.text(title).first;
              await _revealVertically(tester, label);
              expect(label.hitTestable(), findsOneWidget, reason: title);
              await tester.tap(label, warnIfMissed: true);
              await tester.pumpAndSettle();
              final navigator = tester.state<NavigatorState>(
                find.byType(Navigator).first,
              );
              expect(navigator.canPop(), isTrue, reason: title);
              navigator.pop();
              await tester.pumpAndSettle();
              expect(
                tester.element(find.byType(PomodoroScreen)),
                same(element),
              );
              expect(
                tester.widget<TabBar>(find.byType(TabBar)).controller,
                same(tab),
              );
              expect(tester.takeException(), isNull, reason: title);
            }
            expect(timer.dndToggles, 1);
            expect(timer.strictToggles, 1);
          } finally {
            semantics.dispose();
          }
          await _capture(tester, boundary, '$name-bottom');
          final historyTab = find.descendant(
            of: find.byType(TabBar),
            matching: find.text(theme.brand.strings.focusTabHistory),
          );
          await tester.ensureVisible(historyTab);
          await tester.tap(historyTab);
          await tester.pumpAndSettle();
          expect(tab!.index, 1);
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(PomodoroScreen)), same(element));
          expect(
            tester.widget<TabBar>(find.byType(TabBar)).controller,
            same(tab),
          );
          expect(
            tab.index,
            1,
            reason: 'live locale retains the selected history tab',
          );
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(tab.index, 1);
          final timerTab = find.descendant(
            of: find.byType(TabBar),
            matching: find.text(theme.brand.strings.focusTabTimer),
          );
          await tester.ensureVisible(timerTab);
          await tester.tap(timerTab);
          await tester.pumpAndSettle();
          expect(tab.index, 0);
          if (_folder != null) {
            await tester.runAsync(() async {
              final path = File('$_folder/$name.states.json');
              path.parent.createSync(recursive: true);
              path.writeAsStringSync(
                const JsonEncoder.withIndent(
                  '  ',
                ).convert({'measurements': rows, 'errors': errors}),
              );
            });
          }
          await _capture(tester, boundary, name);
          expect(tester.takeException(), isNull);
          expect(errors, isEmpty);
        });
      }
    }
  }
}

Future<void> _revealVertically(WidgetTester tester, Finder target) async {
  final element = tester.element(target);
  ScrollableState? vertical;
  element.visitAncestorElements((ancestor) {
    if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
      final state = ancestor.state as ScrollableState;
      if (state.axisDirection == AxisDirection.down ||
          state.axisDirection == AxisDirection.up) {
        vertical = state;
        return false;
      }
    }
    return true;
  });
  // Global ensureVisible can scroll the horizontal TabBarView and dispose the
  // timer tab. Reveal only through the control's actual vertical scroll owner.
  if (vertical != null) {
    await vertical!.position.ensureVisible(element.findRenderObject()!);
    await tester.pumpAndSettle();
  }
  expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (_imageFolder == null) {
    return;
  }
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('$_imageFolder/$name.png');
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _measureContrast(
  WidgetTester tester,
  GlobalKey boundary,
  Set<String> labels,
  List<Map<String, Object?>> measurements,
  List<String> errors,
) async {
  for (final label in labels) {
    final finder = find.text(label);
    expect(finder, findsOneWidget, reason: label);
    await _revealVertically(tester, finder);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    // The three-pixel blank gap beside each label is in the same flat surface
    // as its glyphs. Capture each label after revealing its vertical owner;
    // reject an invisible sample instead of clamping it into another surface.
    final isRingPercentage = label == MainUiCopy.pomodoroRemainingPercent(100);
    // At enlarged Chinese text sizes the left padding intersects the curved
    // progress stroke. The percentage's blank top line padding at ring center
    // stays inside the actual ring surface, including after vertical reveal.
    final point = isRingPercentage
        ? Offset(rect.center.dx, rect.top + 1)
        : Offset(rect.left - 3, rect.center.dy);
    final expectedRingBackground = isRingPercentage
        ? Theme.of(tester.element(finder)).colorScheme.surface
        : null;
    final tile = find.ancestor(of: finder, matching: find.byType(InkWell));
    final surface = tester.renderObject<RenderBox>(
      tile.evaluate().isNotEmpty ? tile.first : find.byType(Scaffold).first,
    );
    final surfaceRect = MatrixUtils.transformRect(
      surface.getTransformTo(null),
      Offset.zero & surface.size,
    );
    expect(surfaceRect.contains(point), isTrue, reason: label);
    final foreground = paragraph.text.style!.color!;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await render.toImage(pixelRatio: 1);
      try {
        final raw = (await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = point.dx.round();
        final y = point.dy.round();
        expect(x, inInclusiveRange(0, picture.width - 1), reason: label);
        expect(y, inInclusiveRange(0, picture.height - 1), reason: label);
        final offset = (y * picture.width + x) * 4;
        final background = Color.fromARGB(
          255,
          raw.getUint8(offset),
          raw.getUint8(offset + 1),
          raw.getUint8(offset + 2),
        );
        if (expectedRingBackground != null && expectedRingBackground.a == 1) {
          expect(
            background.toARGB32(),
            expectedRingBackground.toARGB32(),
            reason:
                '$label sample must be blank ring surface, not stroke or glyph',
          );
        }
        final composed = Color.alphaBlend(foreground, background);
        final a = composed.computeLuminance();
        final b = background.computeLuminance();
        final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
        measurements.add({
          'kind': 'actual-pixel-contrast',
          'text': label,
          'foregroundARGB': foreground.toARGB32(),
          'backgroundARGB': background.toARGB32(),
          'sampleX': x,
          'sampleY': y,
          'contrastRatio': ratio,
        });
        if (ratio < 4.5) {
          errors.add('$label: contrast $ratio');
        }
      } finally {
        picture.dispose();
      }
    });
  }
}
