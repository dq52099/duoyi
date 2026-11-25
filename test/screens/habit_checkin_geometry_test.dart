import '../support/habit_public_text_bounds.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/habit_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

// The advertised legacy scalar is deliberately unrelated to scale(fontSize).
// A layout that reads only textScaleFactor cannot satisfy the paragraph checks.
class _HabitGeometryNonlinearScaler extends TextScaler {
  const _HabitGeometryNonlinearScaler();
  @override
  double scale(double fontSize) {
    if (fontSize <= 10) return 2.4 * fontSize;
    if (fontSize <= 13) return 24 + .6 * (fontSize - 10);
    return 25.8 + 1.4 * (fontSize - 13);
  }
  @override
  double get textScaleFactor => 1;
}

Finder _card(String id) => find.byKey(ValueKey('habit_checkin_card_$id'));
Finder _inside(String id, Finder target) =>
    find.descendant(of: _card(id), matching: target);
Finder _scrollable() => find.descendant(
  of: find.byKey(const ValueKey('habit_today_scroll_view')),
  matching: find.byType(Scrollable),
).first;

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Future<void> _host(WidgetTester tester, Future<void> Function() action) async {
  final done = await tester.runAsync(() async {
    await action().timeout(const Duration(seconds: 20));
    return true;
  });
  expect(done, isTrue);
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final position = tester.state<ScrollableState>(_scrollable()).position;
  position.jumpTo(position.minScrollExtent);
  await _settle(tester);
  await tester.scrollUntilVisible(
    target, 180, scrollable: _scrollable(), maxScrolls: 100,
  );
  await tester.ensureVisible(target);
  await _settle(tester);
}

Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(
  box.getTransformTo(null), Offset.zero & box.size,
);

Rect _viewport(WidgetTester tester, Finder target) {
  final viewport = RenderAbstractViewport.maybeOf(
    tester.renderObject<RenderBox>(target),
  );
  if (viewport is! RenderBox) {
    throw TestFailure('Habit content must have a box viewport');
  }
  final box = viewport as RenderBox;
  return _globalRect(box);
}

void _contained(Rect inner, Rect outer, String reason) {
  expect(inner.width, greaterThan(0), reason: reason);
  expect(inner.height, greaterThan(0), reason: reason);
  expect(inner.left, greaterThanOrEqualTo(outer.left - .5), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top - .5), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + .5), reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .5), reason: reason);
}

void _paragraphs(WidgetTester tester, String id, TextScaler scaler) {
  final card = _card(id);
  final cardRect = tester.getRect(card);
  final texts = _inside(id, find.byType(Text));
  expect(texts.evaluate(), isNotEmpty);
  for (final element in texts.evaluate()) {
    final paragraph = element.findRenderObject()! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: '$id: $text');
    expect(paragraph.maxLines, isNull, reason: '$id: $text');
    expect(paragraph.overflow, isNot(TextOverflow.ellipsis), reason: '$id: $text');
    _contained(_globalRect(paragraph), cardRect, '$id: full paragraph $text');
    expectHabitTextPaintBounds(
      paragraph, cardRect: cardRect, reason: '$id: full visible text $text',
    );
    final fontSize = paragraph.text.style?.fontSize;
    expect(fontSize, isNotNull, reason: text);
    final actualFontSize = fontSize!;
    expect(
      paragraph.textScaler.scale(actualFontSize),
      closeTo(scaler.scale(actualFontSize), .001),
      reason: '$id: actual font size must use the supplied scaler',
    );
    for (final axis in [const Offset(1, 0), const Offset(0, 1)]) {
      expect(
        (paragraph.localToGlobal(axis) -
            paragraph.localToGlobal(Offset.zero)).distance,
        closeTo(1, .001), reason: '$id: no transformed text shrink',
      );
    }
  }
}

Future<void> _fullText(
  WidgetTester tester, String id, String text,
) async {
  final target = _inside(id, find.text(text));
  expect(target, findsOneWidget, reason: 'complete literal: $text');
  await Scrollable.ensureVisible(tester.element(target), alignment: .05);
  await _settle(tester);
  _contained(tester.getRect(target), _viewport(tester, target), text);
  expectHabitTextPaintBounds(
    tester.renderObject<RenderParagraph>(target), cardRect: tester.getRect(_card(id)),
    viewportRect: _viewport(tester, target), reason: '$id: full visible copy $text',
  );
  expect(
    tester.getSemantics(target).getSemanticsData().label,
    contains(text), reason: 'complete semantic copy: $text',
  );
}

Future<Rect> _target(
  WidgetTester tester, Finder finder, {
  required bool enabled,
  required String label,
  Rect? host,
  Finder? semanticsTarget,
}) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await _settle(tester);
  final rect = tester.getRect(finder);
  // Remove only affine translation before measuring: subtracting two large
  // global coordinates can turn an exact 44px height into 43.99999999999994.
  // Scaling/rotation remains in this matrix and the 44px minimum stays exact.
  final renderBox = tester.renderObject<RenderBox>(finder);
  final transform = renderBox.getTransformTo(null);
  expect(transform.entry(3, 0), 0, reason: '$label: no perspective target');
  expect(transform.entry(3, 1), 0, reason: '$label: no perspective target');
  expect(transform.entry(3, 3), 1, reason: '$label: affine target coordinates');
  transform.setEntry(0, 3, 0);
  transform.setEntry(1, 3, 0);
  transform.setEntry(2, 3, 0);
  final targetSize = Rect.fromPoints(
    MatrixUtils.transformPoint(transform, Offset.zero),
    MatrixUtils.transformPoint(
      transform, renderBox.size.bottomRight(Offset.zero),
    ),
  ).size;
  expect(targetSize.width, greaterThanOrEqualTo(44));
  expect(targetSize.height, greaterThanOrEqualTo(44));
  _contained(rect, _viewport(tester, finder), '$label: visible target');
  if (host != null) _contained(rect, host, '$label: target inside card');
  final semanticFinder = semanticsTarget ?? finder;
  expect(semanticFinder, findsOneWidget);
  final node = tester.getSemantics(semanticFinder);
  expect(node.rect.width, greaterThanOrEqualTo(44));
  expect(node.rect.height, greaterThanOrEqualTo(44));
  final data = node.getSemanticsData();
  expect(data.hasAction(ui.SemanticsAction.tap), enabled,
      reason: '$label: ${node.toStringDeep()}');
  expect('${data.label} ${data.tooltip}', contains(label));
  return rect;
}

String _snapshot(HabitProvider provider) => jsonEncode(
  provider.habits.map((habit) => habit.toJson()).toList(),
);

Habit _current(HabitProvider provider, String id) =>
    provider.habits.singleWhere((habit) => habit.id == id);

Rect _contentRect(WidgetTester tester, String id) {
  final rect = tester.getRect(_card(id));
  final pixels = tester.state<ScrollableState>(_scrollable()).position.pixels;
  return rect.translate(0, pixels);
}

void _rows(Map<String, Rect> cards, double width) {
  final a = cards['daily']!, b = cards['flex']!, c = cards['negative']!;
  if (width == 320) {
    expect(a.left, closeTo(b.left, .5));
    expect(b.left, closeTo(c.left, .5));
    expect(a.width, closeTo(b.width, .5));
    expect(b.width, closeTo(c.width, .5));
    expect(b.top, greaterThanOrEqualTo(a.bottom));
    expect(c.top, greaterThanOrEqualTo(b.bottom));
  } else {
    expect(a.top, closeTo(b.top, .5));
    expect(a.right, lessThan(b.left));
    expect(a.width, closeTo(b.width, .5));
    expect(c.left, closeTo(a.left, .5));
    expect(c.width, closeTo(a.width, .5));
    expect(c.top, greaterThanOrEqualTo(a.bottom));
    expect(c.top, greaterThanOrEqualTo(b.bottom));
  }
}

Future<void> _tapAndDrain(
  WidgetTester tester, Offset point,
) async {
  await _host(tester, () async {
    await tester.tapAt(point);
    await AccountPreferenceWrites.drain();
    await Future<void>.delayed(Duration.zero);
  });
  await _settle(tester);
  await tester.pump(const Duration(seconds: 5));
  await _settle(tester);
  expect(tester.takeException(), isNull);
}

Offset _edge(Rect rect, int edge) => switch (edge) {
  0 => Offset(rect.left + 2, rect.center.dy),
  1 => Offset(rect.right - 2, rect.center.dy),
  2 => Offset(rect.center.dx, rect.top + 2),
  _ => Offset(rect.center.dx, rect.bottom - 2),
};

Future<void> _checkCopies(
  WidgetTester tester, HabitProvider provider, String id,
  AppLocale locale, TextScaler scaler, DateTime day,
) async {
  await _reveal(tester, _card(id));
  final habit = _current(provider, id);
  final english = locale == AppLocale.en;
  final count = habit.todayCount();
  final unit = habit.unit!;
  final progress = habit.flexProgressForDate(day);
  final targetText = habit.kind == HabitKind.negative
      ? (english ? 'Goal: None' : '目标: 不发生')
      : habit.hasFlexRule
      ? (english
          ? '${HabitUiCopy(locale).weekGoal(1)} · Target per session: 123 $unit'
          : '${HabitUiCopy(locale).weekGoal(1)} · 单次目标: 123 $unit')
      : (english ? 'Goal: 123 $unit/day' : '目标: 123 $unit/天');
  final countText = habit.kind == HabitKind.negative
      ? '$count $unit'
      : habit.hasFlexRule
      ? progress!.labelFor(locale)
      : '$count/123';
  _paragraphs(tester, id, scaler);
  await _fullText(tester, id, habit.name);
  await _fullText(tester, id, '$targetText · $countText');
  final status = habit.kind == HabitKind.negative
      ? (english ? 'Recorded' : '已记录')
      : habit.hasFlexRule
      ? (english ? '${progress!.labelPrefix} reached' : '${progress!.labelPrefix}达标')
      : (english ? 'Completed' : '已达标');
  await _fullText(tester, id, status);
  if (habit.currentStreak > 0) {
    await _fullText(
      tester, id, '${habit.currentStreak} ${habit.streakUnitLabel}',
    );
  }
  final checkIn = _inside(id, find.byType(FilledButton));
  final enabled = habit.kind == HabitKind.negative;
  final label = habit.kind == HabitKind.negative
      ? (english ? 'Record' : '记录')
      : habit.hasFlexRule
      ? (english ? '${progress!.labelPrefix} done' : '${progress!.labelPrefix}完成')
      : (english ? 'Done' : '完成');
  final checkRect = await _target(
    tester, checkIn, enabled: enabled, label: label,
  );
  _contained(checkRect, tester.getRect(_card(id)), '$id: check-in containment');
  final undo = _inside(
    id, find.byKey(const ValueKey('habit-undo-inline-button')),
  );
  final undoRect = await _target(
    tester, undo, enabled: true, label: english ? 'Undo once' : '撤回一次',
  );
  _contained(undoRect, tester.getRect(_card(id)), '$id: undo containment');
  // Re-read both at the same scroll offset after revealing the last target.
  expect(tester.getRect(checkIn).overlaps(tester.getRect(undo)), isFalse);
  expect(tester.takeException(), isNull);
}

Future<void> _swipeCancel(
  WidgetTester tester, HabitProvider provider, AppLocale locale,
) async {
  await _reveal(tester, _card('daily'));
  await Scrollable.ensureVisible(
    tester.element(_card('daily')), alignment: .5,
  );
  await _settle(tester);
  final original = tester.getRect(_card('daily'));
  final visible = original.intersect(_viewport(tester, _card('daily')));
  final frozen = _snapshot(provider);
  await tester.dragFrom(
    Offset(visible.right - 8, visible.center.dy), const Offset(-220, 0),
  );
  await _settle(tester);
  final menu = <String, String>{
    'habit_swipe_edit_button': HabitUiCopy.actionEdit(locale),
    'habit_swipe_end_button': HabitUiCopy.actionEnd(locale),
    'habit_swipe_delete_button': HabitUiCopy.actionDelete(locale),
  };
  final bounds = <Rect>[];
  for (final entry in menu.entries) {
    final finder = find.descendant(
      of: find.byKey(const ValueKey('habit_today_scroll_view')),
      matching: find.byKey(ValueKey(entry.key)),
    );
    final action = find.descendant(of: finder, matching: find.byType(InkWell));
    expect(action, findsOneWidget);
    final rect = await _target(
      tester, finder, enabled: true, label: entry.value, semanticsTarget: action,
    );
    // Card content translates; the exposed controls stay in the original host.
    _contained(rect, original, '${entry.key}: exposed host');
    for (final other in bounds) {
      expect(rect.overlaps(other), isFalse);
    }
    bounds.add(rect);
  }
  expect(_snapshot(provider), frozen);
  await tester.tap(find.byKey(const ValueKey('habit_swipe_delete_button')));
  await _settle(tester);
  expect(find.text(HabitUiCopy.deleteConfirmTitle(locale)), findsOneWidget);
  expect(_snapshot(provider), frozen, reason: 'opening dialog cannot delete');
  final cancel = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(HabitUiCopy.actionCancel(locale)),
  );
  expect(cancel, findsOneWidget);
  await tester.tap(cancel);
  await _settle(tester);
  expect(find.byType(AlertDialog), findsNothing);
  expect(_snapshot(provider), frozen, reason: 'cancel leaves all habits intact');
}

class _HabitFirstScreen {
  const _HabitFirstScreen({
    required this.window,
    required this.viewport,
    required this.scrollOffset,
    required this.minimumScrollOffset,
    required this.cards,
  });

  final Rect window;
  final Rect viewport;
  final double scrollOffset;
  final double minimumScrollOffset;
  final Map<String, Rect> cards;
}

_HabitFirstScreen _observeHabitFirstScreen(
  WidgetTester tester, Finder builtCards,
) {
  final viewportFinder = find.descendant(
    of: find.byKey(const ValueKey('habit_today_scroll_view')),
    matching: find.byType(Viewport),
  ).first;
  final viewport = _globalRect(tester.renderObject<RenderBox>(viewportFinder));
  final position = tester.state<ScrollableState>(_scrollable()).position;
  final cards = <String, Rect>{};
  for (final element in builtCards.evaluate()) {
    final box = element.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      cards[(element.widget.key! as ValueKey<String>).value] = _globalRect(box);
    }
  }
  return _HabitFirstScreen(
    window: Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio),
    viewport: viewport,
    scrollOffset: position.pixels,
    minimumScrollOffset: position.minScrollExtent,
    cards: Map.unmodifiable(cards),
  );
}

void _expectHabitFirstScreenDensity(_HabitFirstScreen state, double width) {
  expect(state.window.width, width);
  expect(state.window.height, 844);
  expect(state.scrollOffset, closeTo(state.minimumScrollOffset, .001),
      reason: '$width: density must describe the unscrolled first viewport');
  final visibleViewport = state.viewport.intersect(state.window);
  expect(visibleViewport.width, greaterThan(0));
  expect(visibleViewport.height, greaterThan(0));
  // Independent observed rectangles, not a production tile/row calculation.
  // Cached/offscreen and partially clipped cards cannot contribute to density.
  final completeCards = state.cards.entries.where((entry) {
    final card = entry.value;
    return card.width > 0 && card.height > 0 &&
        card.left >= visibleViewport.left && card.top >= visibleViewport.top &&
        card.right <= visibleViewport.right && card.bottom <= visibleViewport.bottom;
  }).map((entry) => entry.key).toList();
  expect(completeCards.length, greaterThanOrEqualTo(2),
      reason: '$width: at least two complete cards must fit the first viewport; '
          'viewport=$visibleViewport; complete=$completeCards; mounted=${state.cards}');
}

class _HabitDensityScreenshots {
  _HabitDensityScreenshots()
      : directory = Platform.environment['DUOYI_HABIT_DENSITY_SCREENSHOT_DIR'];

  final String? directory;
  bool _prepared = false;
  final Set<int> _capturedWidths = {};

  Future<void> capture(WidgetTester tester, GlobalKey key, int width) async {
    final configured = directory;
    if (configured == null) return;
    await _host(tester, () async {
      final root = Directory(configured);
      if (!root.isAbsolute || !configured.endsWith('/screenshots') ||
          configured.split('/').any((part) => part == '.' || part == '..')) {
        throw ArgumentError('Density PNGs require an absolute named evidence batch/screenshots path');
      }
      final batch = root.parent;
      if (!batch.path.split('/').last.startsWith('habit-density-')) {
        throw ArgumentError('Density evidence batch must have a new habit-density- name');
      }
      final batchType = FileSystemEntity.typeSync(batch.path, followLinks: false);
      if (batchType != FileSystemEntityType.directory &&
          batchType != FileSystemEntityType.notFound) {
        throw StateError('Density evidence batch cannot be a file or symlink');
      }
      final anchor = batchType == FileSystemEntityType.directory ? batch : batch.parent;
      final resolvedAnchor = anchor.resolveSymbolicLinksSync();
      final evidence = Directory('/home/ubuntu/duoyi/evidence').resolveSymbolicLinksSync();
      if (resolvedAnchor != anchor.absolute.path ||
          !(resolvedAnchor == evidence || resolvedAnchor.startsWith('$evidence/'))) {
        throw StateError('Density PNGs must remain under canonical managed evidence');
      }
      if ((width != 1400 && width != 320) || !_capturedWidths.add(width)) {
        throw StateError('Only the two distinct initial density states may be captured');
      }
      // The enclosing verifier retains the serial lock/resource guard. This
      // read-only preflight rechecks the normal 12 GiB floor before each PNG.
      final budget = await Process.run('/usr/bin/python3', [
        '/home/ubuntu/duoyi/scripts/disk_budget.py', 'check',
      ]);
      if (budget.exitCode != 0) {
        throw StateError('Density screenshot disk admission failed: ${budget.stdout}${budget.stderr}');
      }
      debugPrint('Habit density screenshot disk admission: ${budget.stdout}');
      if (!_prepared) {
        if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Density screenshot leaf already exists; retain it and choose a new batch');
        }
        await root.create(recursive: true);
        _prepared = true;
      }
      if (root.resolveSymbolicLinksSync() != root.absolute.path) {
        throw StateError('Density screenshot leaf cannot become a symlink');
      }
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Density PNG encoding returned no bytes');
        final png = File('${root.path}/initial-${width}x844.png');
        await png.create(exclusive: true);
        await png.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      } finally {
        image.dispose();
      }
    });
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('Habit public rows build lazily and reach the last authored habit', (
    tester,
  ) async {
    I18n.setLocale(AppLocale.en);
    tester.view.physicalSize = const Size(1400, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late HabitProvider habits;
    late ThemeProvider theme;
    late TimeAuditProvider audit;
    late AuthProvider auth;
    await _host(tester, () async {
      audit = TimeAuditProvider();
      habits = HabitProvider()
        ..timeAudit = audit
        ..scheduler = RecordingReminderScheduler();
      theme = ThemeProvider();
      auth = AuthProvider();
      await theme.loadFromStorage();
      await habits.loadFromStorage();
      await audit.loadFromStorage();
      for (var index = 0; index < 81; index++) {
        await habits.addHabit(Habit(
          id: 'lazy-$index', name: 'Authored lazy habit $index',
          sortOrder: index,
        ));
      }
    });
    addTearDown(() {
      habits.dispose(); theme.dispose(); audit.dispose(); auth.dispose();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    });
    await _host(tester, loadWeeklyReviewScreenshotFonts);
    final densityCaptureKey = GlobalKey();
    final densityScreenshots = _HabitDensityScreenshots();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppBrands.defaultBrand.theme,
        home: RepaintBoundary(
          key: densityCaptureKey,
          child: const BrandBackground(child: HabitScreen()),
        ),
      ),
    ));
    await _settle(tester);
    final frozen = _snapshot(habits);
    final builtCards = find.byWidgetPredicate((widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('habit_checkin_card_lazy-'),
    );
    // Collect both affected PNGs before evaluating either density assertion.
    await densityScreenshots.capture(tester, densityCaptureKey, 1400);
    final wideFirstScreen = _observeHabitFirstScreen(tester, builtCards);
    final originalSize = tester.view.physicalSize;
    late _HabitFirstScreen narrowFirstScreen;
    try {
      tester.view.physicalSize = const Size(320, 844);
      await _settle(tester);
      final position = tester.state<ScrollableState>(_scrollable()).position;
      position.jumpTo(position.minScrollExtent);
      await _settle(tester);
      await densityScreenshots.capture(tester, densityCaptureKey, 320);
      narrowFirstScreen = _observeHabitFirstScreen(tester, builtCards);
    } finally {
      tester.view.physicalSize = originalSize;
      await _settle(tester);
      final position = tester.state<ScrollableState>(_scrollable()).position;
      position.jumpTo(position.minScrollExtent);
      await _settle(tester);
    }
    _expectHabitFirstScreenDensity(wideFirstScreen, 1400);
    _expectHabitFirstScreenDensity(narrowFirstScreen, 320);
    expect(_snapshot(habits), frozen, reason: 'viewport density checks cannot mutate authored habits');
    expect(habits.habits, hasLength(81));
    expect(builtCards.evaluate().length, lessThan(81));
    expect(_card('lazy-80'), findsNothing);
    await _reveal(tester, _card('lazy-80'));
    expect(_card('lazy-80'), findsOneWidget);
    expect(_card('lazy-0'), findsNothing);
    expect(builtCards.evaluate().length, lessThan(81));
    expect(
      _inside('lazy-80', find.text('Authored lazy habit 80')),
      findsOneWidget,
    );
    _contained(
      tester.getRect(_card('lazy-80')), _viewport(tester, _card('lazy-80')),
      'the last odd-row habit is publicly reachable',
    );
    expect(_snapshot(habits), frozen);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1120.0, 1400.0]) {
    for (final locale in AppLocale.values) {
      for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
        for (final (scalerName, scaler) in <(String, TextScaler)>[
          ('linear100', TextScaler.linear(1)),
          ('linear200', TextScaler.linear(2)),
          ('nonlinear', const _HabitGeometryNonlinearScaler()),
        ]) {
          testWidgets(
            'Habit public content/actions ${width.toInt()}/${locale.name}/${brand.id}/$scalerName',
            (tester) async {
              I18n.setLocale(locale);
              SharedPreferences.setMockInitialValues({'active_brand': brand.id});
              tester.view.physicalSize = Size(width, 844);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              final semantics = tester.ensureSemantics();
              var semanticsDisposed = false;
              addTearDown(() {
                if (!semanticsDisposed) {
                  semanticsDisposed = true;
                  semantics.dispose();
                }
              });
              final messenger = TestDefaultBinaryMessengerBinding
                  .instance.defaultBinaryMessenger;
              messenger.setMockMethodCallHandler(
                SystemChannels.platform, (call) async => null,
              );
              addTearDown(() => messenger.setMockMethodCallHandler(
                SystemChannels.platform, null,
              ));
              late HabitProvider habits;
              late ThemeProvider theme;
              late TimeAuditProvider audit;
              late AuthProvider auth;
              final now = DateTime.now();
              final day = DateTime(now.year, now.month, now.day);
              final title = locale == AppLocale.en
                  ? 'An authored habit title with every word preserved while learning a difficult chapter and writing a careful explanation'
                  : '完整保留作者填写的长习惯名称：阅读复杂章节并逐句写下自己的解释与每日思考';
              final unit = locale == AppLocale.en
                  ? 'carefully explained authored sections'
                  : '逐句说明且保留完整单位的章节';
              await _host(tester, () async {
                audit = TimeAuditProvider();
                habits = HabitProvider()
                  ..timeAudit = audit
                  ..scheduler = RecordingReminderScheduler();
                theme = ThemeProvider();
                auth = AuthProvider();
                await theme.loadFromStorage();
                await habits.loadFromStorage();
                await audit.loadFromStorage();
                final daily = Habit(
                  id: 'daily', name: 'A · $title', unit: unit, targetCount: 123,
                  currentStreak: 7, bestStreak: 7,
                  startDate: day.subtract(const Duration(days: 28)),
                  sortOrder: 0,
                );
                for (var i = 0; i < 7; i++) {
                  daily.completions[daily.dateKey(
                    day.subtract(Duration(days: i)),
                  )] = 123;
                }
                final flex = Habit(
                  id: 'flex', name: 'B · $title', unit: unit, targetCount: 123,
                  flexPeriod: HabitFlexPeriod.week, flexTarget: 1,
                  currentStreak: 3, bestStreak: 3,
                  startDate: day.subtract(const Duration(days: 28)),
                  sortOrder: 1,
                );
                flex.completions[flex.dateKey(day)] = 123;
                var previous = flex.previousPeriodBounds(
                  flex.periodBoundsForDate(day),
                );
                for (var i = 0; i < 2; i++) {
                  flex.completions[flex.dateKey(previous.start)] = 123;
                  previous = flex.previousPeriodBounds(previous);
                }
                final negative = Habit(
                  id: 'negative', name: 'C · $title', unit: unit,
                  kind: HabitKind.negative, sortOrder: 2,
                  startDate: day.subtract(const Duration(days: 28)),
                  completions: {daily.dateKey(day): 12},
                );
                expect(flex.flexProgressForDate(day)!.completed, 1);
                expect(flex.flexProgressForDate(day)!.target, 1);
                expect(flex.isCompletedForDate(day), isTrue,
                    reason: 'the weekly-completed fixture must reach its period goal');
                for (final habit in [daily, flex, negative]) {
                  await habits.addHabit(habit);
                }
              });
              expect(theme.brand.id, brand.id);
              addTearDown(() {
                habits.dispose(); theme.dispose(); audit.dispose(); auth.dispose();
              });
              addTearDown(() async {
                await tester.pumpWidget(const SizedBox.shrink());
                await _settle(tester);
              });
              await _host(tester, loadWeeklyReviewScreenshotFonts);
              final captureKey = GlobalKey();
              await tester.pumpWidget(MultiProvider(
                providers: [
                  ChangeNotifierProvider<HabitProvider>.value(value: habits),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
                  ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ],
                child: MaterialApp(
                  locale: locale.flutterLocale,
                  supportedLocales: const [Locale('zh'), Locale('en')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: scaler),
                    child: child!,
                  ),
                  home: RepaintBoundary(
                    key: captureKey,
                    child: const BrandBackground(child: HabitScreen()),
                  ),
                ),
              ));
              await _settle(tester);
              final screen = tester.state(find.byType(HabitScreen));
              final route = ModalRoute.of(tester.element(find.byType(HabitScreen)));
              final initial = _snapshot(habits);
              final rows = <String, Rect>{};
              for (final id in ['daily', 'flex', 'negative']) {
                await _checkCopies(tester, habits, id, locale, scaler, day);
                rows[id] = _contentRect(tester, id);
              }
              _rows(rows, width);
              expect(_snapshot(habits), initial);

              var writes = 0;
              habits.onLocalMutationPersisted = () => writes++;
              for (final id in ['daily', 'flex']) {
                await _reveal(tester, _card(id));
                final button = _inside(id, find.byType(FilledButton));
                await tester.ensureVisible(button);
                await _settle(tester);
                expect(tester.widget<FilledButton>(button).onPressed, isNull);
                await _tapAndDrain(tester, tester.getCenter(button));
                expect(route!.isCurrent, isTrue,
                    reason: 'disabled check-in taps must not open habit details');
                expect(tester.state(find.byType(HabitScreen)), same(screen));
                expect(_snapshot(habits), initial);
                expect(writes, 0, reason: 'disabled actions cannot persist');
                final directory = Platform.environment['DUOYI_HABIT_DISABLED_SCREENSHOT_DIR'];
                final capture = (width == 320 && locale == AppLocale.en &&
                        (scalerName == 'linear100' || scalerName == 'linear200')) ||
                    (width == 1120 && locale == AppLocale.en && scalerName == 'linear200') ||
                    (width == 1400 && locale == AppLocale.zh && scalerName == 'linear200');
                if (directory != null && capture) {
                  final rect = tester.getRect(button);
                  final metadata = <String, Object>{
                    'brand': brand.id, 'locale': locale.name, 'scaler': scalerName,
                    'width': width, 'habit': id, 'routeCurrent': route.isCurrent,
                    'disabled': tester.widget<FilledButton>(button).onPressed == null,
                    'writes': writes, 'buttonRect': [rect.left, rect.top, rect.width, rect.height],
                  };
                  await _host(tester, () async {
                    final boundary = captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                    final image = await boundary.toImage(pixelRatio: 1);
                    try {
                      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
                      expect(bytes, isNotNull);
                      final stem = '${brand.id}-${locale.name}-${width.toInt()}-$scalerName-$id';
                      final root = Directory(directory);
                      await root.create(recursive: true);
                      final png = File('$directory/$stem.png');
                      final record = File('$directory/$stem.json');
                      expect(png.existsSync() || record.existsSync(), isFalse,
                          reason: 'preserve previous screenshot evidence');
                      await png.writeAsBytes(bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
                      await record.writeAsString(jsonEncode(metadata));
                    } finally {
                      image.dispose();
                    }
                  });
                }
              }
              for (var edge = 0; edge < 4; edge++) {
                await _reveal(tester, _card('daily'));
                final undo = _inside(
                  'daily', find.byKey(const ValueKey('habit-undo-inline-button')),
                );
                final undoRect = await _target(
                  tester, undo, enabled: true,
                  label: locale == AppLocale.en ? 'Undo once' : '撤回一次',
                );
                final beforeUndo = writes;
                await _tapAndDrain(tester, _edge(undoRect, edge));
                expect(_current(habits, 'daily').todayCount(), 122);
                expect(writes, beforeUndo + 1, reason: 'one undo edge tap');
                await _reveal(tester, _card('daily'));
                final button = _inside('daily', find.byType(FilledButton));
                final buttonRect = await _target(
                  tester, button, enabled: true,
                  label: locale == AppLocale.en ? 'Check in' : '打卡',
                );
                final beforeCheck = writes;
                await _tapAndDrain(tester, _edge(buttonRect, edge));
                expect(_current(habits, 'daily').todayCount(), 123);
                expect(writes, beforeCheck + 1, reason: 'one check-in edge tap');
                expect(_current(habits, 'flex').todayCount(), 123);
                expect(_current(habits, 'negative').todayCount(), 12);
                await _checkCopies(tester, habits, 'daily', locale, scaler, day);
              }
              await _reveal(tester, _card('negative'));
              final record = _inside('negative', find.byType(FilledButton));
              await tester.ensureVisible(record);
              await _settle(tester);
              final beforeRecord = writes;
              await _tapAndDrain(tester, tester.getCenter(record));
              expect(_current(habits, 'negative').todayCount(), 13);
              expect(writes, beforeRecord + 1);
              await _checkCopies(tester, habits, 'negative', locale, scaler, day);
              final undo = _inside(
                'negative', find.byKey(const ValueKey('habit-undo-inline-button')),
              );
              await tester.ensureVisible(undo);
              await _settle(tester);
              await _tapAndDrain(tester, tester.getCenter(undo));
              expect(_current(habits, 'negative').todayCount(), 12);
              expect(writes, beforeRecord + 2);
              final beforeMenu = writes;
              await _swipeCancel(tester, habits, locale);
              expect(writes, beforeMenu);
              expect(tester.state(find.byType(HabitScreen)), same(screen));
              expect(ModalRoute.of(tester.element(find.byType(HabitScreen))), same(route));
              expect(tester.takeException(), isNull);
              semanticsDisposed = true;
              semantics.dispose();
            },
          );
        }
      }
    }
  }
}

