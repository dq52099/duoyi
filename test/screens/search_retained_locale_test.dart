import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/screens/search_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _CountingDiaryProvider extends DiaryProvider {
  _CountingDiaryProvider(this.fixtureEntries);

  final List<DiaryEntry> fixtureEntries;
  int entriesReadCount = 0;

  @override
  List<DiaryEntry> get entries {
    entriesReadCount++;
    return fixtureEntries;
  }
}

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _textSpans(child);
    }
  }
}

List<TextSpan> _highlightedReviewSpans(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .expand((richText) => _textSpans(richText.text))
    .where((span) => span.text == 'review' && span.style?.color != null)
    .toList();

String _resultSummary(AppLocale locale) {
  final copy = _LocaleStrings(locale);
  return '${copy.summaryPrefix}review${copy.summaryMiddle}2${copy.summarySuffix}';
}

class _LocaleStrings {
  const _LocaleStrings(this.locale);

  final AppLocale locale;

  String get summaryPrefix => locale == AppLocale.en ? '"' : '“';
  String get summaryMiddle => locale == AppLocale.en ? '" found ' : '” 共 ';
  String get summarySuffix => locale == AppLocale.en ? ' matches' : ' 条命中';
}

Widget _searchApp(_CountingDiaryProvider diaryProvider) => MultiProvider(
  providers: [
    ChangeNotifierProvider<TodoProvider>(create: (_) => TodoProvider()),
    ChangeNotifierProvider<HabitProvider>(create: (_) => HabitProvider()),
    ChangeNotifierProvider<NoteProvider>(create: (_) => NoteProvider()),
    ChangeNotifierProvider<DiaryProvider>.value(value: diaryProvider),
    ChangeNotifierProvider<AnniversaryProvider>(
      create: (_) => AnniversaryProvider(),
    ),
    ChangeNotifierProvider<CountdownProvider>(
      create: (_) => CountdownProvider(),
    ),
    ChangeNotifierProvider<GoalProvider>(create: (_) => GoalProvider()),
    ChangeNotifierProvider<CourseProvider>(create: (_) => CourseProvider()),
    ChangeNotifierProvider<CalendarProvider>(create: (_) => CalendarProvider()),
    ChangeNotifierProvider<TimeAuditProvider>(
      create: (_) => TimeAuditProvider(),
    ),
    ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
  ],
  child: const MaterialApp(home: BrandRouteSurface(child: SearchScreen())),
);

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'mounted SearchScreen relocalizes retained diary hits without rerunning query',
    (tester) async {
      final date = DateTime(2026, 10, 11);
      final fixtureEntries = [
        DiaryEntry(
          id: 'generated-diary',
          date: date,
          content: '  ',
          tags: ['review'],
        ),
        DiaryEntry(
          id: 'authored-diary',
          date: date,
          content: '10月11日的日记\nreview',
          tags: ['review'],
        ),
      ];
      final diaryProvider = _CountingDiaryProvider(fixtureEntries);
      final sourceIds = fixtureEntries.map((entry) => entry.id).toList();
      final sourceDates = fixtureEntries.map((entry) => entry.date).toList();

      await tester.pumpWidget(_searchApp(diaryProvider));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'review');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'review',
      );
      expect(find.text(_resultSummary(AppLocale.zh)), findsOneWidget);
      expect(find.text('10月11日的日记'), findsNWidgets(2));
      expect(find.text('10/11'), findsNWidgets(2));
      expect(_highlightedReviewSpans(tester), hasLength(1));
      expect(diaryProvider.entriesReadCount, 1);
      expect(sourceIds, ['generated-diary', 'authored-diary']);
      expect(sourceDates, [date, date]);

      final screenState = tester.state(find.byType(SearchScreen));
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      final editingValue = controller.value;
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(SearchScreen)), same(screenState));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(controller),
      );
      expect(controller.value, editingValue);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'review',
      );
      expect(find.text(_resultSummary(AppLocale.en)), findsOneWidget);
      expect(find.text('Diary for 10/11'), findsOneWidget);
      expect(find.text('10月11日的日记'), findsOneWidget);
      expect(find.text('10/11'), findsNWidgets(2));
      expect(_highlightedReviewSpans(tester), hasLength(1));
      expect(diaryProvider.entriesReadCount, 1);
      expect(fixtureEntries.map((entry) => entry.id).toList(), sourceIds);
      expect(fixtureEntries.map((entry) => entry.date).toList(), sourceDates);
      expect(
        tester.getTopLeft(find.text('Diary for 10/11')).dy,
        lessThan(tester.getTopLeft(find.text('10月11日的日记')).dy),
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(SearchScreen)), same(screenState));
      expect(controller.value, editingValue);

      expect(find.text(_resultSummary(AppLocale.zh)), findsOneWidget);
      expect(find.text('10月11日的日记'), findsNWidgets(2));
      expect(find.text('10/11'), findsNWidgets(2));
      expect(_highlightedReviewSpans(tester), hasLength(1));
      expect(diaryProvider.entriesReadCount, 1);

      await tester.tap(
        find
            .ancestor(
              of: find.text('10月11日的日记').first,
              matching: find.byType(AppSurfaceCard),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiaryScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.takeException(), isNull);
      I18n.setLocale(AppLocale.zh);
    },
  );
}
