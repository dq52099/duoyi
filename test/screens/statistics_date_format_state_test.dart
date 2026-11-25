import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/statistics_ui_copy.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final locale in AppLocale.values) {
    testWidgets(
      '${locale.name} retained report share and clipboard follow date preferences',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        I18n.setLocale(locale);
        late PreferencesProvider preferences;
        await tester.runAsync(() async {
          preferences = PreferencesProvider();
          await preferences.loadFromStorage();
        });
        addTearDown(preferences.dispose);
        tester.view.physicalSize = const Size(800, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final writes = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              writes.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences,
              ),
              ChangeNotifierProvider(create: (_) => TodoProvider()),
              ChangeNotifierProvider(create: (_) => GoalProvider()),
              ChangeNotifierProvider(create: (_) => HabitProvider()),
              ChangeNotifierProvider(create: (_) => PomodoroProvider()),
              ChangeNotifierProvider(create: (_) => DiaryProvider()),
              ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
              ChangeNotifierProvider(create: (_) => AiService()),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ],
            child: const MaterialApp(
              home: BrandRouteSurface(child: StatisticsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final copy = StatisticsUiCopy(locale);
        await tester.tap(find.byTooltip(copy.copyReportTooltip));
        await tester.pumpAndSettle();
        final today = DateTime.now();
        final end = DateTime(today.year, today.month, today.day);
        expect(
          writes.single,
          contains(
            I18nDateFormat.date(end, pattern: 'yyyy-MM-dd', locale: locale),
          ),
        );
        await tester.tap(find.byTooltip(copy.reportShareImageTooltip));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        final stateBefore = tester.state(find.byType(StatisticsScreen));
        await tester.runAsync(() => preferences.setDateFormat('dd/MM/yyyy'));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(StatisticsScreen)), same(stateBefore));
        final formatted = I18nDateFormat.date(
          end,
          pattern: 'dd/MM/yyyy',
          locale: locale,
        );
        expect(
          find.descendant(of: dialog, matching: find.textContaining(formatted)),
          findsWidgets,
        );
        final copyText = find.widgetWithText(
          TextButton,
          copy.copyMarkdownAction,
        );
        await tester.ensureVisible(copyText);
        await tester.tap(copyText);
        await tester.pumpAndSettle();
        expect(writes.last, contains(formatted));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
