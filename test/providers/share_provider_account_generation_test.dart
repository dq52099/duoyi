import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'unloaded shared workspace roles deny edits and private spaces allow them',
    () {
      final provider = ShareProvider();
      expect(provider.roleFor('not-loaded'), WorkspaceRole.viewer);
      expect(provider.canEdit('not-loaded'), isFalse);
      expect(provider.canEdit(null), isTrue);
      expect(provider.canEdit(''), isTrue);
      expect(provider.canEdit('private'), isTrue);
      provider.dispose();
    },
  );

  test(
    'loaded workspace roles are enforced and reset revokes editing',
    () async {
      var userId = 'owner';
      final provider = ShareProvider()
        ..userIdGetter = (() => userId)
        ..apiClientGetter = () => ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-test-token',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/workspaces') {
              return http.Response(
                json.encode([
                  {
                    'id': 'shared',
                    'name': 'Synthetic workspace',
                    'owner_user_id': 'owner',
                    'created_at': '2026-06-01T00:00:00.000Z',
                    'updated_at': '2026-06-01T00:00:00.000Z',
                    'members': [
                      for (final role in ['editor', 'viewer'])
                        {
                          'workspace_id': 'shared',
                          'user_id': role,
                          'username': role,
                          'role': role,
                          'joined_at': '2026-06-01T00:00:00.000Z',
                        },
                    ],
                  },
                ]),
                200,
                headers: _jsonHeaders,
              );
            }
            return http.Response('[]', 200, headers: _jsonHeaders);
          }),
        );
      await provider.load();
      expect(provider.canEdit('shared'), isTrue);
      userId = 'editor';
      expect(provider.canEdit('shared'), isTrue);
      userId = 'viewer';
      expect(provider.canEdit('shared'), isFalse);
      userId = 'outsider';
      expect(provider.canEdit('shared'), isFalse);
      userId = 'owner';
      provider.resetLocalState();
      expect(provider.canEdit('shared'), isFalse);
      provider.dispose();
    },
  );

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

  test(
    'workspace load is deduplicated while in flight and shortly after',
    () async {
      var workspaceRequests = 0;
      final firstWorkspaceResponse = Completer<http.Response>();
      final firstWorkspaceRequestStarted = Completer<void>();
      final provider = ShareProvider()
        ..apiClientGetter = () => ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/workspaces') {
              workspaceRequests++;
              if (workspaceRequests == 1) {
                firstWorkspaceRequestStarted.complete();
                return firstWorkspaceResponse.future;
              }
              return http.Response(
                json.encode([
                  {
                    'id': 'workspace-$workspaceRequests',
                    'name': 'Workspace $workspaceRequests',
                    'owner_user_id': 'admin-id',
                    'created_at': '2026-06-01T00:00:00.000Z',
                    'updated_at': '2026-06-01T00:00:00.000Z',
                  },
                ]),
                200,
                headers: _jsonHeaders,
              );
            }
            if (request.url.path == '/api/workspaces/mentions') {
              return http.Response('[]', 200, headers: _jsonHeaders);
            }
            return http.Response('not found', 404);
          }),
        );

      final firstLoad = provider.load();
      final duplicateLoad = provider.load();
      expect(identical(firstLoad, duplicateLoad), isTrue);
      await firstWorkspaceRequestStarted.future;
      expect(workspaceRequests, 1);

      firstWorkspaceResponse.complete(
        http.Response(
          json.encode([
            {
              'id': 'workspace-1',
              'name': 'Workspace 1',
              'owner_user_id': 'admin-id',
              'created_at': '2026-06-01T00:00:00.000Z',
              'updated_at': '2026-06-01T00:00:00.000Z',
            },
          ]),
          200,
          headers: _jsonHeaders,
        ),
      );
      await firstLoad;
      expect(workspaceRequests, 1);

      await provider.load();
      expect(workspaceRequests, 1);

      await provider.load(force: true);
      expect(workspaceRequests, 2);
    },
  );
}

const _jsonHeaders = {'content-type': 'application/json'};
