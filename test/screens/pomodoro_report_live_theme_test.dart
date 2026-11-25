import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/focus_report.dart';
import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

const _openKey = ValueKey('open-pomodoro-report-route');
const _literalTag = '原始标签 / literal';
const _timeout = Duration(seconds: 5);
const _layouts = [Size(320, 844), Size(568, 320)];

Finder get _dialog => find.byType(AppDialog);
Finder get _body =>
    find.descendant(of: _dialog, matching: find.byType(SelectableText));
Finder get _editable =>
    find.descendant(of: _body, matching: find.byType(EditableText));
Finder get _material => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;
Finder get _screen => find.byType(PomodoroScreen, skipOffstage: false);
Finder get _tabs => find.byType(TabBar, skipOffstage: false);
Finder _button(Type type, String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate(
    (widget) =>
        (type == TextButton && widget is TextButton) ||
        (type == FilledButton && widget is FilledButton) ||
        (type == OutlinedButton && widget is OutlinedButton),
  ),
);
Finder _action(Type type, String label) =>
    find.descendant(of: _dialog, matching: _button(type, label));

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
}

String _markdown(WidgetTester tester) =>
    tester.widget<SelectableText>(_body).data!;
String _title(WidgetTester tester) =>
    (tester.widget<AppDialog>(_dialog).title as Text).data!;

void main() {
  for (final period in [FocusReportPeriod.week, FocusReportPeriod.month]) {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final size in _layouts) {
          final name =
              'pomodoro-report-${period.name}-$brand-${locale.name}-'
              '${size.width.toInt()}x${size.height.toInt()}-2x';
          testWidgets(name, (tester) async {
            final fixture = await _mount(tester, name, brand, locale, size);
            final probe = fixture.probe;
            final oldShadows = debugDisableShadows;
            try {
              debugDisableShadows = false;
              final retained = await fixture.openReport(tester, period);
              final byLocale = <AppLocale, String>{};
              Future<void> stage(
                String phase,
                String liveBrand,
                AppLocale liveLocale,
              ) async {
                // Baseline failures are accumulated only after the screenshot.
                // Every case keeps all four stages even with Chinese/stale ink.
                await fixture.capture(tester, phase);
                probe.frameworkErrors(phase);
                probe.check('$phase retained report/history', () {
                  retained.verify(tester);
                  expect(fixture.clipboard.writes, isEmpty);
                  fixture.expectDataRetained();
                });
                final data = _markdown(tester);
                probe.rows.add({
                  'stage': phase,
                  'brand': liveBrand,
                  'locale': liveLocale.name,
                  'markdown': data,
                  'historyOffset': retained.history.position.pixels,
                  'reportOffset': retained.reportScroll?.position.pixels,
                });
                probe.check('$phase report snapshot and localized framing', () {
                  _expectCopy(
                    tester,
                    fixture.expectedReport(period),
                    liveLocale,
                  );
                  if (byLocale.containsKey(liveLocale)) {
                    expect(
                      data,
                      byLocale[liveLocale],
                      reason:
                          'Theme changes and return must not regenerate metrics',
                    );
                  }
                });
                byLocale.putIfAbsent(liveLocale, () => data);
                probe.check('$phase live brand/fill', () {
                  final expected = AppBrands.byId(liveBrand).theme;
                  expect(fixture.theme.brand.id, liveBrand);
                  expect(
                    appSurfaceStyleOf(tester.element(_screen)),
                    expected.extension<AppSurfaceStyle>(),
                  );
                  final actual = Theme.of(tester.element(_dialog));
                  expect(
                    actual.colorScheme.primary,
                    expected.colorScheme.primary,
                  );
                  expect(
                    actual.colorScheme.surface,
                    expected.colorScheme.surface,
                  );
                  expect(
                    appSurfaceStyleOf(tester.element(_dialog)),
                    expected.extension<AppSurfaceStyle>(),
                  );
                  expect(
                    tester.widget<Material>(_material).color,
                    expected.dialogTheme.backgroundColor ??
                        expected.colorScheme.surface,
                  );
                });

                final positions = _dialogScrolls(tester)
                    .map(
                      (state) => (state: state, offset: state.position.pixels),
                    )
                    .toList();
                final selection = tester
                    .widget<EditableText>(_editable)
                    .controller
                    .selection;
                try {
                  final titleWidget = tester.widget<AppDialog>(_dialog).title;
                  await probe.inspectText(
                    find.descendant(
                      of: _dialog,
                      matching: find.byWidgetPredicate(
                        (widget) => identical(widget, titleWidget),
                      ),
                    ),
                    '$phase title',
                  );
                  final expectedTheme = AppBrands.byId(liveBrand).theme;
                  await probe.inspectBody(
                    '$phase body',
                    expectedFill:
                        expectedTheme.dialogTheme.backgroundColor ??
                        expectedTheme.colorScheme.surface,
                  );
                  for (final control in [
                    _action(
                      TextButton,
                      FocusRoomUiCopy.closeAction(liveLocale),
                    ),
                    _action(
                      FilledButton,
                      FocusRoomUiCopy.copyMarkdownAction(liveLocale),
                    ),
                  ]) {
                    probe.check('$phase reachable action', () {
                      expect(control.hitTestable(), findsOneWidget);
                      final rect = tester.getRect(control);
                      expect(rect.height, greaterThanOrEqualTo(44));
                      expect(rect.top, greaterThanOrEqualTo(0));
                      expect(rect.bottom, lessThanOrEqualTo(size.height));
                    });
                    await probe.inspectText(
                      find.descendant(of: control, matching: find.byType(Text)),
                      '$phase action',
                    );
                  }
                } finally {
                  for (final saved in positions) {
                    if (saved.state.mounted) {
                      final position = saved.state.position;
                      position.jumpTo(
                        saved.offset.clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        ),
                      );
                    }
                  }
                  // Reading the text must not mutate the user's selection.
                  probe.check('$phase probes preserve selection', () {
                    expect(
                      tester
                          .widget<EditableText>(_editable)
                          .controller
                          .selection,
                      selection,
                    );
                  });
                  await tester.pump();
                }
                probe.frameworkErrors('$phase measurements');
              }

              await stage('01-original', brand, locale);
              // Use the real SelectableText-owned controller, never a replacement
              // controller or test result widget. No focus/keyboard is requested.
              retained.setSelectionAndScroll();
              await tester.pump();
              final targetBrand = brand == 'defaultBrand'
                  ? 'liquidGlass'
                  : 'defaultBrand';
              await fixture.switchBrand(tester, targetBrand);
              await stage('02-live-brand', targetBrand, locale);
              final targetLocale = locale == AppLocale.zh
                  ? AppLocale.en
                  : AppLocale.zh;
              I18n.setLocale(targetLocale);
              await _settle(tester);
              await stage('03-live-locale', targetBrand, targetLocale);
              I18n.setLocale(locale);
              await fixture.switchBrand(tester, brand);
              await stage('04-return', brand, locale);

              // Two matrix cases also prove the result is an opening snapshot:
              // a deliberate real provider update must not enter an open report.
              if (brand == 'defaultBrand' &&
                  locale == AppLocale.zh &&
                  size.width == 320) {
                final before = _markdown(tester);
                await tester.runAsync(
                  () => fixture.timer.debugAddSessionsForTest([
                    _session(
                      'after-opening',
                      fixture.now,
                      100,
                      tag: 'Added after opening',
                    ),
                  ]),
                );
                await tester.pump();
                fixture.rememberSessionUpdate();
                probe.check('history update retains report snapshot', () {
                  expect(_markdown(tester), before);
                  expect(tester.element(_dialog), same(retained.dialogElement));
                  fixture.expectDataRetained();
                });
              }

              // Copy after another real locale switch: compare the actual
              // displayed payload at invocation, not a future presenter API.
              I18n.setLocale(targetLocale);
              await _settle(tester);
              final copied = _markdown(tester);
              probe.check('copy uses current locale and opening snapshot', () {
                _expectCopy(
                  tester,
                  fixture.expectedReport(period),
                  targetLocale,
                );
                expect(copied, byLocale[targetLocale]);
              });
              final copy = _action(
                FilledButton,
                FocusRoomUiCopy.copyMarkdownAction(targetLocale),
              );
              probe.check(
                'copy is reachable',
                () => expect(copy.hitTestable(), findsOneWidget),
              );
              await tester.tap(copy);
              await _settle(tester);
              probe.check('current copy closes only its report', () {
                expect(fixture.clipboard.writes, [copied]);
                expect(_dialog, findsNothing);
                retained.verifyHistory(tester);
                fixture.expectDataRetained();
                expect(
                  find.text(
                    FocusRoomUiCopy.focusReportCopiedSnackBar(targetLocale),
                  ),
                  findsOneWidget,
                );
              });
              // Suppress the transient feedback before reopening the real report.
              ScaffoldMessenger.of(
                tester.element(_screen),
              ).hideCurrentSnackBar();
              await _settle(tester);
              final reopened = await fixture.openReport(tester, period);
              await tester.tap(
                _action(TextButton, FocusRoomUiCopy.closeAction(targetLocale)),
              );
              await _settle(tester);
              probe.check('Close retains history without copying', () {
                expect(_dialog, findsNothing);
                expect(fixture.clipboard.writes, [copied]);
                reopened.verifyHistory(tester);
                expect(reopened.screenElement, same(retained.screenElement));
                expect(reopened.tabs, same(retained.tabs));
                fixture.expectDataRetained();
              });
              probe.frameworkErrors('copy and close');
              await fixture.diagnostics(tester);
            } catch (error) {
              probe.errors.add('interrupted production flow: $error');
              await fixture.capture(tester, 'failure');
              await fixture.diagnostics(tester);
              rethrow;
            } finally {
              debugDisableShadows = oldShadows;
            }
            expect(probe.errors, isEmpty, reason: name);
          });
        }
      }
    }
  }

  // Separate from the capture matrix so an old async-pop failure cannot stop
  // the four planned visual stages. Both entrances and opening brands run.
  for (final period in [FocusReportPeriod.week, FocusReportPeriod.month]) {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      testWidgets(
        'dismissed ${period.name} Clipboard completion retains history $brand',
        (tester) async {
          final fixture = await _mount(
            tester,
            'pomodoro-report-stale-copy-${period.name}-$brand',
            brand,
            AppLocale.zh,
            _layouts.first,
          );
          final retained = await fixture.openReport(tester, period);
          final payload = _markdown(tester);
          fixture.clipboard.held = Completer<void>();
          await tester.tap(
            _action(
              FilledButton,
              FocusRoomUiCopy.copyMarkdownAction(AppLocale.zh),
            ),
          );
          await tester.pump();
          expect(fixture.clipboard.writes, [payload]);
          expect(_dialog, findsOneWidget);
          await tester.tap(
            _action(TextButton, FocusRoomUiCopy.closeAction(AppLocale.zh)),
          );
          await _settle(tester);
          expect(_dialog, findsNothing);
          retained.verifyHistory(tester);
          // Also change presentation after dismissal; this grants no ownership
          // of History to the callback waiting on an already dismissed result.
          I18n.setLocale(AppLocale.en);
          await fixture.switchBrand(
            tester,
            brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
          );
          fixture.clipboard.release();
          await _settle(tester);
          fixture.probe.frameworkErrors('old Clipboard completion');
          fixture.probe.check('old completion never pops history', () {
            retained.verifyHistory(tester);
            expect(_dialog, findsNothing);
            expect(fixture.clipboard.writes, [payload]);
            expect(find.byType(SnackBar), findsNothing);
            fixture.expectDataRetained();
          });
          await fixture.diagnostics(tester);
          expect(fixture.probe.errors, isEmpty);
        },
      );
    }
  }
}

void _expectCopy(WidgetTester tester, FocusReport report, AppLocale locale) {
  final title = _title(tester);
  final data = _markdown(tester);
  expect(data, startsWith('# $title\n'));
  expect(data, contains(_literalTag));
  expect(data, isNot(contains('Added after opening')));
  if (locale == AppLocale.zh) {
    expect(title, report.title);
    expect(
      data,
      report.toMarkdown(
        formatDate: (date) => I18nDateFormat.date(date, locale: locale),
      ),
    );
    return;
  }
  // Assert meanings and bound values without selecting a future presenter API
  // or prescribing harmless wording/punctuation choices to the implementer.
  expect(
    title.toLowerCase(),
    contains(report.period == FocusReportPeriod.week ? 'week' : 'month'),
  );
  expect(title.toLowerCase(), contains('focus'));
  expect(title.toLowerCase(), contains('report'));
  final generated = data.replaceAll(_literalTag, 'literal');
  expect(
    generated,
    isNot(matches(RegExp(r'[\u3400-\u9fff]'))),
    reason:
        'Generated framing and untagged copy must be English; authored tag stays literal',
  );
  final lines = data.split('\n');
  String line(String label) => lines.singleWhere(
    (value) =>
        RegExp('^-\\s*(?:$label)\\s*:', caseSensitive: false).hasMatch(value),
  );
  expect(
    line('Period|Range'),
    contains(
      '${I18nDateFormat.date(report.start, locale: locale)} - ${I18nDateFormat.date(report.end, locale: locale)}',
    ),
  );
  void duration(String label, int minutes) => expect(
    line(label),
    matches(RegExp('\\b$minutes\\s+(?:min|minutes)\\b', caseSensitive: false)),
  );
  duration('Total focus(?: time| duration)?|Focus time|Focus duration', 85);
  expect(
    line('Focus sessions|Sessions|Session count|Focus session count'),
    matches(RegExp(r'\b3\b')),
  );
  duration(
    'Average(?: session| focus session| per session)?(?: time| duration)?',
    28,
  );
  duration('Longest(?: session| focus session)?(?: time| duration)?', 50);
  expect(line('Active days'), matches(RegExp(r'\b1\b')));
  final interruptions = line(
    'Strict[ -]focus interruptions|Strict[ -]focus interruptions count',
  );
  expect(interruptions, matches(RegExp(r':\s*1\b')));
  expect(
    interruptions,
    matches(RegExp(r'\b5\s+(?:min|minutes)\b', caseSensitive: false)),
  );
  expect(
    data,
    matches(
      RegExp(
        r'^## (?:Tag breakdown|Tag investment|Tag time allocation|Tags)\s*$',
        caseSensitive: false,
        multiLine: true,
      ),
    ),
  );
  final literal = lines.singleWhere(
    (value) => value.startsWith('- $_literalTag:'),
  );
  expect(literal, matches(RegExp(r'\b75\s+(?:min|minutes)\b')));
  expect(literal, matches(RegExp(r'\b2\s+sessions\b')));
  expect(literal, contains('88%'));
  final untagged = lines.singleWhere(
    (value) => value.toLowerCase().startsWith('- untagged:'),
  );
  expect(untagged, matches(RegExp(r'\b10\s+(?:min|minutes)\b')));
  expect(untagged, matches(RegExp(r'\b1\s+session\b')));
  expect(untagged, contains('12%'));
}

class _Timer extends PomodoroProvider {
  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async =>
      const FocusDndStatus.unavailable();
}

PomodoroSession _session(
  String id,
  DateTime now,
  int minutes, {
  String? tag,
  PomodoroType type = PomodoroType.focus,
}) {
  final start = DateTime(now.year, now.month, now.day, 8);
  return PomodoroSession(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    durationSeconds: minutes * 60,
    type: type,
    taskName: 'Authored task 原文',
    tag: tag,
  );
}

List<ScrollableState> _verticalAncestors(Element element) {
  final scrolls = <ScrollableState>[];
  element.visitAncestorElements((ancestor) {
    if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
      final state = ancestor.state as ScrollableState;
      if (axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
        scrolls.add(state);
      }
    }
    return true;
  });
  return scrolls;
}

List<ScrollableState> _dialogScrolls(WidgetTester tester) => find
    .descendant(of: _dialog, matching: find.byType(Scrollable))
    .evaluate()
    .map((element) => (element as StatefulElement).state as ScrollableState)
    .where((state) => axisDirectionToAxis(state.axisDirection) == Axis.vertical)
    .toList();

class _Retained {
  _Retained(WidgetTester tester, this.history)
    : screenElement = tester.element(_screen),
      screenRoute = ModalRoute.of(tester.element(_screen))!,
      tabs = tester.widget<TabBar>(_tabs).controller!,
      historyOffset = history.position.pixels,
      dialogElement = tester.element(_dialog),
      dialogRoute = ModalRoute.of(tester.element(_dialog))!,
      textElement = tester.element(_body),
      textState = tester.state<State<SelectableText>>(_body),
      textController = tester.widget<EditableText>(_editable).controller,
      textData = _markdown(tester),
      reportScroll = Scrollable.maybeOf(
        tester.element(_body),
        axis: Axis.vertical,
      );

  final Element screenElement, dialogElement, textElement;
  final ModalRoute<dynamic> screenRoute, dialogRoute;
  final TabController tabs;
  final ScrollableState history;
  final double historyOffset;
  final State<SelectableText> textState;
  TextEditingController textController;
  String textData;
  final ScrollableState? reportScroll;
  TextSelection? selection;
  double? reportOffset;

  void setSelectionAndScroll() {
    selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    textController.selection = selection!;
    if (reportScroll != null) {
      final position = reportScroll!.position;
      reportOffset = math.min(24.0, position.maxScrollExtent);
      position.jumpTo(reportOffset!);
    }
  }

  void verifyHistory(WidgetTester tester, {bool covered = false}) {
    expect(tester.element(_screen), same(screenElement));
    expect(ModalRoute.of(tester.element(_screen)), same(screenRoute));
    expect(screenRoute.isCurrent, !covered);
    expect(tester.widget<TabBar>(_tabs).controller, same(tabs));
    expect(tabs.index, 1);
    expect(history.mounted, isTrue);
    expect(history.position.pixels, closeTo(historyOffset, .5));
  }

  void verify(WidgetTester tester) {
    verifyHistory(tester, covered: true);
    expect(tester.element(_dialog), same(dialogElement));
    expect(ModalRoute.of(tester.element(_dialog)), same(dialogRoute));
    expect(dialogRoute.isCurrent, isTrue);
    expect(tester.element(_body), same(textElement));
    expect(tester.state<State<SelectableText>>(_body), same(textState));
    final currentController = tester.widget<EditableText>(_editable).controller;
    final currentData = _markdown(tester);
    if (currentData == textData) {
      // Theme-only rebuilds retain exact selection and controller identity.
      expect(currentController, same(textController));
      if (selection != null) expect(currentController.selection, selection);
    } else {
      // Flutter's SelectableText replaces its private editing controller when
      // its data changes. A translated body retains SelectableText State, not
      // the disposed old controller or the old string's selection offsets.
      textController = currentController;
      textData = currentData;
      selection = currentController.selection;
    }
    expect(
      Scrollable.maybeOf(tester.element(_body), axis: Axis.vertical),
      same(reportScroll),
    );
    if (reportOffset != null) {
      expect(reportScroll!.position.pixels, closeTo(reportOffset!, .5));
    }
  }
}

class _Clipboard {
  final writes = <String>[];
  Completer<void>? held;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add((call.arguments as Map)['text'] as String);
          await held?.future;
        } else if (call.method == 'Clipboard.getData') {
          return {'text': writes.isEmpty ? '' : writes.last};
        } else if (call.method == 'Clipboard.hasStrings') {
          return {'value': writes.isNotEmpty};
        }
        return null;
      },
    );
  }

  void release() {
    if (held != null && !held!.isCompleted) held!.complete();
  }
}

class _Probe extends RouteRenderProbe {
  _Probe(super.tester, super.boundary, super.name);

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

  Future<void> inspectText(Finder finder, String role) async {
    try {
      await text(finder, role: role, minimumGeometricScale: .999);
    } catch (error) {
      errors.add('$role: $error');
    }
  }

  Future<void> inspectBody(String role, {required Color expectedFill}) async {
    try {
      final widget = tester.widget<EditableText>(_editable);
      final render = tester.state<EditableTextState>(_editable).renderEditable;
      final data = _markdown(tester);
      expect(widget.controller.text, data);
      expect(
        render.textScaler.scale(14),
        28,
        reason: 'Keep actual enlarged text, not a shrunken preview',
      );
      List<ui.TextBox> tightBoxes(TextSelection selection) {
        // Native EditableText defaults to max-width selection highlights,
        // which include line padding. Read tight glyph boxes from this same
        // renderer and restore highlight behavior before any frame is pumped.
        final previous = render.selectionWidthStyle;
        try {
          render.selectionWidthStyle = ui.BoxWidthStyle.tight;
          return render.getBoxesForSelection(selection);
        } finally {
          render.selectionWidthStyle = previous;
        }
      }

      // A selected trailing space may extend beyond the paragraph's paint
      // width. Measure every visible token, without trimming displayed data or
      // weakening the bounds/word-integrity checks below.
      final boxes = <({ui.TextBox box, int start, int end, String text})>[
        for (final run in RegExp(r'\S+').allMatches(data))
          for (final box in tightBoxes(
            TextSelection(baseOffset: run.start, extentOffset: run.end),
          ))
            (box: box, start: run.start, end: run.end, text: run.group(0)!),
      ];
      expect(boxes, isNotEmpty);
      for (final word in RegExp(
        r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
      ).allMatches(data)) {
        final parts = tightBoxes(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        );
        expect(
          parts.map((box) => box.top.round()).toSet(),
          hasLength(1),
          reason: 'Keep ${word.group(0)} intact',
        );
      }
      final ancestors = _verticalAncestors(tester.element(_editable));
      Rect visible() {
        var rect = tester
            .getRect(_material)
            .intersect(Offset.zero & MediaQuery.sizeOf(tester.element(_body)));
        for (final scroll in ancestors) {
          rect = rect.intersect(tester.getRect(find.byWidget(scroll.widget)));
        }
        return rect;
      }

      for (final run in RegExp(r'\S+').allMatches(data)) {
        List<ui.TextBox> currentBoxes() => tightBoxes(
          TextSelection(baseOffset: run.start, extentOffset: run.end),
        );
        if (run.group(0) == 'Focus') {
          final selection = TextSelection(
            baseOffset: run.start,
            extentOffset: run.end,
          );
          List<List<double>> values(List<ui.TextBox> queried) => [
            for (final box in queried)
              [box.left, box.top, box.right, box.bottom],
          ];
          rows.add({
            'role': '$role original/tight same token',
            'run': run.group(0),
            'selectionWidthStyle': render.selectionWidthStyle.name,
            'originalBoxes': values(render.getBoxesForSelection(selection)),
            'tightBoxes': values(tightBoxes(selection)),
          });
        }
        for (var part = 0; part < currentBoxes().length; part++) {
          // Scrolling pumps may repaint/re-layout the live themed paragraph.
          // Never compare a previously captured TextBox against its new viewport.
          ui.TextBox currentBox() {
            final live = currentBoxes();
            return live[part.clamp(0, live.length - 1)];
          }

          Rect global() {
            final box = currentBox();
            return Rect.fromPoints(
              render.localToGlobal(Offset(box.left, box.top)),
              render.localToGlobal(Offset(box.right, box.bottom)),
            );
          }

          // Move the real inner and outer vertical viewports; nested scrolls must
          // not make a line geometrically present but clipped by an outer owner.
          final before = global();
          final currentViewport = visible();
          if (before.top < currentViewport.top - .5 ||
              before.bottom > currentViewport.bottom + .5) {
            for (final scroll in ancestors) {
              final position = scroll.position;
              final viewport = tester.getRect(find.byWidget(scroll.widget));
              position.jumpTo(
                (position.pixels + global().center.dy - viewport.center.dy)
                    .clamp(position.minScrollExtent, position.maxScrollExtent),
              );
              await tester.pump(const Duration(milliseconds: 20));
            }
          }
          if (part >= currentBoxes().length) break;
          final box = currentBox();
          final rect = global();
          final viewport = visible();
          final geometry = {
            'run': run.group(0),
            'start': run.start,
            'end': run.end,
            'box': [box.left, box.top, box.right, box.bottom],
            'global': [rect.left, rect.top, rect.right, rect.bottom],
            'viewport': [
              viewport.left,
              viewport.top,
              viewport.right,
              viewport.bottom,
            ],
            'caretAtEnd': render
                .getLocalRectForCaret(
                  TextPosition(
                    offset: run.end,
                    affinity: TextAffinity.upstream,
                  ),
                )
                .toString(),
          };
          if (rect.left < viewport.left - .5 ||
              rect.right > viewport.right + .5) {
            rows.add({'role': '$role failing token geometry', ...geometry});
          }
          expect(rect.left, greaterThanOrEqualTo(viewport.left - .5));
          expect(
            rect.right,
            lessThanOrEqualTo(viewport.right + .5),
            reason: jsonEncode(geometry),
          );
          expect(rect.top, greaterThanOrEqualTo(viewport.top - .5));
          expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + .5));
        }
      }
      final viewport = visible();
      final boundaryRender =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bodyRect = tester.getRect(_body);
      final point = boundaryRender.globalToLocal(
        Offset(bodyRect.left - 3, viewport.center.dy),
      );
      final background = (await tester.runAsync(() async {
        final image = await boundaryRender.toImage(pixelRatio: 1);
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final x = point.dx.floor(), y = point.dy.floor();
          expect(x, inInclusiveRange(0, image.width - 1));
          expect(y, inInclusiveRange(0, image.height - 1));
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(
            255,
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
        } finally {
          image.dispose();
        }
      }))!;
      final foreground = widget.style.foreground?.color ?? widget.style.color!;
      final ratio = appContrastRatio(
        Color.alphaBlend(foreground, background),
        background,
      );
      final size = render.textScaler.scale(widget.style.fontSize!);
      final required = size >= 24 ? 3.0 : 4.5;
      rows.add({
        'role': role,
        'lineBoxes': boxes.length,
        'foregroundARGB': foreground.toARGB32(),
        'backgroundARGB': background.toARGB32(),
        'ratio': ratio,
        'required': required,
        'renderedFontSize': size,
      });
      expect(ratio, greaterThanOrEqualTo(required));
      expect(
        background,
        expectedFill,
        reason: 'The actual painted blank gap must follow the current brand',
      );
    } catch (error) {
      errors.add('$role: $error');
    }
  }
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String name,
  String brand,
  AppLocale locale,
  Size size,
) async {
  final previousLocale = I18n.current;
  final previousStore = SharedPreferencesStorePlatform.instance;
  final now = DateTime.now();
  final sessions = [
    _session('focus-25', now, 25, tag: _literalTag),
    _session('focus-50', now, 50, tag: _literalTag),
    _session('focus-10-untagged', now, 10),
    _session(
      'excluded-break',
      now,
      90,
      tag: 'Excluded break',
      type: PomodoroType.shortBreak,
    ),
  ];
  final penalties = [
    PomodoroFocusPenalty(
      id: 'penalty-5',
      occurredAt: DateTime(now.year, now.month, now.day, 9),
      reason: FocusPenaltyReason.pause,
      affectedSeconds: 300,
    ),
  ];
  SharedPreferences.setMockInitialValues({
    'active_brand': brand,
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'theme_shop_state': jsonEncode({
      'activeBrand': brand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'pomodoro_sessions': jsonEncode(
      sessions.map((session) => session.toJson()).toList(),
    ),
    'pomodoro_focus_penalties': jsonEncode(
      penalties.map((penalty) => penalty.toJson()).toList(),
    ),
  });
  I18n.setLocale(locale);
  final fixture = (await tester.runAsync(
    () async => _Fixture(tester, name, now, sessions, penalties),
  ))!;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  fixture.clipboard.install(tester);
  addTearDown(() async {
    try {
      // Retire the route before releasing a still-pending callback on failure.
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.clipboard.release();
      await _settle(tester);
      await tester.runAsync(() async {
        await AccountPreferenceWrites.drain().timeout(_timeout);
        await fixture.timer.waitForSnapshotWrites().timeout(_timeout);
      });
    } finally {
      fixture.timer.dispose();
      fixture.rooms.dispose();
      fixture.sounds.dispose();
      fixture.auth.dispose();
      fixture.theme.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      SharedPreferencesStorePlatform.instance = previousStore;
      I18n.setLocale(previousLocale);
      tester.view.reset();
    }
  });
  await tester.runAsync(() async {
    await loadWeeklyReviewScreenshotFonts().timeout(_timeout);
    await fixture.theme.loadFromStorage().timeout(_timeout);
    await fixture.timer.loadFromStorage().timeout(_timeout);
    await fixture.timer.setFocusRoomId(FocusRoomProvider.defaultRoomId);
    await AccountPreferenceWrites.drain().timeout(_timeout);
  });
  expect(fixture.theme.brand.id, brand);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: fixture.theme),
        ChangeNotifierProvider<PomodoroProvider>.value(value: fixture.timer),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: fixture.rooms),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: fixture.sounds,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, child) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, child) => MaterialApp(
            locale: locale.flutterLocale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: RepaintBoundary(key: fixture.boundaryKey, child: child!),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    key: _openKey,
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const BrandRouteSurface(
                          child: PomodoroScreen(useShellBackground: true),
                        ),
                      ),
                    ),
                    child: const Text('Open focus'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_openKey));
  await _settle(tester);
  fixture.probe.frameworkErrors('opened focus route');
  final historyTab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text(fixture.theme.brand.strings.focusTabHistory),
  );
  await tester.ensureVisible(historyTab);
  await tester.tap(historyTab);
  await _settle(tester);
  fixture.probe.frameworkErrors('selected history tab');
  expect(tester.widget<TabBar>(_tabs).controller!.index, 1);
  fixture.rememberData();
  return fixture;
}

class _Fixture {
  _Fixture(
    WidgetTester tester,
    this.name,
    this.now,
    this.openingSessions,
    this.openingPenalties,
  ) {
    probe = _Probe(tester, boundaryKey, name);
  }
  final String name;
  final DateTime now;
  final List<PomodoroSession> openingSessions;
  final List<PomodoroFocusPenalty> openingPenalties;
  final theme = ThemeProvider();
  final timer = _Timer();
  final rooms = FocusRoomProvider();
  final sounds = CustomFocusSoundProvider();
  final auth = AuthProvider();
  final clipboard = _Clipboard();
  final boundaryKey = GlobalKey();
  late final _Probe probe;
  late String _sessions, _penalties, _config;
  late PomodoroState _state;
  late String? _room;
  final evidenceDirectory =
      Platform.environment['DUOYI_THEME_DIALOG_EVIDENCE_DIR'];

  FocusReport expectedReport(FocusReportPeriod period) =>
      FocusReportBuilder.build(
        sessions: openingSessions,
        penalties: openingPenalties,
        period: period,
        now: now,
      );

  void rememberData() {
    _sessions = jsonEncode(
      timer.sessions.map((session) => session.toJson()).toList(),
    );
    _penalties = jsonEncode(
      timer.penalties.map((penalty) => penalty.toJson()).toList(),
    );
    _config = jsonEncode(timer.config.toJson());
    _state = timer.state;
    _room = rooms.activeRoomId;
  }

  void rememberSessionUpdate() {
    _sessions = jsonEncode(
      timer.sessions.map((session) => session.toJson()).toList(),
    );
  }

  void expectDataRetained() {
    expect(
      jsonEncode(timer.sessions.map((session) => session.toJson()).toList()),
      _sessions,
    );
    expect(
      jsonEncode(timer.penalties.map((penalty) => penalty.toJson()).toList()),
      _penalties,
    );
    expect(jsonEncode(timer.config.toJson()), _config);
    expect(timer.state, same(_state));
    expect(rooms.activeRoomId, _room);
  }

  Future<_Retained> openReport(
    WidgetTester tester,
    FocusReportPeriod period,
  ) async {
    final label = period == FocusReportPeriod.week
        ? FocusRoomUiCopy.copyWeeklyReportButton(I18n.current)
        : FocusRoomUiCopy.copyMonthlyReportButton(I18n.current);
    final tabs = tester.widget<TabBar>(_tabs).controller!;
    expect(tabs.index, 1);
    // The report buttons live inside the History tab's CustomScrollView. In short
    // landscape the first history card fills the viewport/cache, so the buttons
    // have no Elements yet and cannot supply their Scrollable ancestor.
    final historyList = find.descendant(
      of: _screen,
      matching: find.byType(CustomScrollView),
    );
    expect(historyList, findsOneWidget);
    final historyScrollable = find.descendant(
      of: historyList,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    );
    expect(historyScrollable, findsOneWidget);
    final history = tester.state<ScrollableState>(historyScrollable);
    final button = _button(OutlinedButton, label);
    final initialOffset = history.position.pixels;
    var revealSteps = 0;
    if (button.evaluate().isEmpty) {
      // A reopened result can also be above the currently built children.
      // Search from the start only when the button has not been built.
      history.position.jumpTo(history.position.minScrollExtent);
      await _settle(tester);
      while (button.evaluate().isEmpty && revealSteps < 40) {
        final position = history.position;
        final previous = position.pixels;
        final step = math.max(48.0, position.viewportDimension * .8);
        position.jumpTo(
          (previous + step).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        revealSteps++;
        await _settle(tester);
        expect(tester.widget<TabBar>(_tabs).controller, same(tabs));
        expect(tabs.index, 1);
        if (position.pixels <= previous && button.evaluate().isEmpty) break;
      }
    }
    probe.rows.add({
      'role': '${period.name} report entrance reveal',
      'initialHistoryOffset': initialOffset,
      'revealedHistoryOffset': history.position.pixels,
      'revealSteps': revealSteps,
      'historyViewport': history.position.viewportDimension,
      'selectedTab': tabs.index,
    });
    expect(button, findsOneWidget);
    expect(
      Scrollable.maybeOf(tester.element(button), axis: Axis.vertical),
      same(history),
    );
    // Reveal the actual vertical owner; never move the horizontal TabBarView.
    await history.position.ensureVisible(
      tester.renderObject(button),
      alignment: .5,
    );
    await _settle(tester);
    expect(tester.widget<TabBar>(_tabs).controller, same(tabs));
    expect(tabs.index, 1);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await _settle(tester);
    probe.frameworkErrors('opened ${period.name} report');
    expect(_dialog, findsOneWidget);
    expect(_body, findsOneWidget);
    return _Retained(tester, history);
  }

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
      final render =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('$directory/$name-$phase.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> diagnostics(WidgetTester tester) async {
    final directory = evidenceDirectory;
    if (directory == null || directory.isEmpty) return;
    await tester.runAsync(() async {
      final file = File('$directory/$name.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'name': name,
          'measurements': probe.rows,
          'errors': probe.errors,
        }),
      );
    });
  }
}
