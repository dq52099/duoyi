import 'dart:convert';

import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('本地改动会后台自动同步，不需要手动入口', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'sync_auto': true,
      'todos': json.encode([
        {'id': 'todo-1', 'title': '自动同步'},
      ]),
    });

    var syncRequests = 0;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'token',
      httpClient: MockClient((request) async {
        syncRequests++;
        expect(request.url.path, '/api/sync');
        return http.Response(
          json.encode({
            'todos': [
              {'id': 'todo-1', 'title': '自动同步'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => const {'backup_enabled': true};
    provider.dirtyMarkEnabled = true;
    await provider.loadFromStorage();

    provider.markPendingLocalChange();
    expect(provider.hasPendingChanges, isTrue);

    await Future<void>.delayed(const Duration(seconds: 21));

    expect(syncRequests, 1);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.lastError, isNull);
    provider.dispose();
  });
}
