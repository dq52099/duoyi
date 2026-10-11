import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/webdav_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _first = WebDavBackupConfig(
  baseUrl: 'https://dav.example.test/first',
  username: 'fixture-a',
  password: 'fixture-secret-a',
);
const _second = WebDavBackupConfig(
  baseUrl: 'https://dav.example.test/second',
  username: 'fixture-b',
  password: 'fixture-secret-b',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AccountPreferenceWrites.drain);

  test(
    'account change during MKCOL prevents exporting B to A destination',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var uploads = 0;
      final service = WebDavBackupService(
        client: MockClient((request) async {
          if (request.method == 'MKCOL') {
            started.complete();
            await release.future;
            return http.Response('', 201);
          }
          uploads++;
          return http.Response('', 201);
        }),
      );
      final uploading = expectLater(
        service.uploadCurrentBackup(_first),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await started.future;
      await AccountLocalDataCleaner.clearSharedPreferences();
      await (await SharedPreferences.getInstance()).setString(
        'user_profile',
        'synthetic B data',
      );
      release.complete();
      await uploading;
      expect(uploads, 0);
    },
  );

  test(
    'old account download does not return content after account switch',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final service = WebDavBackupService(
        client: MockClient((request) async {
          started.complete();
          return response.future;
        }),
      );
      final downloading = expectLater(
        service.downloadLatestBackup(_first),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await started.future;
      await AccountLocalDataCleaner.clearSharedPreferences();
      response.complete(http.Response('{"synthetic":"old data"}', 200));
      await downloading;
    },
  );

  test(
    'cleanup drains config save and discards its remaining credentials',
    () async {
      final store = _ConfigStore()..holdKey = 'flutter.webdav_backup_base_url';
      SharedPreferencesStorePlatform.instance = store;
      final saving = expectLater(
        WebDavBackupService.saveConfig(_first),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await store.started.future;
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
        (_) => cleaned = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      await Future.wait([saving, cleanup]);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.startsWith('webdav_backup_')),
        isEmpty,
      );
      expect(store.setKeys, isNot(contains('flutter.webdav_backup_password')));
    },
  );

  test(
    'rejected config write rolls back every field and permits retry',
    () async {
      await WebDavBackupService.saveConfig(_first);
      final initial = {
        for (final entry in _first.toPrefs().entries)
          'flutter.${entry.key}': entry.value,
      };
      final store = _ConfigStore(initial: initial)
        ..rejectOnce = 'flutter.webdav_backup_username';
      SharedPreferencesStorePlatform.instance = store;
      await expectLater(
        WebDavBackupService.saveConfig(_second),
        throwsStateError,
      );
      final restored = await WebDavBackupService.loadConfig();
      expect(restored.toPrefs(), _first.toPrefs());
      await WebDavBackupService.saveConfig(_second);
      expect(
        (await WebDavBackupService.loadConfig()).toPrefs(),
        _second.toPrefs(),
      );
    },
  );

  test(
    'queued config choices and config reads wait for complete writes',
    () async {
      final store = _ConfigStore()..holdKey = 'flutter.webdav_backup_base_url';
      SharedPreferencesStorePlatform.instance = store;
      final first = WebDavBackupService.saveConfig(_first);
      await store.started.future;
      final second = WebDavBackupService.saveConfig(_second);
      var loaded = false;
      final loading = WebDavBackupService.loadConfig().then((value) {
        loaded = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(loaded, isFalse);
      store.release.complete();
      await Future.wait([first, second]);
      expect((await loading).toPrefs(), _second.toPrefs());
    },
  );

  test('config save already inside cleanup reports cancellation', () async {
    await AccountLocalDataCleaner.runPreferenceBoundary(() async {
      await expectLater(
        WebDavBackupService.saveConfig(_first),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
    });
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}

class _ConfigStore extends InMemorySharedPreferencesStore {
  _ConfigStore({Map<String, Object> initial = const {}})
    : super.withData(initial);
  String? holdKey;
  String? rejectOnce;
  final started = Completer<void>();
  final release = Completer<void>();
  final setKeys = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (key == rejectOnce) {
      rejectOnce = null;
      return false;
    }
    setKeys.add(key);
    return super.setValue(valueType, key, value);
  }
}
