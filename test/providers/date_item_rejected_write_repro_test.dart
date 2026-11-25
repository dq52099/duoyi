import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final anniversary in [false, true]) {
    test(
      'rejected date write must not announce success anniversary=$anniversary',
      () async {
        SharedPreferences.setMockInitialValues({});
        final previous = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = _RejectDateStore();
        addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
        var persisted = 0;
        if (anniversary) {
          final provider = AnniversaryProvider()
            ..onLocalMutationPersisted = () => persisted++;
          addTearDown(provider.dispose);
          await expectLater(
            provider.add(
              Anniversary(
                title: 'Synthetic birthday',
                originDate: DateTime(2030, 1, 1),
                type: AnniversaryType.birthday,
              ),
            ),
            throwsStateError,
          );
          expect(provider.items, isEmpty);
        } else {
          final provider = CountdownProvider()
            ..onLocalMutationPersisted = () => persisted++;
          addTearDown(provider.dispose);
          await expectLater(
            provider.addItem(
              CountdownItem(
                id: 'synthetic-date',
                title: 'Synthetic deadline',
                targetDate: DateTime(2030, 1, 1),
              ),
            ),
            throwsStateError,
          );
          expect(provider.items, isEmpty);
        }
        expect(persisted, 0);
      },
    );
  }
}

class _RejectDateStore extends InMemorySharedPreferencesStore {
  _RejectDateStore() : super.withData({});

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_countdowns' ||
        key == 'flutter.duoyi_anniversaries_v2') {
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
