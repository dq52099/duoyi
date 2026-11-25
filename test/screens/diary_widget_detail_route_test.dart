import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets('historical diary detail identity $brand ${locale.name}', (
        tester,
      ) async {
        final historical = DiaryEntry(
          id: 'diary /?#&=% 测试🌙',
          date: DateTime(2001, 1, 2),
          content: 'Historical entry\n用户正文',
          mood: Mood.good,
        );
        final newer = DiaryEntry(
          id: 'newer-diary',
          date: DateTime(2002, 3, 4),
          content: 'A different entry',
        );
        final stored = [
          newer,
          historical,
        ].map((entry) => jsonEncode(entry.toJson())).toList();
        SharedPreferences.setMockInitialValues({
          'active_brand': brand,
          'duoyi_diary': stored,
        });
        I18n.setLocale(locale);
        final diaries = DiaryProvider();
        final theme = ThemeProvider();
        try {
          await diaries.loadFromStorage();
          await theme.loadFromStorage();
          expect(theme.brand.id, brand);
          expect(diaries.entries.first.id, newer.id);
          // The receiver decodes one opaque path segment before routing.
          // This test starts at that contract; it does not launch a native URL.
          final uri = Uri.parse(
            'duoyi://diary/${Uri.encodeComponent(historical.id)}',
          );
          expect(uri.pathSegments, [historical.id]);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<DiaryProvider>.value(value: diaries),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ],
              child: MaterialApp(
                theme: theme.brand.theme,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => TodayDetailRouter.open(
                        context,
                        TodaySectionKind.diary,
                        id: uri.pathSegments.first,
                      ),
                      child: const Text('Open published diary'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open published diary'));
          await tester.pumpAndSettle();
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          final editor = tester.widget<DiaryEditScreen>(
            find.byType(DiaryEditScreen),
          );
          expect(editor.entry!.id, historical.id);
          expect(editor.entry!.date, historical.date);
          expect(editor.entry!.content, historical.content);
          expect(editor.entry!.mood, historical.mood);
          expect(find.byType(DiaryScreen), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Open published diary'), findsOneWidget);
          expect(find.byType(DiaryEditScreen), findsNothing);
          expect(
            (await SharedPreferences.getInstance()).getStringList(
              'duoyi_diary',
            ),
            stored,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          diaries.dispose();
          theme.dispose();
          I18n.setLocale(AppLocale.zh);
        }
      });
    }
  }
}
