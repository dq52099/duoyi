import 'dart:convert';

import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'diary editor lunar context updates while drafts and selection stay',
    (tester) async {
      final date = DateTime(2023, 3, 22);
      final lunar = LunarCalendar.fromSolar(date);
      expect(lunar.isLeapMonth, isTrue);
      final entry = DiaryEntry(
        id: 'lunar-diary',
        date: date,
        content: '用户正文 stays unchanged',
        mood: Mood.good,
        weather: Weather.sunny,
        tags: ['用户标签'],
      );
      final before = jsonEncode(entry.toJson());
      final provider = DiaryProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            home: BrandRouteSurface(child: DiaryEditScreen(entry: entry)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(DiaryEditScreen));
      final contentField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == entry.content,
      );
      final content = tester.widget<TextField>(contentField).controller!;
      final currentContentField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == I18n.tr('diary.editor.content_hint'),
      );
      final contentFocus = tester
          .widget<EditableText>(
            find.descendant(
              of: currentContentField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      contentFocus.requestFocus();
      content.value = const TextEditingValue(
        text: '等待中的新草稿',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      final tagField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == I18n.tr('diary.editor.tag_hint'),
      );
      final tag = tester.widget<TextField>(tagField).controller!;
      tag.text = '未添加的标签';
      await tester.pumpAndSettle();
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(DiaryEditScreen)), same(state));
        expect(
          tester.widget<TextField>(currentContentField).controller,
          same(content),
        );
        expect(tester.widget<TextField>(tagField).controller, same(tag));
        expect(contentFocus.hasFocus, isTrue);
        expect(
          tester
              .widgetList<FilterChip>(find.byType(FilterChip))
              .where((chip) => chip.selected),
          hasLength(1),
        );
        expect(
          find.text(AlmanacLocaleFormat.formatLunarDate(lunar)),
          findsOneWidget,
        );
        expect(content.text, '等待中的新草稿');
        expect(
          content.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(tag.text, '未添加的标签');
        expect(jsonEncode(entry.toJson()), before);
        expect(provider.entries, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'diary card lunar day follows live locale without changing entry',
    (tester) async {
      final date = DateTime(2026, 2, 17);
      final lunar = LunarCalendar.fromSolar(date);
      final provider = DiaryProvider();
      final entry = DiaryEntry(id: 'card', date: date, content: '用户原文');
      await provider.addOrUpdate(entry);
      addTearDown(provider.dispose);
      final before = jsonEncode(entry.toJson());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: BrandRouteSurface(child: DiaryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(lunar.dayChineseText),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(Scrollable).first), same(scroll));
        expect(scroll.position.pixels, offset);
        expect(
          find.text(AlmanacLocaleFormat.formatLunarDay(lunar)),
          findsOneWidget,
        );
        expect(find.text(entry.content), findsWidgets);
        expect(jsonEncode(entry.toJson()), before);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('opened diary picker translates its header live', (tester) async {
    final provider = DiaryProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: BrandRouteSurface(
            child: DiaryEditScreen(initialDate: DateTime(2023, 3, 22)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('diary.editor.date_title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    final cancel = find.descendant(
      of: find.byType(AppModalSheet).last,
      matching: find.text(I18n.tr('action.cancel')),
    );
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
