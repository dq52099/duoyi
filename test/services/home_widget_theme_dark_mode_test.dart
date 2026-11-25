import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_focus_projection.dart';
import 'package:duoyi/services/widget_habit_progress.dart';
import 'package:duoyi/services/widget_schedule_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrastRatio(Color foreground, Color background) {
  final effectiveFg = foreground.a < 1.0
      ? Color.alphaBlend(foreground, background)
      : foreground;
  final l1 = effectiveFg.computeLuminance();
  final l2 = background.computeLuminance();
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  group('Default iOS System Blue (#0066D6) & Dark Mode widget palettes', () {
    test(
      'accountPayloadDefaults uses #FF0066D6 system blue and matches fresh provider',
      () {
        final provider = ThemeProvider();
        addTearDown(provider.dispose);
        final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
        final defaults = HomeWidgetService.accountPayloadDefaults;

        expect(defaults['widget_theme_primary'], '#FF0066D6');
        expect(defaults['widget_theme_accent_start'], '#FF0066D6');
        expect(defaults['widget_theme_accent_end'], '#FF3898FF');
        expect(defaults['widget_theme_border'], '#000066D6');
        expect(defaults['widget_theme_background'], '#FFF6F7F9');
        expect(defaults['widget_theme_dark'], false);
        final themeDefaults = <String, Object>{
          for (final entry in defaults.entries)
            if (entry.key.startsWith('widget_theme_')) entry.key: entry.value,
        };
        expect(payload.payloadValues, themeDefaults);
      },
    );

    test(
      'defaultBrand darkVariantFor and darkOverride emit dark system blue tokens with AA contrast',
      () {
        final plainSkin = ThemeProvider.cardSkinRewards.singleWhere(
          (skin) => skin.id == ThemeProvider.defaultCardSkinId,
        );
        final darkPayload = HomeWidgetThemePayload.darkVariantFor(
          AppBrands.defaultBrand,
          plainSkin,
        );
        final provider = _PaletteProvider(AppBrands.defaultBrand, plainSkin);
        addTearDown(provider.dispose);
        final fromOverride = HomeWidgetThemePayload.fromThemeProvider(
          provider,
          darkOverride: true,
        );

        expect(darkPayload.dark, isTrue);
        expect(darkPayload.primary, const Color(0xFF0A84FF));
        expect(darkPayload.accentStart, const Color(0xFF0A84FF));
        expect(darkPayload.accentEnd, const Color(0xFF409CFF));
        expect(darkPayload.background, const Color(0xFF14171F));
        expect(darkPayload.surface, const Color(0xFF1C212B));
        expect(darkPayload.navBackground, const Color(0xFF242A36));
        expect(darkPayload.border, const Color(0xFF2F3847));
        expect(darkPayload.text, const Color(0xFFF2F5FA));
        expect(darkPayload.mutedText, const Color(0xFFA5B0C2));
        expect(darkPayload.onPrimary, const Color(0xFFFFFFFF));
        expect(fromOverride.payloadValues, darkPayload.payloadValues);

        for (final surface in [darkPayload.background, darkPayload.surface]) {
          expect(
            _contrastRatio(darkPayload.text, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrastRatio(darkPayload.mutedText, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      },
    );

    test(
      'liquidGlass darkVariantFor and darkOverride emit dark frosted glass tokens with AA contrast',
      () {
        final plainSkin = ThemeProvider.cardSkinRewards.singleWhere(
          (skin) => skin.id == ThemeProvider.defaultCardSkinId,
        );
        final glassDark = HomeWidgetThemePayload.darkVariantFor(
          AppBrands.liquidGlass,
          plainSkin,
        );
        final provider = _PaletteProvider(AppBrands.liquidGlass, plainSkin);
        addTearDown(provider.dispose);
        final fromOverride = HomeWidgetThemePayload.fromThemeProvider(
          provider,
          darkOverride: true,
        );

        expect(glassDark.dark, isTrue);
        expect(glassDark.primary, const Color(0xFF0A84FF));
        expect(glassDark.accentStart, const Color(0xFF0A84FF));
        expect(glassDark.accentEnd, const Color(0xFF5AC8FA));
        expect(glassDark.background, const Color(0xE6161B24));
        expect(glassDark.surface, const Color(0xD91F2633));
        expect(glassDark.navBackground, const Color(0xCC283142));
        expect(glassDark.border, const Color(0xFF3A465C));
        expect(glassDark.text, const Color(0xFFF5F8FC));
        expect(glassDark.mutedText, const Color(0xFFB0BCD0));
        expect(glassDark.onPrimary, const Color(0xFFFFFFFF));
        expect(fromOverride.payloadValues, glassDark.payloadValues);

        const darkWallpaperBase = Color(0xFF0B0F17);
        final effectiveBg = Color.alphaBlend(
          glassDark.background,
          darkWallpaperBase,
        );
        final effectiveSurface = Color.alphaBlend(
          glassDark.surface,
          effectiveBg,
        );
        expect(
          _contrastRatio(glassDark.text, effectiveBg),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(glassDark.text, effectiveSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(glassDark.mutedText, effectiveBg),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(glassDark.mutedText, effectiveSurface),
          greaterThanOrEqualTo(4.5),
        );
      },
    );

    test(
      'all 36 (AppBrand, CardSkinReward) combos preserve readable text contrast',
      () {
        for (final brand in AppBrands.all) {
          for (final skin in ThemeProvider.cardSkinRewards) {
            final provider = _PaletteProvider(brand, skin);
            final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
            provider.dispose();

            expect(
              _contrastRatio(payload.text, payload.surface),
              greaterThanOrEqualTo(4.5),
              reason: '${brand.id}/${skin.id} text on surface',
            );
            expect(
              _contrastRatio(payload.text, payload.background),
              greaterThanOrEqualTo(4.5),
              reason: '${brand.id}/${skin.id} text on background',
            );
          }
        }
      },
    );
  });

  group('Widget projection helpers', () {
    test('focus progress and localized status labels reflect timer state', () {
      const idle = PomodoroState(
        remainingSeconds: 1500,
        totalSeconds: 1500,
        isRunning: false,
        type: PomodoroType.focus,
        completedSessions: 0,
      );
      const running = PomodoroState(
        remainingSeconds: 900,
        totalSeconds: 1500,
        isRunning: true,
        type: PomodoroType.focus,
        completedSessions: 1,
      );
      const paused = PomodoroState(
        remainingSeconds: 600,
        totalSeconds: 1500,
        isRunning: false,
        type: PomodoroType.focus,
        completedSessions: 1,
      );
      const onBreak = PomodoroState(
        remainingSeconds: 180,
        totalSeconds: 300,
        isRunning: true,
        type: PomodoroType.shortBreak,
        completedSessions: 2,
      );

      expect(widgetFocusProgressRatio(idle), 0.0);
      expect(widgetFocusProgressRatio(running), closeTo(0.4, 1e-6));
      expect(widgetFocusProgressRatio(paused), closeTo(0.6, 1e-6));
      expect(widgetFocusStateLabel(idle, locale: AppLocale.zh), '待开始');
      expect(widgetFocusStateLabel(running, locale: AppLocale.zh), '专注中');
      expect(widgetFocusStateLabel(paused, locale: AppLocale.zh), '已暂停');
      expect(widgetFocusStateLabel(onBreak, locale: AppLocale.en), 'On Break');
    });

    test('calendar lunar summary, holiday badge, and habit ratio helpers', () {
      expect(homeWidgetCalendarDayBadge(DateTime(2026, 5, 1)), '休');
      expect(homeWidgetCalendarDayBadge(DateTime(2026, 4, 26)), '班');
      expect(homeWidgetCalendarDayBadge(DateTime(2026, 5, 17)), isNull);

      final summaryZh = homeWidgetCalendarSummary(
        DateTime(2026, 5, 17),
        locale: AppLocale.zh,
      );
      expect(summaryZh, contains('农历'));

      expect(
        widgetHabitCompletionRatio(activeCount: 4, completedCount: 3),
        closeTo(0.75, 1e-6),
      );
      expect(
        widgetHabitSummaryRatioText(activeCount: 4, completedCount: 3),
        '3/4',
      );
    });
  });

  group('WidgetScreen preview toolbar & live/dark toggles', () {
    testWidgets(
      'toggles Sample/Real Data, Light/Dark preview, and navigates to ThemePickerScreen',
      (tester) async {
        final theme = ThemeProvider();
        final auth = AuthProvider();
        final achievements = AchievementProvider();
        final todos = TodoProvider();
        final habits = HabitProvider();
        final pomodoro = PomodoroProvider();
        final goals = GoalProvider();
        addTearDown(() async {
          await AccountPreferenceWrites.drain();
          await tester.pumpWidget(const SizedBox.shrink());
          theme.dispose();
          auth.dispose();
          achievements.dispose();
          todos.dispose();
          habits.dispose();
          pomodoro.dispose();
          goals.dispose();
        });

        await todos.addTodo(
          TodoItem(title: 'Live Sync Task', date: DateTime.now()),
        );
        await habits.addHabit(
          Habit(id: 'h1', name: 'Morning Run'),
        );
        await goals.add(
          GoalItem(
            title: 'Real Goal Item',
            progress: 0.75,
            autoProgress: false,
          ),
        );

        await tester.binding.setSurfaceSize(const Size(412, 915));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AchievementProvider>.value(
                value: achievements,
              ),
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
              ChangeNotifierProvider<GoalProvider>.value(value: goals),
            ],
            child: const MaterialApp(
              home: WidgetScreen(hostPlatform: WidgetHostPlatform.ios),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> reveal(Finder target) async {
          final scrollable = find.byType(Scrollable).first;
          if (target.evaluate().isEmpty) {
            tester.state<ScrollableState>(scrollable).position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              target,
              120.0,
              scrollable: scrollable,
            );
          }
          await Scrollable.ensureVisible(
            tester.element(target),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
        }

        // Default sample mode preserves WidgetUiCopy sample strings.
        await reveal(find.text(WidgetUiCopy.todoItem1));
        expect(find.text(WidgetUiCopy.todoItem1), findsOneWidget);

        // Reveal preview toolbar below the first catalog card.
        await reveal(find.byKey(const ValueKey('widget_preview_toolbar')));
        expect(
          find.byKey(const ValueKey('widget_preview_toolbar')),
          findsOneWidget,
        );
        expect(find.text('示例预览'), findsOneWidget);
        expect(find.text('实时数据'), findsOneWidget);
        expect(find.text('浅色'), findsOneWidget);
        expect(find.text('深色'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('widget_open_theme_studio')),
          findsOneWidget,
        );

        // Switch to Dark preview & Real Data via toolbar.
        await reveal(find.text('实时数据'));
        await tester.tap(find.text('实时数据'));
        await tester.pumpAndSettle();
        await reveal(find.text('深色'));
        await tester.tap(find.text('深色'));
        await tester.pumpAndSettle();

        await reveal(find.text('Live Sync Task'));
        expect(find.text('Live Sync Task'), findsOneWidget);

        final todoSurface = find.descendant(
          of: find.byKey(const ValueKey('widget_gallery_todo')),
          matching: find.byKey(const ValueKey('widget_preview_surface')),
        );
        final boxDecoration =
            tester.widget<Container>(todoSurface).decoration! as BoxDecoration;
        expect(boxDecoration.color, const Color(0xFF14171F));

        // Scroll to toolbar and open Theme Studio.
        await reveal(find.byKey(const ValueKey('widget_open_theme_studio')));
        await tester.tap(find.byKey(const ValueKey('widget_open_theme_studio')));
        await tester.pumpAndSettle();
        expect(find.byType(ThemePickerScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _PaletteProvider extends ThemeProvider {
  _PaletteProvider(this.widgetBrand, this.widgetSkin);

  final AppBrand widgetBrand;
  final CardSkinReward widgetSkin;

  @override
  AppBrand get activeWidgetBackgroundBrand => widgetBrand;

  @override
  CardSkinReward get activeWidgetCardSkin => widgetSkin;
}
