import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart' show appContrastRatio;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

const _captureKey = ValueKey('mine-update-badge-root-capture');

// Uses AppUpdateService's real hasUpdate/latestVersion/checking implementation.
// The existing today_mine_smoke held-check fixture has no active release policy.
// Only publication is added here; no badge, tile or route is recreated.
class _ReleaseUpdater extends AppUpdateService {
  _ReleaseUpdater()
    : super(
        repo: 'synthetic/duoyi',
        currentVersion: '1.0.0',
        currentVersionCode: 1,
      );

  void publish(String? version) {
    debugSetUpdatePolicyForTest(
      latestVersion: version,
      latestVersionCode: 2,
    );
    notifyListeners();
  }
}

Widget _root(ThemeProvider theme, AppUpdateService updater) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AchievementProvider()),
    ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
    ChangeNotifierProvider(create: (_) => AppLockProvider()),
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => CalendarProvider()),
    ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
    ChangeNotifierProvider(create: (_) => CountdownProvider()),
    ChangeNotifierProvider(create: (_) => CourseProvider()),
    ChangeNotifierProvider(create: (_) => DiaryProvider()),
    ChangeNotifierProvider(create: (_) => GoalProvider()),
    ChangeNotifierProvider(create: (_) => HabitProvider()),
    ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
    ChangeNotifierProvider(create: (_) => NoteProvider()),
    ChangeNotifierProvider(create: (_) => PomodoroProvider()),
    ChangeNotifierProvider(create: (_) => PreferencesProvider()),
    ChangeNotifierProvider(create: (_) => ShareProvider()),
    ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
    ChangeNotifierProvider(create: (_) => TodoProvider()),
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => NotificationService()),
    ChangeNotifierProvider(create: (_) => AiService()),
    ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
    ChangeNotifierProvider<ThemeProvider>.value(value: theme),
    ChangeNotifierProvider<AppUpdateService>.value(value: updater),
  ],
  child: AnimatedBuilder(
    animation: Listenable.merge([theme, I18n.localeListenable]),
    builder: (context, _) {
      final base = theme.brand.theme;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: I18n.current.flutterLocale,
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
          primaryTextTheme: base.primaryTextTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
          ),
          child: RepaintBoundary(key: _captureKey, child: child!),
        ),
        home: const BrandBackground(
          child: MineScreen(useShellBackground: true),
        ),
      );
    },
  ),
);

Finder _updateTile() => find.ancestor(
  of: find.text(I18n.tr('mine.tile.check_updates')),
  matching: find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_Tile',
  ),
).first;

Future<void> _reveal(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text(I18n.tr('mine.tile.check_updates')),
    400,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(_updateTile());
  await tester.pumpAndSettle();
}

List<double> _rect(Rect rect) => [
  rect.left, rect.top, rect.width, rect.height,
];

String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

// Always captures final raster first. Baseline diagnostics do not fail on the
// known ellipsis/contrast defects, allowing the whole retained matrix to finish.
Future<Map<String, Object?>> _capture(
  WidgetTester tester,
  String name,
  String? version,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final badge = find.descendant(
    of: _updateTile(),
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_UpdateAvailableBadge',
    ),
  );
  expect(badge, findsOneWidget);
  Rect inImage(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(boundary), Offset.zero & box.size,
  );
  final badgeRect = inImage(tester.renderObject<RenderBox>(badge));
  final viewport = Offset.zero & boundary.size;
  expect(viewport.contains(badgeRect.topLeft), isTrue);
  expect(viewport.contains(badgeRect.bottomRight - const Offset(.01, .01)), isTrue);

  final pixels = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final directory = Platform.environment['DUOYI_MINE_UPDATE_BADGE_SCREENSHOTS'];
      if (directory != null && directory.isNotEmpty) {
        final file = File('$directory/$name.png');
        if (file.existsSync()) throw StateError('Refusing to overwrite $file');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(png.buffer.asUint8List());
      }
      return (rgba: rgba, width: image.width, height: image.height);
    } finally {
      image.dispose();
    }
  });
  expect(pixels, isNotNull);
  final raster = pixels!;
  final paragraphs = find.descendant(of: badge, matching: find.byType(RichText));
  expect(paragraphs, findsWidgets);
  final probes = <Map<String, Object?>>[];
  final visibleStrings = <String>[];
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    visibleStrings.add(text);
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
    )..layout(maxWidth: paragraph.size.width);
    final didExceed = painter.didExceedMaxLines;
    painter.dispose();
    final transform = paragraph.getTransformTo(boundary);
    final origin = MatrixUtils.transformPoint(transform, Offset.zero);
    final xScale = (MatrixUtils.transformPoint(transform, const Offset(1, 0)) - origin).distance;
    final yScale = (MatrixUtils.transformPoint(transform, const Offset(0, 1)) - origin).distance;
    final textRect = inImage(paragraph);
    final decoration = find.ancestor(
      of: find.byElementPredicate((candidate) => identical(candidate, element)),
      matching: find.byType(DecoratedBox),
    ).first;
    final fillRect = inImage(tester.renderObject<RenderBox>(decoration));
    final foreground = paragraph.text.style?.foreground?.color ?? paragraph.text.style?.color;
    expect(foreground, isNotNull);
    final samples = <Map<String, Object?>>[];
    // Blank painted padding above the paragraph, away from the rounded corners.
    final y = ((fillRect.top + textRect.top) / 2).floor();
    for (final fraction in [.25, .5, .75]) {
      final x = (textRect.left + textRect.width * fraction).floor();
      expect(x, inInclusiveRange(0, raster.width - 1));
      expect(y, inInclusiveRange(0, raster.height - 1));
      final point = Offset(x + .5, y + .5);
      expect(fillRect.contains(point), isTrue);
      expect(textRect.contains(point), isFalse);
      final offset = (y * raster.width + x) * 4;
      final data = raster.rgba;
      final background = Color.fromARGB(
        data.getUint8(offset + 3), data.getUint8(offset),
        data.getUint8(offset + 1), data.getUint8(offset + 2),
      );
      expect(background.a, 1);
      samples.add({
        'x': x, 'y': y, 'backgroundArgb': background.toARGB32(),
        'ratio': appContrastRatio(Color.alphaBlend(foreground!, background), background),
      });
    }
    probes.add({
      'text': text,
      'rect': _rect(textRect),
      'fillRect': _rect(fillRect),
      'didExceedMaxLines': didExceed,
      'scaled10px': paragraph.textScaler.scale(10),
      'transformScaleX': xScale,
      'transformScaleY': yScale,
      'foregroundArgb': foreground!.toARGB32(),
      'fontWeight': (paragraph.text.style?.fontWeight ?? FontWeight.normal).value,
      'samples': samples,
    });
  }
  final expected = version == null || version.trim().isEmpty
      ? I18n.tr('mine.update.badge')
      : '${I18n.tr('mine.update.badge_version_prefix')}$version';
  expect(_compact(visibleStrings.join()), _compact(expected));
  return {
    'schema': 'duoyi.mine-update-badge.capture.v215',
    'name': name, 'version': version, 'locale': I18n.current.storageValue,
    'viewport': [raster.width, raster.height], 'textScale': 2,
    'badgeRect': _rect(badgeRect), 'expectedText': expected, 'paragraphs': probes,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Mine active update badge retained theme locale and fallback capture', (tester) async {
    SharedPreferences.setMockInitialValues({
      'active_brand': 'defaultBrand',
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    });
    I18n.setLocale(AppLocale.zh);
    addTearDown(() => I18n.setLocale(AppLocale.zh));
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = ThemeProvider();
    final updater = _ReleaseUpdater();
    addTearDown(theme.dispose);
    addTearDown(updater.dispose);
    await theme.loadFromStorage();
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
    updater.publish('2.0.0');
    await tester.pumpWidget(_root(theme, updater));
    await tester.pumpAndSettle();
    final screen = tester.state(find.byType(MineScreen));
    final route = ModalRoute.of(tester.element(find.byType(MineScreen)));
    final reports = <Map<String, Object?>>[];
    try {
      for (final release in <(String, String?)>[
        ('version', '2.0.0'), ('empty-fallback', ''), ('null-fallback', null),
      ]) {
        updater.publish(release.$2);
        await tester.pumpAndSettle();
        var step = 0;
        for (final state in <(String, AppLocale)>[
          ('defaultBrand', AppLocale.zh), ('liquidGlass', AppLocale.zh),
          ('liquidGlass', AppLocale.en), ('defaultBrand', AppLocale.en),
          ('defaultBrand', AppLocale.zh),
        ]) {
          var finished = false;
          final change = theme.setBrand(state.$1).whenComplete(() => finished = true);
          for (var frame = 0; frame < 100 && !finished; frame++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(finished, isTrue);
          expect(await change, isTrue);
          I18n.setLocale(state.$2);
          await tester.pumpAndSettle();
          await _reveal(tester);
          expect(theme.brand.id, state.$1);
          expect(updater.checking, isFalse);
          expect(updater.hasUpdate, isTrue);
          expect(updater.latestVersion, release.$2);
          expect(tester.state(find.byType(MineScreen)), same(screen));
          expect(ModalRoute.of(tester.element(find.byType(MineScreen))), same(route));
          expect(tester.takeException(), isNull);
          final name = '${release.$1}-${step++}-${state.$1}-${state.$2.storageValue}-320x844-scale200';
          final report = await _capture(tester, name, release.$2);
          report['brand'] = theme.brand.id;
          reports.add(report);
          final directory = Platform.environment['DUOYI_MINE_UPDATE_BADGE_SCREENSHOTS'];
          if (directory != null && directory.isNotEmpty) {
            await tester.runAsync(() async {
              final file = File('$directory/$name.json');
              if (file.existsSync()) throw StateError('Refusing to overwrite $file');
              file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
            });
          }
        }
      }
      // Enable only after baseline pixels have been retained and reviewed.
      if (Platform.environment['DUOYI_MINE_UPDATE_BADGE_REQUIRE_READABLE'] == '1') {
        for (final report in reports) {
          for (final probe in report['paragraphs']! as List<Map<String, Object?>>) {
            final reason = '${report['name']}: ${probe['text']}';
            expect(probe['didExceedMaxLines'], isFalse, reason: reason);
            expect(probe['scaled10px'], 20, reason: reason);
            expect(probe['transformScaleX'], closeTo(1, .001), reason: reason);
            expect(probe['transformScaleY'], closeTo(1, .001), reason: reason);
            expect(probe['fontWeight'], 400, reason: reason);
            for (final sample in probe['samples']! as List<Map<String, Object?>>) {
              expect(sample['ratio']! as double, greaterThanOrEqualTo(4.5), reason: reason);
            }
          }
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
