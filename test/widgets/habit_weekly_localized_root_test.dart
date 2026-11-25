import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/habit_weekly_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets('const weekly card follows localized root $brand', (
      tester,
    ) async {
      final habits = HabitProvider();
      var habitNotifications = 0;
      habits.addListener(() => habitNotifications++);
      final originalHabits = jsonEncode(
        habits.habits.map((h) => h.toJson()).toList(),
      );
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          httpClient: MockClient((_) async => fail('No fixture HTTP allowed')),
        ),
      );
      await mountPriorityFixture(
        tester,
        auth: auth,
        brand: brand,
        locale: AppLocale.zh,
        size: const Size(390, 844),
        scale: 2,
        home: ChangeNotifierProvider<HabitProvider>(
          create: (_) => habits,
          child: const Scaffold(
            body: CustomScrollView(
              slivers: [SliverToBoxAdapter(child: HabitWeeklyCard())],
            ),
          ),
        ),
      );
      final card = find.byType(HabitWeeklyCard);
      final originalElement = tester.element(card);
      final preferences = await SharedPreferences.getInstance();
      Map<String, Object?> preferenceSnapshot() => {
        for (final key in preferences.getKeys()) key: preferences.get(key),
      };
      final originalPreferences = preferenceSnapshot();
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        // The fixture updates MaterialApp.locale and real delegates, matching
        // the production localization dependency. The const subtree is reused.
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(card), same(originalElement));
        final context = tester.element(card);
        expect(Localizations.localeOf(context).languageCode, locale.name);
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              context.read<ThemeProvider>().brand.strings.habitWeekOverview,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(MainUiCopy.habitNoHabits),
          ),
          findsOneWidget,
        );
        for (var day = 1; day <= 7; day++) {
          expect(
            find.descendant(
              of: card,
              matching: find.text(I18n.tr('habit.weekday.$day')),
            ),
            findsWidgets,
          );
        }
        expect(tester.takeException(), isNull);
      }
      expect(habitNotifications, 0);
      expect(
        jsonEncode(habits.habits.map((h) => h.toJson()).toList()),
        originalHabits,
      );
      expect(preferenceSnapshot(), originalPreferences);
    });
  }
}
