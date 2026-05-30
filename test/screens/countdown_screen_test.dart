import 'dart:convert';

import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('empty countdown page exposes add entry and creates countdown', (
    tester,
  ) async {
    final provider = CountdownProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无倒数日记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown_add_button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countdown_add_button')),
        matching: find.text('添加'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '版本发布');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('countdown_editor_save_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '版本发布');
  });

  testWidgets('more applications entry opens countdown and can add countdown', (
    tester,
  ) async {
    final provider = CountdownProvider();
    await provider.loadFromStorage();
    final preferences = PreferencesProvider();
    final theme = ThemeProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider.value(value: preferences),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: const MaterialApp(
          home: MoreApplicationsScreen(visibleBottomNavTabs: [0, 1, 2, 3, 6]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MoreApplicationsScreen), findsOneWidget);
    expect(find.text('倒数日'), findsOneWidget);

    await tester.tap(find.text('倒数日'));
    await tester.pumpAndSettle();

    expect(find.byType(CountdownScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '从入口新增');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('countdown_editor_save_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '从入口新增');
  });

  testWidgets('existing countdown can still be edited', (tester) async {
    SharedPreferences.setMockInitialValues({
      'duoyi_countdowns': [
        jsonEncode({
          'id': 'release',
          'title': '版本发布',
          'targetDate': '2026-06-01T00:00:00.000',
        }),
      ],
    });

    final provider = CountdownProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('版本发布'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '版本补丁发布');
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('countdown_editor_save_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '版本补丁发布');
    expect(find.text('版本补丁发布'), findsOneWidget);
  });

  testWidgets(
    'existing countdown left swipe reveals delete action and confirms',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'duoyi_countdowns': [
          jsonEncode({
            'id': 'release',
            'title': '版本发布',
            'targetDate': '2026-06-01T00:00:00.000',
          }),
        ],
      });

      final provider = CountdownProvider();
      await provider.loadFromStorage();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(home: CountdownScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('版本发布'), findsOneWidget);

      await tester.drag(find.text('版本发布'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(provider.items, hasLength(1));
      expect(
        find.byKey(const ValueKey('countdown_swipe_delete_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('countdown_swipe_delete_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('确认删除？'), findsOneWidget);
      expect(provider.items, hasLength(1));

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(provider.items, isEmpty);
      expect(find.text('版本发布'), findsNothing);
      expect(find.text('暂无倒数日记录'), findsOneWidget);
    },
  );

  testWidgets('existing countdown can be deleted from editor', (tester) async {
    SharedPreferences.setMockInitialValues({
      'duoyi_countdowns': [
        jsonEncode({
          'id': 'release',
          'title': '版本发布',
          'targetDate': '2026-06-01T00:00:00.000',
        }),
      ],
    });

    final provider = CountdownProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('版本发布'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('确认删除？'), findsOneWidget);
    expect(provider.items, hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(provider.items, isEmpty);
    expect(find.text('版本发布'), findsNothing);
    expect(find.text('暂无倒数日记录'), findsOneWidget);
  });

  testWidgets('fixed countdown anniversary page has no add entry', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: AnniversaryScreen(fixedType: AnniversaryType.normal),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('添加'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(provider.items, isEmpty);
  });

  testWidgets('BirthdayScreen add creates birthday anniversary', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: BirthdayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BirthdayScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('天气'), findsNothing);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '测试生日');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '添加').last);
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '测试生日');
    expect(provider.items.single.type, AnniversaryType.birthday);
    expect(provider.birthdays, hasLength(1));
    expect(provider.memorials, isEmpty);
    expect(provider.countdowns, isEmpty);
  });

  testWidgets('MemorialAnniversaryScreen add creates memorial anniversary', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MemorialAnniversaryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MemorialAnniversaryScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('天气'), findsNothing);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '测试纪念日');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '添加').last);
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '测试纪念日');
    expect(provider.items.single.type, AnniversaryType.memorial);
    expect(provider.birthdays, isEmpty);
    expect(provider.memorials, hasLength(1));
    expect(provider.countdowns, isEmpty);
  });

  testWidgets('anniversary card left swipe reveals matching delete action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'duoyi_anniversaries_v2': [
        jsonEncode(
          Anniversary(
            id: 'birthday',
            title: '生日提醒',
            originDate: DateTime(2026, 7, 1),
            type: AnniversaryType.birthday,
          ).toJson(),
        ),
      ],
    });

    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: AnniversaryScreen(fixedType: AnniversaryType.birthday),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生日提醒'), findsOneWidget);

    await tester.drag(find.text('生日提醒'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(
      find.byKey(const ValueKey('anniversary_swipe_delete_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('anniversary_swipe_delete_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('确认删除？'), findsOneWidget);
    expect(provider.items, hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(provider.items, isEmpty);
    expect(find.text('生日提醒'), findsNothing);
    expect(find.text('还没有任何纪念'), findsOneWidget);
  });

  testWidgets('direct normal anniversary editor creates memorial instead', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAnniversaryEditor(
                context,
                fixedType: AnniversaryType.normal,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('倒数日'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '不会新增倒数日');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.type, AnniversaryType.memorial);
    expect(provider.countdowns, isEmpty);
  });
}
