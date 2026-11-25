import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/calendar_date_navigation.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

final _previews = <String, Widget Function(WidgetDisplayMode)>{
  'todo': (mode) => WidgetPreviewCard.todo(displayMode: mode),
  'focus': (mode) => WidgetPreviewCard.focus(displayMode: mode),
  'habit': (mode) => WidgetPreviewCard.habit(displayMode: mode),
  'calendar': (mode) => WidgetPreviewCard.calendar(displayMode: mode),
  'schedule': (mode) => WidgetPreviewCard.schedule(displayMode: mode),
  'goal': (mode) => WidgetPreviewCard.goal(displayMode: mode),
  'course': (mode) => WidgetPreviewCard.course(displayMode: mode),
  'note': (mode) => WidgetPreviewCard.note(displayMode: mode),
  'anniversary': (mode) => WidgetPreviewCard.anniversary(displayMode: mode),
  'diary': (mode) => WidgetPreviewCard.diary(displayMode: mode),
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'structured previews preserve fonts and content priority: ${locale.name}/${platform.name}',
        (tester) async {
          I18n.setLocale(locale);
          final theme = await _prepare(tester);
          final preferences = PreferencesProvider();
          addTearDown(preferences.dispose);
          final firstDay = platform == TargetPlatform.iOS ? 7 : 1;
          await preferences.setFirstDayOfWeek(firstDay);
          final kinds = [
            WidgetPreviewKind.todo,
            WidgetPreviewKind.habit,
            WidgetPreviewKind.focus,
            WidgetPreviewKind.calendar,
          ];
          for (final mode in WidgetDisplayMode.values) {
            for (final presentation in [
              'regular',
              'enlarged',
              'spacing',
              'roomy',
            ]) {
              final width = presentation == 'roomy'
                  ? 640.0
                  : presentation == 'regular'
                  ? 390.0
                  : presentation == 'enlarged'
                  ? 180.0
                  : 240.0;
              final scale = presentation == 'regular' || presentation == 'roomy'
                  ? 1.0
                  : presentation == 'enlarged'
                  ? 3.2
                  : 1.6;
              tester.view.physicalSize = Size(width, 844);
              final keys = {for (final kind in kinds) kind: GlobalKey()};
              Widget preview(WidgetPreviewKind kind) => switch (kind) {
                WidgetPreviewKind.todo => WidgetPreviewCard.todo(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                WidgetPreviewKind.habit => WidgetPreviewCard.habit(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                WidgetPreviewKind.focus => WidgetPreviewCard.focus(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                _ => WidgetPreviewCard.calendar(
                  displayMode: mode,
                  platformOverride: platform,
                ),
              };
              await tester.pumpWidget(
                _app(
                  theme,
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: preferences,
                    child: MediaQuery(
                      data: MediaQueryData(
                        size: Size(width, 844),
                        textScaler: TextScaler.linear(scale),
                        boldText: presentation == 'enlarged',
                        lineHeightScaleFactorOverride: presentation == 'spacing'
                            ? 2.2
                            : null,
                        letterSpacingOverride: presentation == 'spacing'
                            ? 1.2
                            : null,
                        wordSpacingOverride: presentation == 'spacing'
                            ? 2.5
                            : null,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final kind in kinds)
                              RepaintBoundary(
                                key: keys[kind],
                                child: preview(kind),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  viewport: Size(width, 844),
                  textScale: scale,
                ),
              );
              await tester.pumpAndSettle();
              for (final kind in kinds) {
                final card = find.byWidgetPredicate(
                  (widget) =>
                      widget is WidgetPreviewCard && widget.kind == kind,
                );
                await tester.ensureVisible(card);
                await tester.pumpAndSettle();
                final scenario =
                    '$locale/$platform/${mode.id}/${kind.name}/$presentation';
                final frame = find.descendant(
                  of: card,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget.runtimeType.toString() ==
                        '_WidgetPreviewContentFrame',
                  ),
                );
                final frameRect = tester.getRect(frame);
                final bodyText = find.descendant(
                  of: frame,
                  matching: find.byType(Text),
                );
                expect(bodyText, findsWidgets, reason: scenario);
                expect(
                  find.descendant(of: card, matching: find.byType(FittedBox)),
                  findsNothing,
                );
                final renderCard = tester.renderObject<RenderBox>(card);
                for (final element in bodyText.evaluate()) {
                  final text = find.byWidget(element.widget);
                  final paragraph = tester.renderObject<RenderParagraph>(text);
                  final transform = paragraph.getTransformTo(renderCard);
                  expect(
                    transform.entry(0, 0),
                    closeTo(1, 0.001),
                    reason: scenario,
                  );
                  expect(
                    transform.entry(1, 1),
                    closeTo(1, 0.001),
                    reason: scenario,
                  );
                  expect(
                    paragraph.textScaler.scale(12),
                    closeTo(12 * scale, 0.001),
                  );
                  final rect = tester.getRect(text);
                  expect(
                    rect.top,
                    greaterThanOrEqualTo(frameRect.top - 0.1),
                    reason: scenario,
                  );
                  expect(
                    rect.bottom,
                    lessThanOrEqualTo(frameRect.bottom + 0.1),
                    reason: scenario,
                  );
                  expect(rect.left, greaterThanOrEqualTo(frameRect.left - 0.1));
                  expect(rect.right, lessThanOrEqualTo(frameRect.right + 0.1));
                }
                Finder label(String value) =>
                    find.descendant(of: frame, matching: find.text(value));
                final nav = find.descendant(
                  of: card,
                  matching: find.byKey(
                    const ValueKey('widget_preview_navigation'),
                  ),
                );
                final allowsNav = platform == TargetPlatform.android
                    ? mode == WidgetDisplayMode.detailed
                    : mode != WidgetDisplayMode.compact;
                if (!allowsNav) {
                  expect(nav, findsNothing);
                }
                if (presentation == 'roomy' &&
                    mode == WidgetDisplayMode.detailed) {
                  expect(nav, findsOneWidget, reason: scenario);
                }
                var allCandidatesVisible = true;
                if (kind == WidgetPreviewKind.todo) {
                  final labels = [
                    WidgetUiCopy.todoItem1,
                    WidgetUiCopy.todoItem2,
                    WidgetUiCopy.todoItem3,
                  ];
                  final shown = labels
                      .where((value) => label(value).evaluate().isNotEmpty)
                      .length;
                  expect(shown, inInclusiveRange(1, mode.index + 1));
                  for (var i = 0; i < labels.length; i++) {
                    expect(
                      label(labels[i]),
                      i < shown ? findsOneWidget : findsNothing,
                    );
                  }
                  final paragraph = tester.renderObject<RenderParagraph>(
                    label(labels.first),
                  );
                  final circle = tester.renderObject<RenderParagraph>(
                    label('○').first,
                  );
                  var used = 0.0;
                  var expected = 0;
                  for (final value in labels.take(mode.index + 1)) {
                    final size = _previewMeasuredText(
                      paragraph,
                      value,
                      12,
                      width: paragraph.size.width,
                    );
                    final circleHeight = circle.size.height + 4 > 22
                        ? circle.size.height + 4
                        : 22.0;
                    final height =
                        (size.height > circleHeight
                            ? size.height
                            : circleHeight) +
                        (expected > 0 ? 7 : 0);
                    if (used + height > frameRect.height) {
                      break;
                    }
                    used += height;
                    expected++;
                  }
                  expect(shown, expected, reason: scenario);
                  allCandidatesVisible = shown == mode.index + 1;
                  if (mode == WidgetDisplayMode.detailed) {
                    allCandidatesVisible =
                        allCandidatesVisible &&
                        label(
                          WidgetUiCopy.todoSummaryCount,
                        ).evaluate().isNotEmpty &&
                        label(WidgetUiCopy.todoQuickAdd).evaluate().isNotEmpty;
                  }
                } else if (kind == WidgetPreviewKind.habit) {
                  final button = label(WidgetUiCopy.habitCheckInButton);
                  if (button.evaluate().isEmpty) {
                    expect(label(WidgetUiCopy.habitTitle), findsOneWidget);
                  }
                  allCandidatesVisible =
                      button.evaluate().isNotEmpty &&
                      label(WidgetUiCopy.habitTitle).evaluate().isNotEmpty &&
                      label(WidgetUiCopy.habitLine1).evaluate().isNotEmpty &&
                      (mode == WidgetDisplayMode.compact ||
                          label(WidgetUiCopy.habitLine2).evaluate().isNotEmpty);
                } else if (kind == WidgetPreviewKind.focus) {
                  expect(label('25'), findsOneWidget);
                  expect(
                    label(WidgetUiCopy.focusTimerUnit).evaluate().isNotEmpty ||
                        label(
                          WidgetUiCopy.focusMetricNext,
                        ).evaluate().isNotEmpty,
                    isTrue,
                  );
                  if (mode == WidgetDisplayMode.compact) {
                    expect(label(WidgetUiCopy.focusStartButton), findsNothing);
                    expect(
                      label(WidgetUiCopy.focusMetricSessions),
                      findsNothing,
                    );
                  } else {
                    allCandidatesVisible =
                        label(
                          WidgetUiCopy.focusStartButton,
                        ).evaluate().isNotEmpty &&
                        label(WidgetUiCopy.focusLine1).evaluate().isNotEmpty &&
                        (mode != WidgetDisplayMode.detailed ||
                            (label(
                                  WidgetUiCopy.focusLine2,
                                ).evaluate().isNotEmpty &&
                                label(
                                  WidgetUiCopy.focusLine3,
                                ).evaluate().isNotEmpty));
                  }
                } else {
                  final fallback = find.descendant(
                    of: frame,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Text &&
                          (widget.data == WidgetUiCopy.calendarCurrentDate ||
                              widget.data == WidgetUiCopy.calendarCurrentDay),
                    ),
                  );
                  if (fallback.evaluate().isNotEmpty) {
                    expect(label('17'), findsNothing);
                    expect(tester.widget<Text>(fallback).data, contains('17'));
                    expect(
                      tester
                          .renderObject<RenderParagraph>(fallback)
                          .didExceedMaxLines,
                      isFalse,
                    );
                  } else {
                    expect(label('17'), findsOneWidget);
                    final week = find
                        .ancestor(of: label('17'), matching: find.byType(Row))
                        .first;
                    final weekRect = tester.getRect(week);
                    final column =
                        (tester.getCenter(label('17')).dx - weekRect.left) /
                        (weekRect.width / 7);
                    expect(column, closeTo(firstDay == 7 ? 0.5 : 6.5, 0.01));
                    final weekdayRow = find
                        .ancestor(
                          of: label(
                            WidgetUiCopy.calendarWeekLabels.first,
                          ).first,
                          matching: find.byType(Row),
                        )
                        .first;
                    expect(
                      tester
                          .widgetList<Text>(
                            find.descendant(
                              of: weekdayRow,
                              matching: find.byType(Text),
                            ),
                          )
                          .map((text) => text.data),
                      orderedEquals([
                        for (final day
                            in CalendarDateNavigation.orderedWeekdays(firstDay))
                          WidgetUiCopy.calendarWeekLabels[day - 1],
                      ]),
                    );
                    final cells = find.descendant(
                      of: frame,
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget.runtimeType.toString() ==
                            '_WidgetPreviewCalendarCell',
                      ),
                    );
                    final weekCount = cells.evaluate().length ~/ 7;
                    final limit = mode == WidgetDisplayMode.compact
                        ? 1
                        : mode == WidgetDisplayMode.standard
                        ? 4
                        // May 2026 has six real weeks only for weekend starts.
                        : (firstDay >= 6 ? 6 : 5);
                    expect(weekCount, inInclusiveRange(1, limit));
                    final dates = [
                      for (final text in tester.widgetList<Text>(bodyText))
                        if (int.tryParse(text.data ?? '') != null)
                          int.parse(text.data!),
                    ];
                    expect(dates, orderedEquals([...dates]..sort()));
                    allCandidatesVisible = weekCount == limit;
                  }
                }
                if (!allCandidatesVisible) {
                  expect(nav, findsNothing, reason: scenario);
                }
                for (final control in [
                  WidgetUiCopy.todoQuickAdd,
                  WidgetUiCopy.habitCheckInButton,
                  WidgetUiCopy.focusStartButton,
                  WidgetUiCopy.calendarToday,
                ]) {
                  if (label(control).evaluate().isEmpty) {
                    continue;
                  }
                  final text = label(control);
                  final paragraph = tester.renderObject<RenderParagraph>(text);
                  expect(
                    paragraph.didExceedMaxLines,
                    isFalse,
                    reason: '$scenario/$control',
                  );
                  final container = find
                      .ancestor(of: text, matching: find.byType(Container))
                      .first;
                  final bounds = tester.getRect(container);
                  final rect = tester.getRect(text);
                  expect(
                    rect.top,
                    greaterThanOrEqualTo(bounds.top),
                    reason: control,
                  );
                  expect(
                    rect.bottom,
                    lessThanOrEqualTo(bounds.bottom),
                    reason: control,
                  );
                }
                if (nav.evaluate().isNotEmpty) {
                  final bounds = tester.getRect(nav);
                  expect(
                    bounds.bottom,
                    lessThanOrEqualTo(frameRect.bottom + 0.1),
                  );
                  for (final value in WidgetUiCopy.previewNavLabels) {
                    final text = tester.renderObject<RenderParagraph>(
                      label(value),
                    );
                    expect(text.didExceedMaxLines, isFalse);
                    expect(
                      text.getMaxIntrinsicWidth(double.infinity),
                      lessThanOrEqualTo(text.size.width + 0.1),
                    );
                  }
                }
                expect(tester.takeException(), isNull, reason: scenario);
                if (mode == WidgetDisplayMode.detailed) {
                  await _capture(
                    tester,
                    keys[kind]!,
                    'structured-${kind.name}-${locale.name}-${platform.name}-$presentation',
                  );
                }
              }
              if (locale == AppLocale.en) {
                _expectEnglishCopy(tester);
              }
              await tester.pumpWidget(const SizedBox.shrink());
            }
          }
        },
      );
    }
  }

  for (final locale in AppLocale.values) {
    for (final darkApp in [false, true]) {
      testWidgets(
        'default widget text hierarchy: ${locale.name} / dark app $darkApp',
        (tester) async {
          I18n.setLocale(locale);
          final theme = await _prepare(tester, dark: darkApp);
          if (darkApp) {
            await theme.setWidgetBackgroundBrand('defaultBrand');
          }
          final key = GlobalKey();
          await tester.pumpWidget(
            _app(
              theme,
              SingleChildScrollView(
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: theme.brand.theme.scaffoldBackgroundColor,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WidgetPreviewCard.todo(),
                          SizedBox(height: 12),
                          WidgetPreviewCard.habit(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final previews = find.byType(WidgetPreviewCard);
          expect(previews, findsNWidgets(2));
          for (final preview in previews.evaluate()) {
            final previewTheme = tester.widget<Theme>(
              find.descendant(
                of: find.byWidget(preview.widget),
                matching: find.byType(Theme),
              ),
            );
            expect(previewTheme.data.brightness, Brightness.light);
            expect(
              previewTheme.data.colorScheme.onSurfaceVariant,
              DesignTokens.defaultTextMuted,
            );
            expect(
              previewTheme.data.colorScheme.onSurface,
              DesignTokens.defaultText,
            );
          }
          if (locale == AppLocale.en) _expectEnglishCopy(tester);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            key,
            'default-hierarchy-${locale.name}-${darkApp ? 'dark' : 'light'}-app',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('preview follows independent widget background and skin', (
    tester,
  ) async {
    final theme = await _prepare(tester, dark: true);
    await theme.unlockCardSkin('mint_card');
    await theme.setWidgetBackgroundBrand('defaultBrand');
    await theme.setWidgetCardSkin('mint_card');
    final screenshotKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        theme,
        RepaintBoundary(
          key: screenshotKey,
          child: const WidgetPreviewCard.focus(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(WidgetPreviewCard);
    final previewTheme = find.descendant(
      of: preview,
      matching: find.byType(Theme),
    );
    final payload = HomeWidgetThemePayload.fromThemeProvider(theme);
    expect(payload.cardSkinId, 'mint_card');
    expect(theme.activeCardSkin.id, 'plain_card');
    expect(
      tester.widget<Theme>(previewTheme).data.colorScheme.primary,
      payload.primary,
    );
    expect(
      tester.widget<Theme>(previewTheme).data.colorScheme.onSurface,
      payload.text,
    );
    expect(
      tester.widget<Theme>(previewTheme).data.brightness,
      Brightness.light,
    );
    final appTheme = Theme.of(tester.element(find.byKey(screenshotKey)));
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.colorScheme.onSurface, isNot(payload.text));
    final sampleTitle = find.text(
      WidgetUiCopy.previewSampleBadge(
        WidgetUiCopy.previewTitle(WidgetPreviewKind.focus),
      ),
    );
    expect(sampleTitle, findsOneWidget);
    final titleRichText = tester.widget<RichText>(
      find.descendant(of: sampleTitle, matching: find.byType(RichText)),
    );
    expect(titleRichText.text.style?.color, payload.text);
    final surface = find.descendant(
      of: preview,
      matching: find.byKey(const ValueKey('widget_preview_surface')),
    );
    final root = tester.widget<Container>(surface);
    final decoration = root.decoration! as BoxDecoration;
    expect(decoration.color, payload.background);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(payload.cornerRadiusDp.toDouble()),
    );
    await theme.setWidgetCardSkin('plain_card');
    await tester.pumpAndSettle();
    final updated =
        tester.widget<Container>(surface).decoration! as BoxDecoration;
    expect(updated.border, isNull);
    expect(updated.borderRadius, BorderRadius.circular(16));
    expect(tester.takeException(), isNull);
    await _capture(
      tester,
      screenshotKey,
      'independent-light-widget-on-dark-app',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final mode in WidgetDisplayMode.values) {
        final name = '${locale.name}-${dark ? 'dark' : 'light'}-${mode.id}';
        testWidgets('all ten widget previews fit 320 / 1.6: $name', (
          tester,
        ) async {
          I18n.setLocale(locale);
          final theme = await _prepare(tester, dark: dark);
          final keys = {for (final kind in _previews.keys) kind: GlobalKey()};
          await tester.pumpWidget(
            _app(
              theme,
              SingleChildScrollView(
                child: Column(
                  children: [
                    for (final entry in _previews.entries)
                      RepaintBoundary(
                        key: keys[entry.key],
                        child: ColoredBox(
                          color: theme.brand.theme.colorScheme.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: entry.value(mode),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(WidgetPreviewCard), findsNWidgets(10));
          if (locale == AppLocale.en) _expectEnglishCopy(tester);

          for (final entry in keys.entries) {
            final finder = find.byKey(entry.value);
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: entry.key);
            expect(tester.getSize(finder).width, 320);
            if (mode != WidgetDisplayMode.compact) {
              final navigation = find.descendant(
                of: finder,
                matching: find.byKey(
                  const ValueKey('widget_preview_navigation'),
                ),
              );
              expect(navigation.evaluate().length, lessThanOrEqualTo(1));
              for (final label
                  in navigation.evaluate().isEmpty
                      ? <String>[]
                      : WidgetUiCopy.previewNavLabels) {
                final text = find.descendant(
                  of: navigation,
                  matching: find.text(label),
                );
                final paragraph = tester.renderObject<RenderParagraph>(text);
                expect(tester.widget<Text>(text).softWrap, isFalse);
                expect(
                  paragraph.size.width + 0.5,
                  greaterThanOrEqualTo(
                    paragraph.getMaxIntrinsicWidth(double.infinity),
                  ),
                  reason:
                      '${entry.key}: navigation label $label must fit intact',
                );
              }
            }
            if (mode == WidgetDisplayMode.standard) {
              await _capture(tester, entry.value, '${entry.key}-$name');
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final locale in AppLocale.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'text list previews preserve enlarged fonts and prioritize rows: ${locale.name}/${platform.name}',
        (tester) async {
          I18n.setLocale(locale);
          final theme = await _prepare(tester);
          final samples = <WidgetPreviewKind, List<String>>{
            WidgetPreviewKind.schedule: [
              WidgetUiCopy.scheduleItem1,
              WidgetUiCopy.scheduleItem2,
              WidgetUiCopy.scheduleItem3,
            ],
            WidgetPreviewKind.goal: [
              WidgetUiCopy.goalItem1,
              WidgetUiCopy.goalItem2,
              WidgetUiCopy.goalItem3,
            ],
            WidgetPreviewKind.course: [
              WidgetUiCopy.courseItem1,
              WidgetUiCopy.courseItem2,
              WidgetUiCopy.courseItem3,
            ],
            WidgetPreviewKind.note: [
              WidgetUiCopy.noteItem1,
              WidgetUiCopy.noteItem2,
              WidgetUiCopy.noteItem3,
            ],
            WidgetPreviewKind.anniversary: [
              WidgetUiCopy.anniversaryItem1,
              WidgetUiCopy.anniversaryItem2,
              WidgetUiCopy.anniversaryItem3,
            ],
            WidgetPreviewKind.diary: [
              WidgetUiCopy.diaryItem1,
              WidgetUiCopy.diaryItem2,
              WidgetUiCopy.diaryItem3,
            ],
          };
          for (final mode in WidgetDisplayMode.values) {
            for (final presentation in ['regular', 'enlarged', 'spacing']) {
              final enlarged = presentation == 'enlarged';
              final spacing = presentation == 'spacing';
              final width = enlarged
                  ? 180.0
                  : spacing
                  ? 240.0
                  : 390.0;
              final scale = enlarged
                  ? 3.2
                  : spacing
                  ? 1.6
                  : 1.0;
              tester.view.physicalSize = Size(width, 844);
              final captureKeys = {
                for (final kind in samples.keys) kind: GlobalKey(),
              };
              Widget preview(WidgetPreviewKind kind) => switch (kind) {
                WidgetPreviewKind.schedule => WidgetPreviewCard.schedule(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                WidgetPreviewKind.goal => WidgetPreviewCard.goal(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                WidgetPreviewKind.course => WidgetPreviewCard.course(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                WidgetPreviewKind.note => WidgetPreviewCard.note(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                WidgetPreviewKind.anniversary => WidgetPreviewCard.anniversary(
                  displayMode: mode,
                  platformOverride: platform,
                ),
                _ => WidgetPreviewCard.diary(
                  displayMode: mode,
                  platformOverride: platform,
                ),
              };
              await tester.pumpWidget(
                _app(
                  theme,
                  MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 844),
                      textScaler: TextScaler.linear(scale),
                      boldText: enlarged,
                      lineHeightScaleFactorOverride: spacing ? 2.2 : null,
                      letterSpacingOverride: spacing ? 1.2 : null,
                      wordSpacingOverride: spacing ? 2.5 : null,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final kind in samples.keys)
                            RepaintBoundary(
                              key: captureKeys[kind],
                              child: preview(kind),
                            ),
                        ],
                      ),
                    ),
                  ),
                  viewport: Size(width, 844),
                  textScale: scale,
                ),
              );
              await tester.pumpAndSettle();
              final rowLimit = mode.index + 1;
              for (final entry in samples.entries) {
                final card = find.byWidgetPredicate(
                  (widget) =>
                      widget is WidgetPreviewCard && widget.kind == entry.key,
                );
                await tester.ensureVisible(card);
                await tester.pumpAndSettle();
                final bodyTexts = [
                  for (final label in entry.value)
                    find.descendant(of: card, matching: find.text(label)),
                ];
                final scenario =
                    '${entry.key.name}/${mode.id}/$platform/$locale/$width/$scale';
                expect(bodyTexts.first, findsOneWidget, reason: scenario);
                final shown = bodyTexts
                    .where((finder) => finder.evaluate().isNotEmpty)
                    .length;
                expect(shown, inInclusiveRange(1, rowLimit));
                for (var index = 0; index < entry.value.length; index++) {
                  expect(
                    bodyTexts[index],
                    index < shown ? findsOneWidget : findsNothing,
                  );
                }
                if (presentation == 'regular') expect(shown, rowLimit);
                final primaryParagraph = tester.renderObject<RenderParagraph>(
                  bodyTexts.first,
                );
                final effectiveStyle =
                    (primaryParagraph.text as TextSpan).style!;
                expect(
                  effectiveStyle.fontWeight,
                  enlarged ? FontWeight.bold : FontWeight.normal,
                );
                if (spacing) {
                  expect(effectiveStyle.height, 2.2);
                  expect(effectiveStyle.letterSpacing, 1.2);
                  expect(effectiveStyle.wordSpacing, 2.5);
                }
                final bodyLayout = find
                    .ancestor(
                      of: bodyTexts.first,
                      matching: find.byType(LayoutBuilder),
                    )
                    .first;
                final bodyHeight = tester.getSize(bodyLayout).height;
                var expectedCount = 0;
                var expectedHeight = 0.0;
                for (final label in entry.value.take(rowLimit)) {
                  final painter = TextPainter(
                    text: TextSpan(
                      text: label,
                      style: (primaryParagraph.text as TextSpan).style,
                    ),
                    textScaler: primaryParagraph.textScaler,
                    textDirection: primaryParagraph.textDirection,
                    // Preview rows wrap at the system font size. Account for
                    // all lines before deciding how many rows can fit.
                    textHeightBehavior: primaryParagraph.textHeightBehavior,
                    locale: primaryParagraph.locale,
                  )..layout(maxWidth: primaryParagraph.size.width);
                  final cost =
                      (painter.height < 13 ? 13.0 : painter.height) + 4;
                  painter.dispose();
                  if (expectedHeight + cost > bodyHeight) break;
                  expectedHeight += cost;
                  expectedCount++;
                }
                expect(shown, expectedCount, reason: scenario);
                final navigation = find.descendant(
                  of: card,
                  matching: find.byKey(
                    const ValueKey('widget_preview_navigation'),
                  ),
                );
                if (shown < rowLimit) expect(navigation, findsNothing);
                if (navigation.evaluate().isNotEmpty) {
                  final rect = tester.getRect(navigation);
                  final cardRect = tester.getRect(card);
                  expect(rect.bottom, lessThanOrEqualTo(cardRect.bottom));
                  expect(
                    rect.top,
                    greaterThanOrEqualTo(
                      tester.getRect(bodyTexts[shown - 1]).bottom,
                    ),
                  );
                  for (final label in WidgetUiCopy.previewNavLabels) {
                    final text = find.descendant(
                      of: navigation,
                      matching: find.text(label),
                    );
                    final labelRect = tester.getRect(text);
                    expect(labelRect.left, greaterThanOrEqualTo(rect.left));
                    expect(labelRect.right, lessThanOrEqualTo(rect.right));
                  }
                }
                expect(
                  find.descendant(of: card, matching: find.byType(FittedBox)),
                  findsNothing,
                );
                final renderCard = tester.renderObject<RenderBox>(card);
                for (final text in bodyTexts.take(shown)) {
                  final paragraph = tester.renderObject<RenderParagraph>(text);
                  final transform = paragraph.getTransformTo(renderCard);
                  expect(transform.entry(0, 0), closeTo(1, 0.001));
                  expect(transform.entry(1, 1), closeTo(1, 0.001));
                  expect(
                    paragraph.textScaler.scale(11),
                    closeTo(11 * scale, 0.001),
                  );
                  final rect = tester.getRect(text);
                  final cardRect = tester.getRect(card);
                  expect(rect.top, greaterThanOrEqualTo(cardRect.top));
                  expect(rect.bottom, lessThanOrEqualTo(cardRect.bottom));
                }
                expect(tester.takeException(), isNull);
                if (mode == WidgetDisplayMode.detailed &&
                    entry.key == WidgetPreviewKind.note) {
                  await _capture(
                    tester,
                    captureKeys[entry.key]!,
                    'readable-${locale.name}-${platform.name}-$presentation',
                  );
                }
              }
              await tester.pumpWidget(const SizedBox.shrink());
            }
          }
        },
      );
    }
  }

  testWidgets('standalone previews react to language changes', (tester) async {
    final theme = await _prepare(tester);
    await tester.pumpWidget(_app(theme, const WidgetPreviewCard.habit()));
    await tester.pumpAndSettle();
    expect(find.text('今日习惯'), findsWidgets);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    _expectEnglishCopy(tester);
    expect(find.text('80%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.text('今日习惯'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('catalog changes language without resetting style or category', (
    tester,
  ) async {
    final theme = await _prepare(tester);
    final catalogKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        theme,
        RepaintBoundary(
          key: catalogKey,
          child: const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('生活'));
    await tester.tap(find.text('生活'));
    await tester.pumpAndSettle();
    final categoryFinder = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetCategory>,
    );
    expect(
      tester.widget<SegmentedButton<WidgetCategory>>(categoryFinder).selected,
      {WidgetCategory.life},
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    final modeFinder = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetDisplayMode>,
    );
    await tester.ensureVisible(modeFinder);
    final detailedModeLabel = find
        .descendant(of: modeFinder, matching: find.textContaining('详细'))
        .first;
    await tester.tap(detailedModeLabel);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SegmentedButton<WidgetDisplayMode>>(modeFinder).selected,
      {WidgetDisplayMode.detailed},
    );
    final visibleKinds = tester
        .widgetList<WidgetPreviewCard>(find.byType(WidgetPreviewCard))
        .length;
    expect(visibleKinds, lessThan(10));
    expect(visibleKinds, greaterThan(0));

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    _expectEnglishCopy(tester);
    expect(
      tester.widget<SegmentedButton<WidgetCategory>>(categoryFinder).selected,
      {WidgetCategory.life},
    );
    expect(
      tester.widget<SegmentedButton<WidgetDisplayMode>>(modeFinder).selected,
      {WidgetDisplayMode.detailed},
    );
    expect(find.byType(WidgetPreviewCard), findsNWidgets(visibleKinds));
    expect(find.text(WidgetDisplayMode.detailed.description), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, catalogKey, 'catalog-life-detailed-en');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'all style choices remain visible after language expands labels',
    (tester) async {
      final theme = await _prepare(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          theme,
          RepaintBoundary(
            key: key,
            child: const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final modes = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      );
      await tester.ensureVisible(modes);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      for (final mode in WidgetDisplayMode.values) {
        final label = find.text('${mode.label} ${mode.launcherRequestLabel}');
        final rect = tester.getRect(label);
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(
          rect.right,
          lessThanOrEqualTo(308),
          reason: 'Every style choice must fit the phone viewport: ${mode.id}',
        );
        expect(label.hitTestable(), findsOneWidget);
        _expectSegmentLabelUnclipped(tester, modes, label);
        _expectSegmentTouchTarget(tester, label);
      }
      await _capture(tester, key, 'all-style-choices-en');
      final categories = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetCategory>,
      );
      await tester.ensureVisible(categories);
      await tester.pumpAndSettle();
      for (final category in WidgetCategory.values) {
        final label = find.descendant(
          of: categories,
          matching: find.text(WidgetUiCopy.categoryLabel(category)),
        );
        expect(label.hitTestable(), findsOneWidget);
        _expectSegmentLabelUnclipped(tester, categories, label);
        _expectSegmentTouchTarget(tester, label);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'iOS help remains readable at 320x540 and 2x text in both locales',
    (tester) async {
      final theme = await _prepare(tester);
      tester.view.physicalSize = const Size(320, 540);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _app(
            theme,
            const WidgetScreen(hostPlatform: WidgetHostPlatform.ios),
            viewport: const Size(320, 540),
            textScale: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
      final catalogScroll = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(add, 250, scrollable: catalogScroll);
      final button = find.descendant(
        of: add,
        matching: find.byType(FilledButton),
      );
      await Scrollable.ensureVisible(tester.element(button), alignment: 0.35);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final dialog = tester.element(find.byType(AppDialog));
      expect(MediaQuery.textScalerOf(dialog).scale(10), 20);
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(AppDialog)), same(dialog));
        expect(
          find.text(WidgetUiCopy.hostHelpMessage(WidgetHostPlatform.ios)),
          findsOneWidget,
        );
        final dialogScroll = find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(dialogScroll).position;
        expect(position.maxScrollExtent, greaterThan(0));
        position.jumpTo(0);
        await tester.pumpAndSettle();
        await _capture(tester, key, 'ios-help-short-2x-${locale.name}-top');
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          find.text(WidgetUiCopy.actionGotIt).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, key, 'ios-help-short-2x-${locale.name}-bottom');
      }
      await tester.tap(find.text(WidgetUiCopy.actionGotIt));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scenario in ['ios', 'web', 'desktop']) {
    testWidgets(
      'Manual widget help follows host and retains locale state: $scenario',
      (tester) async {
        final platform = WidgetHostPlatform.values.byName(scenario);
        final calls = <String>[];
        const channel = MethodChannel('duoyi/widgets');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        AndroidWidgetManager.debugIsAndroidOverride = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
        addTearDown(() {
          AndroidWidgetManager.debugIsAndroidOverride = null;
          messenger.setMockMethodCallHandler(channel, null);
        });
        final theme = await _prepare(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: _app(theme, WidgetScreen(hostPlatform: platform)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(WidgetUiCopy.hostSupportTitle(platform)),
          findsOneWidget,
        );
        expect(find.text(WidgetUiCopy.actionRecheck), findsNothing);
        final modeFinder = find.byWidgetPredicate(
          (widget) => widget is SegmentedButton<WidgetDisplayMode>,
        );
        expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});
        for (final preview in tester.widgetList<WidgetPreviewCard>(
          find.byType(WidgetPreviewCard),
        )) {
          expect(preview.platformOverride, TargetPlatform.iOS);
        }
        await tester.tap(
          find.descendant(
            of: modeFinder,
            matching: find.text(WidgetDisplayMode.detailed.label),
          ),
        );
        await tester.pumpAndSettle();
        final add = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
        final scrollable = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(add, 300, scrollable: scrollable);
        final button = find.descendant(
          of: add,
          matching: find.widgetWithText(
            FilledButton,
            WidgetUiCopy.hostAddAction(platform),
          ),
        );
        await Scrollable.ensureVisible(tester.element(button), alignment: 0.35);
        ScaffoldMessenger.of(tester.element(button)).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        final dialog = tester.element(find.byType(AppDialog));
        expect(
          find.text(WidgetUiCopy.hostHelpMessage(platform)),
          findsOneWidget,
        );
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(AppDialog)), same(dialog));
        expect(
          find.text(WidgetUiCopy.hostHelpMessage(platform)),
          findsOneWidget,
        );
        expect(find.text(WidgetUiCopy.hostHelpTitle(platform)), findsOneWidget);
        expect(
          find.text(
            WidgetUiCopy.pinHelpMessage(
              AndroidWidgetPinResult.unsupportedPlatform,
            ),
          ),
          findsNothing,
        );
        _expectEnglishCopy(tester);
        expect(tester.takeException(), isNull);
        expect(calls, isEmpty);
        await _capture(tester, key, 'pin-help-${platform.name}-en');
        await tester.tap(find.text(WidgetUiCopy.actionGotIt));
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
        expect(
          find.text(WidgetUiCopy.hostStyleDescription('detailed', platform)),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final scenario in [
    'unsupported_launcher',
    'permission_denied',
    'invalid_widget_id',
  ]) {
    testWidgets(
      'pin help updates language and preserves selection: $scenario',
      (tester) async {
        const channel = MethodChannel('duoyi/widgets');
        const receiptChannel = MethodChannel('duoyi/widget_pin_results');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        AndroidWidgetManager.debugIsAndroidOverride = true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'canRequestPinWidget' => scenario != 'unsupported_launcher',
            'canOpenWidgetSettings' => true,
            'applyWidgetDisplayMode' || 'refreshAllWidgets' => 0,
            'requestPinWidget' =>
              scenario == 'invalid_widget_id'
                  ? 'requested:locale-test'
                  : scenario,
            'lastPinResult' => <String, Object>{
              'requestId': 'locale-test',
              'status': 'invalid_widget_id',
              'kind': 'todo',
              'style': 'detailed',
            },
            _ => null,
          };
        });
        messenger.setMockMethodCallHandler(
          receiptChannel,
          (call) async => call.method == 'beginWait' ? 'locale-receipt' : null,
        );
        addTearDown(() {
          AndroidWidgetManager.debugIsAndroidOverride = null;
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(receiptChannel, null);
        });
        final theme = await _prepare(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: _app(
              theme,
              const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final modeSelector = find.byWidgetPredicate(
          (widget) => widget is SegmentedButton<WidgetDisplayMode>,
        );
        await tester.tap(
          find.descendant(
            of: modeSelector,
            matching: find.textContaining(WidgetDisplayMode.detailed.label),
          ),
        );
        await tester.pumpAndSettle();
        final label = scenario == 'unsupported_launcher'
            ? WidgetUiCopy.pinDisabledAction(
                AndroidWidgetPinResult.unsupportedLauncher,
              )
            : WidgetUiCopy.addWidgetButtonLabel(
                modeLabel: WidgetDisplayMode.detailed.label,
                launcherRequestLabel:
                    WidgetDisplayMode.detailed.launcherRequestLabel,
              );
        final addControl = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
        final scrollable = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          addControl,
          300,
          scrollable: scrollable,
        );
        final button = find.descendant(
          of: addControl,
          matching: find.widgetWithText(FilledButton, label),
        );
        expect(button, findsOneWidget);
        ScaffoldMessenger.of(tester.element(addControl)).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(button), alignment: 0.35);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsOneWidget);
        final dialogElement = tester.element(find.byType(AppDialog));
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(AppDialog)), same(dialogElement));
        expect(
          tester
              .widgetList<WidgetPreviewCard>(find.byType(WidgetPreviewCard))
              .first
              .displayMode,
          WidgetDisplayMode.detailed,
        );
        _expectEnglishCopy(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsNothing);
        await _capture(tester, key, 'pin-help-$scenario-en');
        await tester.tap(find.text(WidgetUiCopy.actionGotIt));
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'account cleanup keeps a pending saved style read from restoring old data',
    (tester) async {
      final store = _GatedReadPreferencesStore({
        'flutter.duoyi_widget_display_mode': 'detailed',
      });
      SharedPreferencesStorePlatform.instance = store;
      final theme = ThemeProvider();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        _app(
          theme,
          const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
        ),
      );
      await store.readStarted.future;

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

      final cleanup = AccountLocalDataCleaner.clearSharedPreferences();
      await tester.pump();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

      store.releaseRead.complete();
      await tester.pump();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

      await cleanup;
      await tester.pumpAndSettle();

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});
      expect(
        (await SharedPreferences.getInstance()).getString(
          'duoyi_widget_display_mode',
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await AccountPreferenceWrites.waitForBoundary();
    },
  );

  testWidgets('stale style retry cannot overwrite a newer selected style', (
    tester,
  ) async {
    final store = _RejectingWidgetModePreferencesStore()
      ..rejectNextModeWrite = true;
    SharedPreferencesStorePlatform.instance = store;
    final theme = ThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      _app(theme, const WidgetScreen(hostPlatform: WidgetHostPlatform.android)),
    );
    await tester.pumpAndSettle();

    final modeSelector = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetDisplayMode>,
    );
    await tester.tap(
      find.descendant(
        of: modeSelector,
        matching: find.textContaining(WidgetDisplayMode.detailed.label),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('widget_style_retry'));
    expect(retry, findsOneWidget);
    final staleRetry = tester.widget<TextButton>(retry).onPressed!;

    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(
      find.descendant(of: retry, matching: find.text('Retry')),
      findsOneWidget,
    );
    I18n.setLocale(AppLocale.zh);
    await tester.pump();
    expect(
      find.descendant(of: retry, matching: find.text('重试')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: modeSelector,
        matching: find.textContaining(WidgetDisplayMode.compact.label),
      ),
    );
    await tester.pumpAndSettle();
    expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});
    expect(
      (await SharedPreferences.getInstance()).getString(
        'duoyi_widget_display_mode',
      ),
      WidgetDisplayMode.compact.id,
    );

    staleRetry();
    await tester.pumpAndSettle();

    expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});
    expect(
      (await SharedPreferences.getInstance()).getString(
        'duoyi_widget_display_mode',
      ),
      WidgetDisplayMode.compact.id,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed style save restores the saved mode after a delayed initial load',
    (tester) async {
      final store = _GatedReadPreferencesStore({
        'flutter.duoyi_widget_display_mode': 'detailed',
      })..rejectNextModeWrite = true;
      SharedPreferencesStorePlatform.instance = store;
      final theme = ThemeProvider();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        _app(
          theme,
          const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
        ),
      );
      await store.readStarted.future;

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});
      final modeSelector = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      );
      await tester.tap(
        find.descendant(
          of: modeSelector,
          matching: find.textContaining(WidgetDisplayMode.compact.label),
        ),
      );
      await tester.pump();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});

      store.releaseRead.complete();
      await tester.pumpAndSettle();

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
      expect(
        (await SharedPreferences.getInstance()).getString(
          'duoyi_widget_display_mode',
        ),
        WidgetDisplayMode.detailed.id,
      );
      expect(find.byKey(const ValueKey('widget_style_retry')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Set<WidgetDisplayMode> _selectedDisplayMode(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetDisplayMode>>(
      find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      ),
    )
    .selected;

class _GatedReadPreferencesStore extends InMemorySharedPreferencesStore {
  _GatedReadPreferencesStore(super.data) : super.withData();

  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool rejectNextModeWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_widget_display_mode' && rejectNextModeWrite) {
      rejectNextModeWrite = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (!readStarted.isCompleted) {
      readStarted.complete();
      await releaseRead.future;
    }
    return super.getAll();
  }
}

class _RejectingWidgetModePreferencesStore
    extends InMemorySharedPreferencesStore {
  _RejectingWidgetModePreferencesStore() : super.withData({});

  bool rejectNextModeWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_widget_display_mode' && rejectNextModeWrite) {
      rejectNextModeWrite = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

Future<ThemeProvider> _prepare(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  SharedPreferences.setMockInitialValues({
    'active_brand': dark ? 'starRail' : 'defaultBrand',
  });
  final theme = ThemeProvider();
  await theme.loadFromStorage();
  addTearDown(theme.dispose);
  return theme;
}

Widget _app(
  ThemeProvider provider,
  Widget child, {
  Size viewport = const Size(320, 844),
  double textScale = 1.6,
}) {
  final theme = provider.brand.theme;
  final fonts = theme.textTheme.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );
  return ChangeNotifierProvider<ThemeProvider>.value(
    value: provider,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(size: viewport, textScaler: TextScaler.linear(textScale)),
        child: navigator!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

void _expectSegmentTouchTarget(WidgetTester tester, Finder label) {
  final button = find
      .ancestor(of: label, matching: find.byType(TextButton))
      .first;
  final size = tester.getSize(button);
  expect(
    size.height,
    greaterThanOrEqualTo(44),
    reason: 'Every segment needs a real touch target of at least 44 pixels.',
  );
}

void _expectSegmentLabelUnclipped(
  WidgetTester tester,
  Finder segmented,
  Finder label,
) {
  // Check the production painter's actual clip path, including the outer
  // segments. A label can fit the viewport yet be clipped by a stadium border.
  final painter = find.descendant(
    of: segmented,
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith(
        '_SegmentedButtonRenderWidget<',
      ),
    ),
  );
  final box = tester.renderObject<RenderBox>(painter);
  final dynamic render = box;
  final padding = render.tapTargetVerticalPadding as double;
  final border = render.enabledBorder as OutlinedBorder;
  final origin = box.localToGlobal(Offset.zero);
  final path = border.getInnerPath(
    (origin + Offset(0, padding / 2)) &
        Size(box.size.width, box.size.height - padding),
    textDirection: render.textDirection as TextDirection,
  );
  final rect = tester.getRect(label).deflate(1);
  for (final point in [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ]) {
    expect(
      path.contains(point),
      isTrue,
      reason: 'The actual segmented control border must not clip its labels.',
    );
  }
}

void _expectEnglishCopy(WidgetTester tester) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final labels = <String>[
    for (final widget in tester.widgetList<Text>(find.byType(Text)))
      widget.data ?? widget.textSpan?.toPlainText() ?? '',
    for (final widget in tester.widgetList<Tooltip>(find.byType(Tooltip)))
      widget.message ?? widget.richMessage?.toPlainText() ?? '',
  ];
  expect(labels.where(chinese.hasMatch), isEmpty);
}

Size _previewMeasuredText(
  RenderParagraph reference,
  String value,
  double size, {
  required double width,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: (reference.text as TextSpan).style!.copyWith(fontSize: size),
    ),
    textDirection: reference.textDirection,
    textScaler: reference.textScaler,
    textHeightBehavior: reference.textHeightBehavior,
    locale: reference.locale,
    // Todo labels wrap; measuring one line overestimates visible row capacity.
  )..layout(maxWidth: width);
  final result = painter.size;
  painter.dispose();
  return result;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_WIDGET_LOCALE_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '${Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR'] ?? 'evidence/screenshots/widget-locale-20261006'}/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}
