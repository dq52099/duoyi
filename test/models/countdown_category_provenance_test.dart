import 'dart:convert';

import 'package:duoyi/core/date_item_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('omitted and blank categories become canonical generated defaults', () {
    final omitted = _item();
    final nullCategory = _item(category: null);
    final blank = _item(category: ' \t ');

    for (final item in [omitted, nullCategory, blank]) {
      expect(item.category, CountdownItem.defaultCategory);
      expect(item.categoryIsDefault, isTrue);
    }
  });

  test('nonempty default-looking category names remain authored', () {
    for (final category in ['默认', 'Default']) {
      final item = _item(category: category);

      expect(item.category, category);
      expect(item.categoryIsDefault, isFalse);
    }

    final explicitlyGenerated = _item(
      category: 'Default',
      categoryIsDefault: true,
    );
    expect(explicitlyGenerated.category, CountdownItem.defaultCategory);
    expect(explicitlyGenerated.categoryIsDefault, isTrue);
  });

  test('JSON roundtrip preserves generated and authored category metadata', () {
    final generated = _item(
      id: 'generated',
      categoryIsDefault: true,
      category: 'ignored override',
      isPinned: true,
      remind: true,
      reminderKind: ReminderKind.alarm,
    );
    final authored = _item(
      id: 'authored',
      category: 'Default',
      isPinned: true,
      remind: true,
      reminderKind: ReminderKind.email,
    );

    for (final item in [generated, authored]) {
      final decoded = jsonDecode(jsonEncode(item.toJson()));
      final restored = CountdownItem.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );

      expect(restored.toJson(), item.toJson());
      expect(restored.title, item.title);
      expect(restored.updatedAt, item.updatedAt);
      expect(restored.isPinned, isTrue);
      expect(restored.remind, isTrue);
      expect(restored.reminderKind, item.reminderKind);
    }
  });

  test('pin, reminder, and unrelated copies preserve category provenance', () {
    final generated = _item();
    final authored = _item(category: '默认', remind: true);

    final generatedCopy = generated.copyWith(isPinned: true, remind: true);
    final authoredCopy = authored.copyWith(
      title: '改过的标题',
      reminderKind: ReminderKind.off,
    );

    expect(generatedCopy.category, CountdownItem.defaultCategory);
    expect(generatedCopy.categoryIsDefault, isTrue);
    expect(generatedCopy.isPinned, isTrue);
    expect(generatedCopy.remind, isTrue);
    expect(authoredCopy.title, '改过的标题');
    expect(authoredCopy.category, '默认');
    expect(authoredCopy.categoryIsDefault, isFalse);
    expect(authoredCopy.remind, isFalse);
  });

  test('copyWith category changes classify authored and reset values', () {
    final generated = _item();
    final toChineseName = generated.copyWith(category: '默认');
    final toEnglishName = generated.copyWith(category: 'Default');
    final resetFromCustom = _item(category: 'Project').copyWith(category: '  ');
    final explicitlyGenerated = _item(
      category: 'Project',
    ).copyWith(category: 'Default', categoryIsDefault: true);

    expect(toChineseName.category, '默认');
    expect(toChineseName.categoryIsDefault, isFalse);
    expect(toEnglishName.category, 'Default');
    expect(toEnglishName.categoryIsDefault, isFalse);
    expect(resetFromCustom.category, CountdownItem.defaultCategory);
    expect(resetFromCustom.categoryIsDefault, isTrue);
    expect(explicitlyGenerated.category, CountdownItem.defaultCategory);
    expect(explicitlyGenerated.categoryIsDefault, isTrue);
  });

  test('legacy and malformed provenance flags preserve authored fields', () {
    final updatedAt = DateTime(2025, 7, 8, 9, 10, 11);
    final base = <String, dynamic>{
      'id': 'legacy',
      'title': '原有标题',
      'targetDate': DateTime(2030, 1, 2).toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };

    final legacyImplicit = CountdownItem.fromJson(base);
    expect(legacyImplicit.category, CountdownItem.defaultCategory);
    expect(legacyImplicit.categoryIsDefault, isTrue);
    expect(legacyImplicit.title, '原有标题');
    expect(legacyImplicit.updatedAt, updatedAt);

    final legacyBlank = CountdownItem.fromJson({...base, 'category': '  '});
    expect(legacyBlank.category, CountdownItem.defaultCategory);
    expect(legacyBlank.categoryIsDefault, isTrue);

    for (final malformedFlag in ['true', 1, <String, Object>{}]) {
      final item = CountdownItem.fromJson({
        ...base,
        'category': 'Default',
        'categoryIsDefault': malformedFlag,
      });
      expect(item.category, 'Default');
      expect(item.categoryIsDefault, isFalse);
      expect(item.title, '原有标题');
      expect(item.updatedAt, updatedAt);
    }

    final oldNamedCategory = CountdownItem.fromJson({
      ...base,
      'category': '默认',
    });
    expect(oldNamedCategory.category, '默认');
    expect(oldNamedCategory.categoryIsDefault, isFalse);
  });

  test(
    'default label follows zh-en-zh without changing stored category data',
    () {
      final generated = _item();
      final authoredChinese = _item(category: '默认');
      final authoredEnglish = _item(category: 'Default');
      final before = [
        generated,
        authoredChinese,
        authoredEnglish,
      ].map((item) => jsonEncode(item.toJson())).toList();

      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        expect(
          DateItemUiCopy.countdownCategory(generated),
          I18n.tr('countdown.category.default'),
        );
        expect(DateItemUiCopy.countdownCategory(authoredChinese), '默认');
        expect(DateItemUiCopy.countdownCategory(authoredEnglish), 'Default');
        expect(
          [
            generated,
            authoredChinese,
            authoredEnglish,
          ].map((item) => jsonEncode(item.toJson())).toList(),
          before,
        );
      }
    },
  );
}

CountdownItem _item({
  String id = 'item',
  String title = '标题',
  String? category,
  bool? categoryIsDefault,
  bool isPinned = false,
  bool remind = false,
  ReminderKind reminderKind = ReminderKind.push,
}) => CountdownItem(
  id: id,
  title: title,
  targetDate: DateTime(2030, 8, 17, 12, 30),
  category: category,
  categoryIsDefault: categoryIsDefault,
  isPinned: isPinned,
  remind: remind,
  reminderKind: reminderKind,
  updatedAt: DateTime(2025, 7, 8, 9, 10, 11),
);
