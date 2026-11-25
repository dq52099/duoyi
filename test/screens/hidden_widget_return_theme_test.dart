import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:duoyi/widgets/surface_components.dart';
import '../support/weekly_review_screenshot_font.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localePreferenceKey = 'duoyi_locale_v1';
const _bottomNavOrderPreferenceKey = 'pref_bottom_nav_order';
const _bottomNavVisiblePreferenceKey = 'pref_bottom_nav_visible';
const _defaultVisibleTabs = <int>[0, 1, 2, 5, 6];

class _StartupProviders {
  final PreferencesProvider preferences;
  final LocaleProvider locale;

  const _StartupProviders({required this.preferences, required this.locale});

  void dispose() {
    preferences.dispose();
    locale.dispose();
  }
}

Future<_StartupProviders> _prepareStartupProviders(
  WidgetTester tester, {
  required int defaultTab,
  AppLocale locale = AppLocale.zh,
  List<int> visibleTabs = _defaultVisibleTabs,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _localePreferenceKey: locale.storageValue,
    _bottomNavOrderPreferenceKey: List<String>.generate(7, (index) => '$index'),
    _bottomNavVisiblePreferenceKey: visibleTabs
        .map((tab) => tab.toString())
        .toList(),
  });

  late PreferencesProvider preferences;
  late LocaleProvider localeProvider;
  await tester.runAsync(() async {
    preferences = PreferencesProvider();
    localeProvider = LocaleProvider();
    // Match main(): hydrate persistent state before DuoyiApp creates MainShell.
    await preferences.loadFromStorage();
    await localeProvider.loadFromStorage();
    await preferences.setDefaultTab(defaultTab);
    await preferences.loadFromStorage();
  });
  I18n.setLocale(locale);

  expect(
    preferences.defaultTab,
    PreferencesProvider.normalizeDefaultTab(defaultTab),
  );
  expect(preferences.visibleBottomNavTabs, visibleTabs);
  expect(preferences.visibleBottomNavTabs, contains(6));
  return _StartupProviders(preferences: preferences, locale: localeProvider);
}

Widget _duoyiApp(_StartupProviders startup, ThemeProvider theme) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => theme),
      ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
      ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
      ChangeNotifierProvider(create: (_) => CountdownProvider()),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider<PreferencesProvider>.value(
        value: startup.preferences,
      ),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider<LocaleProvider>.value(value: startup.locale),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: const DuoyiApp(),
  );
}

void main() {
  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    WebTarget.debugDesktopWebBuild = null;
  });
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'ordinary', size: const Size(390, 844), scale: 1.0),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
      ]) {
        testWidgets('hidden widget return $brand ${locale.name} ${layout.name}', (
          tester,
        ) async {
          WebTarget.debugDesktopWebBuild = false;
          final startup = await _prepareStartupProviders(
            tester,
            defaultTab: 5,
            locale: locale,
            visibleTabs: const [0, 1, 2, 6],
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_brand', brand);
          final theme = ThemeProvider();
          await theme.loadFromStorage();
          expect(theme.brand.id, brand);
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = layout.scale;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            startup.dispose();
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(key: boundary, child: _duoyiApp(startup, theme)),
          );
          await tester.pumpAndSettle();
          expect(find.byType(WidgetScreen), findsOneWidget);
          final shell = tester.state<MainShellState>(find.byType(MainShell));
          final screen = tester.element(find.byType(WidgetScreen));
          final errors = <String>[];
          final rows = <Map<String, Object?>>[];
          Future<void> audit(String stage) async {
            final english = I18n.current == AppLocale.en;
            final hint = find.text(english ? 'Hidden feature' : '隐藏应用');
            final button = find.widgetWithText(
              FilledButton,
              english ? 'Back to Me' : '返回我的',
            );
            expect(hint, findsOneWidget);
            expect(button, findsOneWidget);
            final size = tester.getSize(button);
            if (size.width < 44 || size.height < 44) {
              errors.add(
                '$stage button target ${size.width}x${size.height} below44',
              );
            }
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: hint, matching: find.byType(RichText)),
            );
            final rect = MatrixUtils.transformRect(
              paragraph.getTransformTo(render),
              Offset.zero & paragraph.size,
            );
            final background = (await tester.runAsync(() async {
              final image = await render.toImage(pixelRatio: 1);
              try {
                final raw = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final offset =
                    (rect.center.dy.floor() * image.width +
                        (rect.left - 3).floor()) *
                    4;
                return Color.fromARGB(
                  255,
                  raw.getUint8(offset),
                  raw.getUint8(offset + 1),
                  raw.getUint8(offset + 2),
                );
              } finally {
                image.dispose();
              }
            }))!;
            final style = paragraph.text.style!;
            final foreground = Color.alphaBlend(style.color!, background);
            final ratio = appContrastRatio(background, foreground);
            final scaledSize = paragraph.textScaler.scale(style.fontSize!);
            final minimum = scaledSize >= 24 ? 3.0 : 4.5;
            if (ratio < minimum) {
              errors.add('$stage hint contrast $ratio below $minimum');
            }
            if (paragraph.didExceedMaxLines ||
                paragraph.textSize.height > paragraph.size.height + .1) {
              errors.add('$stage hint incomplete');
            }
            expect(button.hitTestable(), findsOneWidget);
            for (final target in [
              hint,
              find.descendant(of: button, matching: find.byType(Text)),
            ]) {
              final text = tester.renderObject<RenderParagraph>(
                find.descendant(of: target, matching: find.byType(RichText)),
              );
              final bounds = MatrixUtils.transformRect(
                text.getTransformTo(render),
                Offset.zero & text.size,
              );
              final content = text.text.toPlainText();
              if (text.didExceedMaxLines ||
                  text.textSize.width > text.size.width + .1 ||
                  text.textSize.height > text.size.height + .1) {
                errors.add('$stage $content incomplete');
              }
              if (bounds.left < -.1 ||
                  bounds.top < -.1 ||
                  bounds.right > layout.size.width + .1 ||
                  bounds.bottom > layout.size.height + .1) {
                errors.add('$stage $content outside viewport');
              }
              for (var i = 0; i < content.length; i++) {
                if (content[i].trim().isEmpty) {
                  continue;
                }
                for (final glyph in text.getBoxesForSelection(
                  TextSelection(baseOffset: i, extentOffset: i + 1),
                )) {
                  // A font's selection box can exceed its nominal line box.
                  // Compare painted bounds with the actual containing surface.
                  final glyphBounds = MatrixUtils.transformRect(
                    text.getTransformTo(render),
                    glyph.toRect(),
                  );
                  final allowed = target == hint
                      ? tester.getRect(
                          find
                              .ancestor(
                                of: hint,
                                matching: find.byType(SafeArea),
                              )
                              .first,
                        )
                      : tester.getRect(button);
                  if (glyphBounds.left < allowed.left - .1 ||
                      glyphBounds.right > allowed.right + .1 ||
                      glyphBounds.top < allowed.top - .1 ||
                      glyphBounds.bottom > allowed.bottom + .1) {
                    errors.add('$stage $content glyph $i outside $allowed');
                  }
                  if (target == hint &&
                      glyphBounds.overlaps(tester.getRect(button))) {
                    errors.add('$stage hint glyph $i overlaps return button');
                  }
                }
              }
            }
            final exception = tester.takeException();
            if (exception != null) {
              errors.add('$stage framework: $exception');
            }
            rows.add({
              'stage': stage,
              'locale': I18n.current.name,
              'brand': theme.brand.id,
              'buttonWidth': size.width,
              'buttonHeight': size.height,
              'hintContrast': ratio,
              'hintMinimum': minimum,
              'hintWidth': paragraph.size.width,
              'hintHeight': paragraph.size.height,
            });
            await tester.runAsync(() async {
              final dir =
                  Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
              if (dir == null) {
                return;
              }
              final image = await render.toImage(pixelRatio: 1);
              try {
                final png = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                final file = File(
                  '$dir/hidden-return-$brand-${locale.name}-${layout.name}-$stage.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(png.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }

          await audit('initial');
          await tester.runAsync(
            () => startup.locale.setLocale(
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            ),
          );
          expect(startup.locale.locale, I18n.current);
          await theme.setBrand(
            brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
          );
          await tester.pumpAndSettle();
          expect(
            tester.state<MainShellState>(find.byType(MainShell)),
            same(shell),
          );
          expect(tester.element(find.byType(WidgetScreen)), same(screen));
          await audit('mounted-switch');
          await tester.runAsync(() async {
            final dir =
                Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
            if (dir == null) {
              return;
            }
            final file = File(
              '$dir/hidden-return-$brand-${locale.name}-${layout.name}.json',
            );
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({'rows': rows, 'errors': errors}),
            );
          });
          final label = I18n.current == AppLocale.en ? 'Back to Me' : '返回我的';
          final target = tester.getRect(
            find.widgetWithText(FilledButton, label),
          );
          await tester.tapAt(Offset(target.center.dx, target.bottom - 1));
          await tester.pumpAndSettle();
          expect(find.byType(MineScreen), findsOneWidget);
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(errors, isEmpty);
        });
      }
    }
  }
}
