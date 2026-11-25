import 'dart:convert';

import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final merge in [false, true]) {
    test('backup restores category provenance merge=$merge', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = CountdownProvider();
      addTearDown(provider.dispose);
      for (final category in [null, '默认', 'Default']) {
        await provider.addItem(
          CountdownItem(
            id: category ?? 'generated',
            title: 'User title',
            targetDate: DateTime(2032, 9, 20),
            category: category,
          ),
        );
      }
      final before = prefs.getStringList('duoyi_countdowns')!;
      final exported = await BackupService.exportAll();
      await prefs.remove('duoyi_countdowns');
      await BackupService.importAll(exported, merge: merge);
      expect(
        prefs.getStringList('duoyi_countdowns')!.map(jsonDecode),
        unorderedEquals(before.map(jsonDecode)),
      );
      final restored = CountdownProvider();
      addTearDown(restored.dispose);
      await restored.loadFromStorage();
      expect(restored.items, hasLength(3));
      expect(
        restored.items
            .singleWhere((item) => item.id == 'generated')
            .categoryIsDefault,
        isTrue,
      );
      for (final category in ['默认', 'Default']) {
        final item = restored.items.singleWhere((item) => item.id == category);
        expect(item.category, category);
        expect(item.categoryIsDefault, isFalse);
      }
    });
  }
}
