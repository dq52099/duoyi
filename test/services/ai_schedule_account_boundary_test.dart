import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => I18n.setLocale(AppLocale.zh));
  test('schedule cancellation follows the currently selected locale', () {
    const error = AiScheduleDiscardedException();
    I18n.setLocale(AppLocale.zh);
    expect(error.message, contains('日程识别已取消'));
    I18n.setLocale(AppLocale.en);
    expect(error.message, contains('schedule request was canceled'));
    expect(AiScheduleDiscardedException.code, 'schedule_discarded');
  });

  test('closed access rejects local parsing before any request', () async {
    final service = AiService();
    addTearDown(service.dispose);
    service.historyAccessAllowed = () => false;
    await expectLater(
      service.createScheduleDraft('Tomorrow meeting'),
      throwsA(isA<AiScheduleDiscardedException>()),
    );
  });

  test('fallback reason survives draft copies without altering user data', () {
    final original = AiScheduleDraft(
      type: AiScheduleType.todo,
      title: 'Literal / 原始标题',
      notes: 'Literal / 原始备注',
      startAt: DateTime(2026, 10, 13),
      warningKind: AiScheduleWarningKind.invalidResponse,
      warning: 'Private diagnostic',
    );
    final copied = original.withSource(AiScheduleSource.localParser);
    expect(copied.warningKind, AiScheduleWarningKind.invalidResponse);
    expect(copied.warning, original.warning);
    expect(copied.title, original.title);
    expect(copied.notes, original.notes);
    expect(copied.startAt, original.startAt);
  });

  for (final transition in ['client', 'token', 'reset', 'dispose', 'access']) {
    for (final outcome in ['success', 'invalid', 'failure']) {
      test(
        'schedule $outcome is discarded after $transition changes',
        () async {
          final started = Completer<void>();
          final release = Completer<http.Response>();
          final client = ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'synthetic-A',
            httpClient: MockClient((request) async {
              started.complete();
              return release.future;
            }),
          );
          final service = AiService();
          var accessAllowed = true;
          service.historyAccessAllowed = () => accessAllowed;
          service.attachClient(client);
          service.updateFromServerConfig({'ai_enabled': true});
          if (transition != 'dispose') addTearDown(service.dispose);
          final future = service.createScheduleDraft(
            'Meeting tomorrow at 3 pm',
            now: DateTime(2026, 10, 12, 9),
          );
          // Attach the error listener before releasing the held transport.
          final checked = expectLater(
            future,
            throwsA(isA<AiScheduleDiscardedException>()),
          );
          await started.future;
          switch (transition) {
            case 'client':
              service.attachClient(
                ApiClient(
                  baseUrl: 'https://duoyi.test',
                  token: 'synthetic-B',
                  httpClient: MockClient((_) async => http.Response('{}', 200)),
                ),
              );
            case 'token':
              client.token = 'synthetic-B';
            case 'reset':
              service.resetLocalState();
            case 'dispose':
              service.dispose();
            case 'access':
              accessAllowed = false;
          }
          final body = switch (outcome) {
            'success' => {
              'content': jsonEncode({
                'type': 'calendar',
                'title': 'Literal returned event',
                'start_at': '2026-10-13T15:00:00',
              }),
            },
            'invalid' => {'content': 'Invalid JSON'},
            _ => {'detail': 'Synthetic upstream failure'},
          };
          release.complete(
            http.Response(
              jsonEncode(body),
              outcome == 'failure' ? 502 : 200,
              headers: {'content-type': 'application/json'},
            ),
          );
          await checked;
        },
      );
    }
  }
}
