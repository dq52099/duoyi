import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _anniversariesPreferenceKey = 'duoyi_anniversaries_v2';
const _platformAnniversariesPreferenceKey = 'flutter.duoyi_anniversaries_v2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _CountingStore();
    SharedPreferencesStorePlatform.instance = store;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final birthday in [true, false]) {
    testWidgets(
      'anniversary wrapper birthday=$birthday keeps its mounted state',
      (tester) async {
        final fixture = await _loadFixture(
          Anniversary.create(
            title: '用户原文',
            solarDate: DateTime(2023, 3, 22),
            type: birthday
                ? AnniversaryType.birthday
                : AnniversaryType.memorial,
          ),
          store,
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          _app(
            fixture,
            birthday
                ? const BirthdayScreen()
                : const MemorialAnniversaryScreen(),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(AnniversaryScreen));
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(AnniversaryScreen)), same(state));
          expect(
            (tester.widget<AppBar>(find.byType(AppBar)).title! as Text).data,
            I18n.tr(birthday ? 'anniversary.birthday' : 'anniversary.title'),
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('opened anniversary picker translates its headers live', (
    tester,
  ) async {
    final fixture = await _loadFixture(
      Anniversary.create(
        title: '用户原文',
        solarDate: DateTime(2023, 3, 22),
        type: AnniversaryType.memorial,
      ),
      store,
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(_editorLauncher(fixture));
    await tester.tap(find.byKey(const ValueKey('open_anniversary_editor')));
    await tester.pumpAndSettle();
    final dateTile = find.byKey(const ValueKey('anniversary_editor_date_tile'));
    await tester.ensureVisible(dateTile);
    await tester.tap(dateTile);
    await tester.pumpAndSettle();
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(
        find.text(I18n.tr('anniversary.field.date_picker_title')),
        findsOneWidget,
      );
      expect(
        find.text(I18n.tr('anniversary.field.date_picker_subtitle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    final cancel = find.descendant(
      of: find.byType(AppModalSheet).last,
      matching: find.text(I18n.tr('action.cancel')),
    );
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dateCase in _lunarDateCases) {
    testWidgets(
      '${dateCase.name} solar editor subtitle follows the selected locale',
      (tester) async {
        final item = Anniversary.create(
          id: 'solar-${dateCase.name}',
          title: 'Solar anniversary',
          solarDate: dateCase.solarDate,
          type: AnniversaryType.memorial,
        );
        final fixture = await _loadFixture(item, store);
        addTearDown(fixture.dispose);
        final lunar = _expectKnownLunarConversion(dateCase);

        await tester.pumpWidget(_editorLauncher(fixture));
        await tester.tap(find.byKey(const ValueKey('open_anniversary_editor')));
        await tester.pumpAndSettle();

        final subtitle = _editorDateTile(tester).subtitle! as Text;
        expect(
          subtitle.data,
          contains(AlmanacLocaleFormat.formatFullLunarDate(lunar)),
        );

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();

        expect(
          (_editorDateTile(tester).subtitle! as Text).data,
          contains(AlmanacLocaleFormat.formatFullLunarDate(lunar)),
        );
        expect(
          (_editorDateTile(tester).subtitle! as Text).data,
          isNot(contains(lunar.toString())),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${dateCase.name} lunar anniversary card subtitle follows the selected locale',
      (tester) async {
        final item = Anniversary.create(
          id: 'lunar-card-${dateCase.name}',
          title: 'Lunar anniversary card',
          solarDate: dateCase.solarDate,
          type: AnniversaryType.normal,
          calendarType: AnniversaryCalendarType.lunar,
        );
        final fixture = await _loadFixture(item, store);
        addTearDown(fixture.dispose);
        final lunar = _expectKnownLunarConversion(dateCase);

        await tester.pumpWidget(_app(fixture, const AnniversaryScreen()));
        await tester.pumpAndSettle();

        expect(_cardSubtitle(tester).data, contains(lunar.chineseText));

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();

        expect(
          _cardSubtitle(tester).data,
          contains(AlmanacLocaleFormat.formatLunarDate(lunar)),
        );
        expect(_cardSubtitle(tester).data, isNot(contains(lunar.chineseText)));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'lunar editor locale changes preserve drafts, date selection, and stored data',
    (tester) async {
      final dateCase = _LunarDateCase(
        name: '2023-03-22 leap second month start',
        solarDate: DateTime(2023, 3, 22),
        year: 2023,
        month: 2,
        day: 1,
        isLeapMonth: true,
      );
      final lunar = _expectKnownLunarConversion(dateCase);
      final item = Anniversary.create(
        id: 'mounted-lunar-anniversary',
        title: '中文纪念日标题',
        description: '中文纪念日说明',
        solarDate: dateCase.solarDate,
        type: AnniversaryType.memorial,
        calendarType: AnniversaryCalendarType.lunar,
      );
      final fixture = await _loadFixture(item, store);
      addTearDown(fixture.dispose);
      final modelJsonBefore = jsonEncode(
        fixture.provider.items.single.toJson(),
      );
      final storedPreferenceBytesBefore = List<String>.of(
        fixture.preferences.getStringList(_anniversariesPreferenceKey)!,
      );

      await tester.pumpWidget(_app(fixture, const AnniversaryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.title));
      await tester.pumpAndSettle();

      final screenState = tester.state<State<AnniversaryScreen>>(
        find.byType(AnniversaryScreen),
      );
      final titleField = find.byType(TextField).at(0);
      final descriptionField = find.byType(TextField).at(1);
      final titleController = tester.widget<TextField>(titleField).controller!;
      final descriptionController = tester
          .widget<TextField>(descriptionField)
          .controller!;
      titleController.text = '正在编辑的中文标题草稿';
      descriptionController.text = '正在编辑的中文说明草稿';
      await tester.pumpAndSettle();

      final initialDateTile = _editorDateTile(tester);
      expect(
        (initialDateTile.title! as Text).data,
        contains(
          AlmanacLocaleFormat.formatFullLunarDate(lunar, includeGanzhi: true),
        ),
      );
      expect(
        tester
            .widget<SegmentedButton<AnniversaryCalendarType>>(
              find.byKey(const ValueKey('anniversary_calendar_type_segments')),
            )
            .selected,
        {AnniversaryCalendarType.lunar},
      );

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        expect(
          tester.state<State<AnniversaryScreen>>(
            find.byType(AnniversaryScreen),
          ),
          same(screenState),
        );
        expect(
          tester.widget<TextField>(titleField).controller,
          same(titleController),
        );
        expect(
          tester.widget<TextField>(descriptionField).controller,
          same(descriptionController),
        );
        expect(titleController.text, '正在编辑的中文标题草稿');
        expect(descriptionController.text, '正在编辑的中文说明草稿');
        expect(
          tester
              .widget<SegmentedButton<AnniversaryCalendarType>>(
                find.byKey(
                  const ValueKey('anniversary_calendar_type_segments'),
                ),
              )
              .selected,
          {AnniversaryCalendarType.lunar},
        );

        final dateTile = _editorDateTile(tester);
        final title = (dateTile.title! as Text).data!;
        if (locale == AppLocale.en) {
          final localizedLunarDate = AlmanacLocaleFormat.formatFullLunarDate(
            lunar,
            includeGanzhi: true,
          );
          expect(title, contains(localizedLunarDate));
          expect(title, contains('2023 (Gui-Mao)'));
          expect(title, contains('Leap Month 2, Day 1'));
          expect(title, isNot(contains(lunar.chineseText)));
        } else {
          expect(
            title,
            contains(
              AlmanacLocaleFormat.formatFullLunarDate(
                lunar,
                includeGanzhi: true,
              ),
            ),
          );
        }

        expect(
          fixture.preferences.getStringList(_anniversariesPreferenceKey),
          storedPreferenceBytesBefore,
        );
        expect(
          jsonEncode(fixture.provider.items.single.toJson()),
          modelJsonBefore,
        );
        expect(store.writeCount(_platformAnniversariesPreferenceKey), 0);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

LunarDate _expectKnownLunarConversion(_LunarDateCase dateCase) {
  final lunar = LunarCalendar.fromSolar(dateCase.solarDate);
  expect(lunar.year, dateCase.year);
  expect(lunar.month, dateCase.month);
  expect(lunar.day, dateCase.day);
  expect(lunar.isLeapMonth, dateCase.isLeapMonth);
  expect(
    LunarCalendar.toSolar(
      dateCase.year,
      dateCase.month,
      dateCase.day,
      isLeap: dateCase.isLeapMonth,
    ),
    dateCase.solarDate,
  );
  if (dateCase.solarDate == DateTime(2025, 8, 23)) {
    expect(
      LunarCalendar.toSolar(2025, 6, 29, isLeap: true),
      DateTime(2025, 8, 22),
    );
  }
  return lunar;
}

Future<_Fixture> _loadFixture(Anniversary item, _CountingStore store) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setStringList(_anniversariesPreferenceKey, [
    jsonEncode(item.toJson()),
  ]);
  final provider = AnniversaryProvider();
  await provider.loadFromStorage();
  store.resetWrites();
  return _Fixture(item: item, provider: provider, preferences: preferences);
}

Widget _app(_Fixture fixture, Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: fixture.provider),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: BrandRouteSurface(child: home),
    ),
  );
}

Widget _editorLauncher(_Fixture fixture) {
  return _app(
    fixture,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open_anniversary_editor'),
            onPressed: () => showAnniversaryEditor(
              context,
              item: fixture.item,
              fixedType: fixture.item.type,
            ),
            child: const Text('Open anniversary editor'),
          ),
        ),
      ),
    ),
  );
}

ListTile _editorDateTile(WidgetTester tester) => tester.widget<ListTile>(
  find.byKey(const ValueKey('anniversary_editor_date_tile')),
);

Text _cardSubtitle(WidgetTester tester) {
  final prefix = I18n.tr('anniversary.next.prefix');
  final finder = find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data ?? '').startsWith(prefix),
  );
  return tester.widget<Text>(finder);
}

class _Fixture {
  const _Fixture({
    required this.item,
    required this.provider,
    required this.preferences,
  });

  final Anniversary item;
  final AnniversaryProvider provider;
  final SharedPreferences preferences;

  void dispose() => provider.dispose();
}

class _LunarDateCase {
  const _LunarDateCase({
    required this.name,
    required this.solarDate,
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
  });

  final String name;
  final DateTime solarDate;
  final int year;
  final int month;
  final int day;
  final bool isLeapMonth;
}

final _lunarDateCases = <_LunarDateCase>[
  _LunarDateCase(
    name: '2023-03-22 leap second month start',
    solarDate: DateTime(2023, 3, 22),
    year: 2023,
    month: 2,
    day: 1,
    isLeapMonth: true,
  ),
  _LunarDateCase(
    name: '2025-08-23 seventh month start after leap month',
    solarDate: DateTime(2025, 8, 23),
    year: 2025,
    month: 7,
    day: 1,
    isLeapMonth: false,
  ),
];

class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore() : super.withData(<String, Object>{});

  final Map<String, int> _writes = <String, int>{};

  int writeCount(String key) => _writes[key] ?? 0;

  void resetWrites() => _writes.clear();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    _writes.update(key, (count) => count + 1, ifAbsent: () => 1);
    return super.setValue(type, key, value);
  }
}
