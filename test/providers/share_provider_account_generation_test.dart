import 'dart:async';
import 'dart:convert';

import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'late workspace load from previous account is discarded after reset',
    () async {
      final workspaceResponse = Completer<http.Response>();
      final workspaceRequestStarted = Completer<void>();
      final provider = ShareProvider()
        ..apiClientGetter = () => ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/workspaces') {
              if (!workspaceRequestStarted.isCompleted) {
                workspaceRequestStarted.complete();
              }
              return workspaceResponse.future;
            }
            if (request.url.path == '/api/workspaces/mentions') {
              return http.Response('[]', 200, headers: _jsonHeaders);
            }
            return http.Response('not found', 404);
          }),
        );

      final loadFuture = provider.load();
      await workspaceRequestStarted.future;

      provider.resetLocalState();
      workspaceResponse.complete(
        http.Response(
          json.encode([
            {
              'id': 'admin-workspace',
              'name': 'Admin Workspace',
              'owner_user_id': 'admin-id',
              'created_at': '2026-06-01T00:00:00.000Z',
              'updated_at': '2026-06-01T00:00:00.000Z',
            },
          ]),
          200,
          headers: _jsonHeaders,
        ),
      );
      await loadFuture;

      expect(provider.workspaces, isEmpty);
      expect(provider.loading, isFalse);
      expect(provider.lastError, isNull);
    },
  );
}

const _jsonHeaders = {'content-type': 'application/json'};
