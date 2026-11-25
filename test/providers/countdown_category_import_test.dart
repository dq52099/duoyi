import 'dart:convert';

import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/services/competitor_task_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'import dedupe separates generated defaults from custom names',
    () async {
      final provider = CountdownProvider();
      addTearDown(provider.dispose);
      final targetDate = DateTime(2031, 2, 3);
      CountdownItem candidate({
        required String id,
        String? category,
        bool? categoryIsDefault,
      }) => CountdownItem(
        id: id,
        title: 'Same title',
        targetDate: targetDate,
        category: category,
        categoryIsDefault: categoryIsDefault,
      );

      final summary = await provider.importCountdowns([
        candidate(id: 'generated'),
        candidate(
          id: 'generated-duplicate',
          category: 'ignored',
          categoryIsDefault: true,
        ),
        candidate(id: 'custom-zh', category: '默认'),
        candidate(id: 'custom-en', category: 'Default'),
        candidate(id: 'custom-work', category: '  Work  '),
        candidate(id: 'custom-work-lower', category: 'work'),
        candidate(id: 'custom-work-case', category: 'WORK'),
      ]);

      expect(summary.inserted, 4);
      expect(summary.skippedDuplicates, 3);
      expect(
        provider.items
            .map((item) => (item.category, item.categoryIsDefault))
            .toList(),
        unorderedEquals([
          (CountdownItem.defaultCategory, true),
          ('默认', false),
          ('Default', false),
          ('  Work  ', false),
        ]),
      );

      final stored = (await SharedPreferences.getInstance()).getStringList(
        'duoyi_countdowns',
      )!;
      final storedRecords = stored
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .toList();
      expect(storedRecords.map((record) => record['categoryIsDefault']), [
        true,
        false,
        false,
        false,
      ]);

      final reloaded = CountdownProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(
        reloaded.items
            .map((item) => (item.category, item.categoryIsDefault))
            .toList(),
        unorderedEquals([
          (CountdownItem.defaultCategory, true),
          ('默认', false),
          ('Default', false),
          ('Work', false),
        ]),
      );
    },
  );

  test(
    'structured dedupe keys do not collide on embedded separators',
    () async {
      final provider = CountdownProvider();
      addTearDown(provider.dispose);
      final firstDate = DateTime(2032, 4, 5);
      final secondDate = DateTime(2032, 4, 6);
      final firstDateText = firstDate.toIso8601String();
      final secondDateText = secondDate.toIso8601String();

      final summary = await provider.importCountdowns([
        CountdownItem(
          id: 'left',
          title: 'collision|$firstDateText',
          targetDate: secondDate,
          category: 'work',
        ),
        CountdownItem(
          id: 'right',
          title: 'collision',
          targetDate: firstDate,
          category: '$secondDateText|work',
        ),
      ]);

      expect(summary.inserted, 2);
      expect(summary.skippedDuplicates, 0);
      expect(
        provider.items.map((item) => item.id),
        unorderedEquals(['left', 'right']),
      );
    },
  );

  test(
    'generic JSON import preserves only explicit boolean default metadata',
    () {
      final result = const CompetitorTaskImporter().parse(
        jsonEncode({
          'countdowns': [
            {
              'title': 'Generated',
              'date': '2034-01-02',
              'category': '默认',
              'categoryIsDefault': true,
            },
            {
              'title': 'Custom',
              'date': '2034-01-02',
              'category': '默认',
              'categoryIsDefault': false,
            },
            {
              'title': 'Malformed text',
              'date': '2034-01-02',
              'category': 'Default',
              'categoryIsDefault': 'true',
            },
            {
              'title': 'Malformed number',
              'date': '2034-01-02',
              'category': 'Default',
              'categoryIsDefault': 1,
            },
            {
              'title': 'Normalized key',
              'date': '2034-01-02',
              'category': '默认',
              'category_is_default': true,
            },
          ],
        }),
      );
      expect(result.warnings, isEmpty);
      expect(result.countdowns.map((item) => item.categoryIsDefault), [
        true,
        false,
        false,
        false,
        true,
      ]);
      expect(result.countdowns.map((item) => item.category), [
        '默认',
        '默认',
        'Default',
        'Default',
        '默认',
      ]);
    },
  );

  test(
    'competitor import distinguishes absent or blank category from names',
    () {
      final result = const CompetitorTaskImporter().parse(
        jsonEncode({
          'countdowns': [
            {'title': 'Absent', 'date': '2034-01-02'},
            {'title': 'Blank', 'date': '2034-01-03', 'category': ' \t '},
            {'title': 'Chinese name', 'date': '2034-01-04', 'category': '默认'},
            {
              'title': 'English name',
              'date': '2034-01-05',
              'category': 'Default',
            },
          ],
        }),
      );

      expect(result.warnings, isEmpty);
      expect(result.countdowns, hasLength(4));
      expect(
        result.countdowns.map(
          (item) => (item.category, item.categoryIsDefault),
        ),
        [
          (CountdownItem.defaultCategory, true),
          (CountdownItem.defaultCategory, true),
          ('默认', false),
          ('Default', false),
        ],
      );
    },
  );
}
