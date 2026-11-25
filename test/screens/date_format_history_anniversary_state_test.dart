import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/ai_history_screen.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dateFormatPreferenceKey = 'pref_date_format';
const _anniversariesPreferenceKey = 'duoyi_anniversaries_v2';
const _reviewHistoryPreferenceKey = 'ai_review_history';
const _initialDateFormat = 'yyyy-MM-dd';
const _updatedDateFormat = 'MM/dd/yyyy';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    testWidgets(
      '${locale.name} AI history date refresh retains an expanded review',
      (tester) async {
        I18n.setLocale(locale);
        final review = AiReviewEntry(
          id: 'date-format-review',
          createdAt: DateTime(2026, 5, 15, 15, 4),
          content: 'Expanded review body remains visible.',
          summary: 'A saved weekly review.',
        );
        final fixture = await _loadFixture(tester, reviewHistory: [review]);

        await tester.pumpWidget(_app(fixture, const AiHistoryScreen()));
        await tester.pumpAndSettle();

        final screenFinder = find.byType(AiHistoryScreen);
        final screenState = tester.state<State<AiHistoryScreen>>(screenFinder);
        final expectedInitialDate = locale == AppLocale.en
            ? '2026-05-15 Fri 3:04 PM'
            : '2026-05-15 周五 15:04';
        final expectedUpdatedDate = locale == AppLocale.en
            ? '05/15/2026 Fri 3:04 PM'
            : '05/15/2026 周五 15:04';

        expect(find.text(expectedInitialDate), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('ai_history_toggle_date-format-review')),
        );
        await tester.pumpAndSettle();
        expect(find.text(review.content), findsOneWidget);

        await _changeDateFormat(tester, fixture.preferences);
        await tester.pumpAndSettle();

        expect(
          tester.state<State<AiHistoryScreen>>(screenFinder),
          same(screenState),
        );
        expect(find.text(expectedUpdatedDate), findsOneWidget);
        expect(find.text(review.content), findsOneWidget);
        final toggle = tester.widget<IconButton>(
          find.byKey(const ValueKey('ai_history_toggle_date-format-review')),
        );
        expect((toggle.icon as Icon).icon, Icons.keyboard_arrow_up);
      },
    );

    testWidgets(
      '${locale.name} upcoming anniversary modal refreshes its date format',
      (tester) async {
        I18n.setLocale(locale);
        final item = Anniversary.create(
          id: 'upcoming-date-format',
          title: 'Upcoming date format',
          solarDate: DateTime.now().add(const Duration(days: 10)),
          type: AnniversaryType.memorial,
        );
        final fixture = await _loadFixture(tester, anniversaries: [item]);
        final occurrence = item.nextOccurrence;

        await tester.pumpWidget(_app(fixture, const AnniversaryScreen()));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byTooltip(I18n.tr('anniversary.upcoming_30_days')),
        );
        await tester.pumpAndSettle();

        final before = _upcomingSubtitle(tester).data!;
        expect(
          before,
          startsWith(
            I18nDateFormat.date(occurrence, pattern: _initialDateFormat),
          ),
        );

        await _changeDateFormat(tester, fixture.preferences);
        await tester.pumpAndSettle();

        expect(find.byType(AppModalSheet), findsOneWidget);
        final after = _upcomingSubtitle(tester).data!;
        expect(
          after,
          startsWith(
            I18nDateFormat.date(occurrence, pattern: _updatedDateFormat),
          ),
        );
        expect(after, isNot(before));
      },
    );

    testWidgets(
      '${locale.name} add anniversary sheet refresh retains controller drafts',
      (tester) async {
        I18n.setLocale(locale);
        final fixture = await _loadFixture(tester);
        await tester.pumpWidget(_app(fixture, const AnniversaryScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'New anniversary draft');
        await tester.enterText(fields.at(1), 'New anniversary notes draft');
        await tester.pump();

        final titleController = tester
            .widget<TextField>(fields.at(0))
            .controller!;
        final descriptionController = tester
            .widget<TextField>(fields.at(1))
            .controller!;
        final initialDateText = _editorDateTitle(tester).data!;
        final initialDate = _extractIsoDate(initialDateText);
        expect(initialDateText, contains(initialDate));

        await _changeDateFormat(tester, fixture.preferences);
        await tester.pumpAndSettle();

        expect(find.byType(AppModalSheet), findsOneWidget);
        expect(
          _editorDateTitle(tester).data,
          contains(
            I18nDateFormat.date(
              DateTime.parse(initialDate),
              pattern: _updatedDateFormat,
            ),
          ),
        );
        expect(
          tester.widget<TextField>(fields.at(0)).controller,
          same(titleController),
        );
        expect(
          tester.widget<TextField>(fields.at(1)).controller,
          same(descriptionController),
        );
        expect(titleController.text, 'New anniversary draft');
        expect(descriptionController.text, 'New anniversary notes draft');
      },
    );

    testWidgets(
      '${locale.name} edit anniversary sheet refresh retains controller drafts',
      (tester) async {
        I18n.setLocale(locale);
        final item = Anniversary.create(
          id: 'edit-date-format',
          title: 'Existing anniversary',
          description: 'Existing description',
          solarDate: DateTime(2026, 4, 9),
          type: AnniversaryType.memorial,
        );
        final fixture = await _loadFixture(tester, anniversaries: [item]);

        await tester.pumpWidget(_app(fixture, const AnniversaryScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Existing anniversary'));
        await tester.pumpAndSettle();

        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Edited anniversary draft');
        await tester.enterText(fields.at(1), 'Edited notes draft');
        await tester.pump();

        final titleController = tester
            .widget<TextField>(fields.at(0))
            .controller!;
        final descriptionController = tester
            .widget<TextField>(fields.at(1))
            .controller!;
        final initialDateText = _editorDateTitle(tester).data!;
        final initialDate = _extractIsoDate(initialDateText);
        expect(initialDate, '2026-04-09');

        await _changeDateFormat(tester, fixture.preferences);
        await tester.pumpAndSettle();

        expect(find.byType(AppModalSheet), findsOneWidget);
        expect(
          _editorDateTitle(tester).data,
          contains(
            I18nDateFormat.date(
              DateTime.parse(initialDate),
              pattern: _updatedDateFormat,
            ),
          ),
        );
        expect(
          tester.widget<TextField>(fields.at(0)).controller,
          same(titleController),
        );
        expect(
          tester.widget<TextField>(fields.at(1)).controller,
          same(descriptionController),
        );
        expect(titleController.text, 'Edited anniversary draft');
        expect(descriptionController.text, 'Edited notes draft');
      },
    );
  }
}

Future<_Fixture> _loadFixture(
  WidgetTester tester, {
  List<Anniversary> anniversaries = const [],
  List<AiReviewEntry> reviewHistory = const [],
}) async {
  final initialValues = <String, Object>{
    _dateFormatPreferenceKey: _initialDateFormat,
    if (anniversaries.isNotEmpty)
      _anniversariesPreferenceKey: anniversaries
          .map((item) => jsonEncode(item.toJson()))
          .toList(),
    if (reviewHistory.isNotEmpty)
      _reviewHistoryPreferenceKey: reviewHistory
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(),
  };
  SharedPreferences.setMockInitialValues(initialValues);

  late PreferencesProvider preferences;
  late AnniversaryProvider anniversaryProvider;
  late AiService aiService;
  await tester.runAsync(() async {
    preferences = PreferencesProvider();
    await preferences.loadFromStorage();
    anniversaryProvider = AnniversaryProvider();
    await anniversaryProvider.loadFromStorage();
    aiService = AiService();
    await aiService.loadFromStorage();
  });

  final fixture = _Fixture(
    preferences: preferences,
    anniversaryProvider: anniversaryProvider,
    aiService: aiService,
  );
  addTearDown(fixture.dispose);
  return fixture;
}

Widget _app(_Fixture fixture, Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PreferencesProvider>.value(
        value: fixture.preferences,
      ),
      ChangeNotifierProvider<AnniversaryProvider>.value(
        value: fixture.anniversaryProvider,
      ),
      ChangeNotifierProvider<AiService>.value(value: fixture.aiService),
    ],
    child: MaterialApp(theme: ThemeData(useMaterial3: true), home: home),
  );
}

Future<void> _changeDateFormat(
  WidgetTester tester,
  PreferencesProvider preferences,
) async {
  await tester.runAsync(() => preferences.setDateFormat(_updatedDateFormat));
}

Text _upcomingSubtitle(WidgetTester tester) {
  final modal = find.byType(AppModalSheet).last;
  final listTile = find
      .descendant(of: modal, matching: find.byType(ListTile))
      .first;
  return tester.widget<ListTile>(listTile).subtitle! as Text;
}

Text _editorDateTitle(WidgetTester tester) {
  final dateTile = find.byKey(const ValueKey('anniversary_editor_date_tile'));
  final title = find
      .descendant(of: dateTile, matching: find.byType(Text))
      .first;
  return tester.widget<Text>(title);
}

String _extractIsoDate(String text) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(text);
  expect(match, isNotNull);
  return match!.group(0)!;
}

class _Fixture {
  final PreferencesProvider preferences;
  final AnniversaryProvider anniversaryProvider;
  final AiService aiService;

  const _Fixture({
    required this.preferences,
    required this.anniversaryProvider,
    required this.aiService,
  });

  void dispose() {
    preferences.dispose();
    anniversaryProvider.dispose();
    aiService.dispose();
  }
}
