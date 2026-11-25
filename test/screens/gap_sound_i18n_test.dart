import 'dart:convert';

import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/focus_sound_catalog.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/core/todo_filters.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPomodoroProvider extends PomodoroProvider {
  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async =>
      const FocusDndStatus.unavailable();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cjkPattern = RegExp(r'[\u3400-\u9fff]');

  setUp(() {
    final originalLocale = I18n.current;
    addTearDown(() => I18n.setLocale(originalLocale));
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Gap 4: FocusSoundCatalog category grouping', () {
    test('all 28 tracks appear in exact category groups without duplicates or gaps', () {
      expect(FocusSoundCatalog.tracks, hasLength(28));
      expect(FocusSoundCatalog.options, hasLength(29));
      expect(FocusSoundCatalog.noneOption.id, FocusSoundCatalog.none);
      expect(FocusSoundCatalog.noneOption.category, isNull);

      final grouped = FocusSoundCatalog.groupedOptions;
      expect(
        grouped.map((g) => g.category).toList(),
        FocusSoundCategory.values,
      );

      final groupedIds = <String>[];
      for (final group in grouped) {
        expect(group.options, isNotEmpty, reason: group.category.name);
        for (final option in group.options) {
          expect(option.isNone, isFalse);
          expect(option.category, group.category);
          expect(FocusSoundCatalog.trackFor(option.id)?.category, group.category);
          expect(FocusSoundCatalog.optionFor(option.id)?.category, group.category);
          groupedIds.add(option.id);
        }
      }

      expect(groupedIds, hasLength(28));
      expect(groupedIds.toSet(), hasLength(28));
      expect(
        groupedIds.toSet(),
        FocusSoundCatalog.tracks.map((track) => track.id).toSet(),
      );
      expect(groupedIds, isNot(contains(FocusSoundCatalog.none)));
    });

    test('category headers localize cleanly in zh and en without CJK leaks', () {
      for (final category in FocusSoundCategory.values) {
        final zhHeader = category.displayLabel(locale: AppLocale.zh);
        final enHeader = category.displayLabel(locale: AppLocale.en);
        expect(zhHeader, isNotEmpty);
        expect(cjkPattern.hasMatch(zhHeader), isTrue, reason: category.name);
        expect(enHeader, isNotEmpty);
        expect(cjkPattern.hasMatch(enHeader), isFalse, reason: category.name);
        expect(zhHeader, isNot(equals(enHeader)));
      }
    });
  });

  group('Gap 4: Sound-picker modal category rendering', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      testWidgets(
        'renders category headers and tracks in $brandId across zh and en',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          SharedPreferences.setMockInitialValues(<String, Object>{
            'theme_shop_state': jsonEncode({
              'activeBrand': brandId,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            }),
          });

          final theme = ThemeProvider();
          await theme.loadFromStorage();
          expect(theme.brand.id, brandId);

          final pomodoro = _TestPomodoroProvider();
          final rooms = FocusRoomProvider();
          final sounds = CustomFocusSoundProvider();
          final auth = AuthProvider();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            pomodoro.dispose();
            rooms.dispose();
            sounds.dispose();
            auth.dispose();
            theme.dispose();
          });

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
                ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
                ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                  value: sounds,
                ),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, currentTheme, _) => MaterialApp(
                  theme: currentTheme.brand.theme,
                  home: const PomodoroScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final noiseTile = find.text(FocusRoomUiCopy.whiteNoiseLabel(AppLocale.zh));
          await tester.ensureVisible(noiseTile);
          await tester.tap(noiseTile);
          await tester.pumpAndSettle();

          final sheet = find.byType(AppModalSheet);
          expect(sheet, findsOneWidget);
          expect(
            find.descendant(
              of: sheet,
              matching: find.text(
                FocusSoundCatalog.noneOption.displayLabel(locale: AppLocale.zh),
              ),
            ),
            findsOneWidget,
          );
          for (final group in FocusSoundCatalog.groupedOptions) {
            final headerFinder = find.descendant(
              of: sheet,
              matching: find.text(group.category.displayLabel(locale: AppLocale.zh)),
            );
            await tester.scrollUntilVisible(
              headerFinder,
              220,
              scrollable: find.descendant(
                of: sheet,
                matching: find.byType(Scrollable),
              ).first,
            );
            expect(headerFinder, findsOneWidget);
          }

          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: sheet,
              matching: find.text(
                FocusSoundCatalog.noneOption.displayLabel(locale: AppLocale.en),
              ),
            ),
            findsOneWidget,
          );
          for (final group in FocusSoundCatalog.groupedOptions) {
            final headerFinder = find.descendant(
              of: sheet,
              matching: find.text(group.category.displayLabel(locale: AppLocale.en)),
            );
            await tester.scrollUntilVisible(
              headerFinder,
              220,
              scrollable: find.descendant(
                of: sheet,
                matching: find.byType(Scrollable),
              ).first,
            );
            expect(headerFinder, findsOneWidget);
          }

          final sheetTexts = tester
              .widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text)))
              .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          expect(
            sheetTexts.where(cjkPattern.hasMatch),
            isEmpty,
            reason: 'English sound picker modal leaked CJK text',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('Gap 5: Localized strings across pomodoro, todo, and admin', () {
    test('FocusRoomUiCopy and AdminUiCopy switch cleanly between zh and en', () {
      expect(FocusRoomUiCopy.selfDisplayNameFallback(AppLocale.zh), '我');
      expect(FocusRoomUiCopy.selfDisplayNameFallback(AppLocale.en), 'Me');
      expect(FocusRoomUiCopy.rankingBadge(true, AppLocale.zh), '服务端排行');
      expect(FocusRoomUiCopy.rankingBadge(true, AppLocale.en), 'Server ranking');
      expect(FocusRoomUiCopy.rankingBadge(false, AppLocale.zh), '本地排行');
      expect(FocusRoomUiCopy.rankingBadge(false, AppLocale.en), 'Local ranking');
      expect(FocusRoomUiCopy.previewAudioTooltip(AppLocale.zh), '试听');
      expect(FocusRoomUiCopy.previewAudioTooltip(AppLocale.en), 'Preview');
      expect(
        FocusRoomUiCopy.deleteCustomAudioTooltip(AppLocale.zh),
        '删除自定义音频',
      );
      expect(
        FocusRoomUiCopy.deleteCustomAudioTooltip(AppLocale.en),
        'Delete custom sound',
      );

      for (final enText in [
        FocusRoomUiCopy.selfDisplayNameFallback(AppLocale.en),
        FocusRoomUiCopy.rankingBadge(true, AppLocale.en),
        FocusRoomUiCopy.rankingBadge(false, AppLocale.en),
        FocusRoomUiCopy.previewAudioTooltip(AppLocale.en),
        FocusRoomUiCopy.deleteCustomAudioTooltip(AppLocale.en),
      ]) {
        expect(cjkPattern.hasMatch(enText), isFalse, reason: enText);
      }

      const permissionKeys = [
        'settings',
        'users',
        'coins',
        'backup',
        'ai',
        'announcements',
        'feedback',
        'invites',
        'audit',
        'groups',
        'roles',
        'permissions',
        '*',
      ];
      for (final key in permissionKeys) {
        final zhLabel = AdminUiCopy.permissionLabel(key, AppLocale.zh);
        final enLabel = AdminUiCopy.permissionLabel(key, AppLocale.en);
        expect(zhLabel, isNotEmpty);
        expect(enLabel, isNotEmpty);
        expect(cjkPattern.hasMatch(enLabel), isFalse, reason: '$key: $enLabel');
      }

      const groupTitles = ['基础功能', '个人数据', '管理功能', '系统功能'];
      for (final title in groupTitles) {
        final enTitle = AdminUiCopy.permissionGroupTitle(title, AppLocale.en);
        expect(enTitle, isNotEmpty);
        expect(cjkPattern.hasMatch(enTitle), isFalse, reason: '$title: $enTitle');
      }

      for (var i = 0; i < 10; i++) {
        final zhTab = AdminUiCopy.tabTitleForIndex(i, AppLocale.zh);
        final enTab = AdminUiCopy.tabTitleForIndex(i, AppLocale.en);
        expect(zhTab, isNotEmpty);
        expect(enTab, isNotEmpty);
        expect(cjkPattern.hasMatch(enTab), isFalse, reason: 'tab $i: $enTab');
      }
    });

    testWidgets(
      'Pomodoro Study Rooms tab localizes fallback display name and ranking badge',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final pomodoro = _TestPomodoroProvider();
        final rooms = FocusRoomProvider();
        final sounds = CustomFocusSoundProvider();
        final auth = AuthProvider();
        final theme = ThemeProvider();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          pomodoro.dispose();
          rooms.dispose();
          sounds.dispose();
          auth.dispose();
          theme.dispose();
        });

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
              ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
              ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                value: sounds,
              ),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ],
            child: const MaterialApp(home: PomodoroScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(FocusRoomUiCopy.roomTab(AppLocale.zh)));
        await tester.pumpAndSettle();
        expect(find.text('我'), findsWidgets);
        final roomScroll = find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last;
        await tester.scrollUntilVisible(
          find.text('本地排行'),
          200,
          scrollable: roomScroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('本地排行'), findsOneWidget);

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Local ranking'),
          200,
          scrollable: roomScroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('Me'), findsWidgets);
        expect(find.text('Local ranking'), findsOneWidget);
        expect(find.text('我'), findsNothing);
        expect(find.text('本地排行'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TodoScreen List view renders ungrouped header in zh and en without leaking CJK',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final todos = TodoProvider();
        await todos.addTodo(
          TodoItem(
            id: 'ungrouped-task',
            title: 'Ungrouped fixture task',
            quadrant: EisenhowerQuadrant.urgentImportant,
          ),
        );
        final preferences = PreferencesProvider();
        final habits = HabitProvider();
        final goals = GoalProvider();
        final theme = ThemeProvider();
        final ai = AiService();
        final share = ShareProvider();
        final auth = AuthProvider();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          todos.dispose();
          preferences.dispose();
          habits.dispose();
          goals.dispose();
          theme.dispose();
          ai.dispose();
          share.dispose();
          auth.dispose();
        });

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences,
              ),
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider<GoalProvider>.value(value: goals),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AiService>.value(value: ai),
              ChangeNotifierProvider<ShareProvider>.value(value: share),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ],
            child: const MaterialApp(home: TodoScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(TodoBoardUiCopy.viewList));
        await tester.pumpAndSettle();
        expect(find.text(ungroupedTodoListName), findsOneWidget);

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(find.text('Ungrouped'), findsOneWidget);
        expect(find.text(ungroupedTodoListName), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
