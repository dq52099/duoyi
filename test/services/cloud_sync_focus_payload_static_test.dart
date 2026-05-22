import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'cloud sync includes focus rooms, strict penalties, reward shop, and shared calendar payloads',
    () {
      final provider = File(
        'lib/providers/cloud_sync_provider.dart',
      ).readAsStringSync();
      final backend = File('backend/main.py').readAsStringSync();

      expect(
        provider,
        contains("'pomodoro_focus_penalties': 'focus_penalties'"),
      );
      expect(provider, contains("'duoyi_focus_rooms': 'focus_rooms'"));
      expect(provider, contains("'duoyi_virtual_rewards': 'virtual_rewards'"));
      expect(provider, contains("'theme_shop_state': 'theme_shop_state'"));
      expect(
        provider,
        contains("'duoyi_local_calendar_events_v1': 'calendar_events'"),
      );
      expect(provider, contains("'duoyi_goals': 'goals'"));
      expect(provider, contains("'calendar_events': _WorkspacePayloadSpec"));
      expect(provider, contains("itemType: 'goal'"));
      expect(provider, contains("itemType: 'calendar_event'"));
      expect(provider, contains('_mergeRemoteWorkspaceItems('));

      expect(backend, contains('focus_penalties TEXT DEFAULT'));
      expect(backend, contains('virtual_rewards TEXT DEFAULT'));
      expect(backend, contains('focus_rooms TEXT DEFAULT'));
      expect(backend, contains('theme_shop_state TEXT DEFAULT'));
      expect(backend, contains('calendar_events TEXT DEFAULT'));
      expect(backend, contains('focus_penalties: list = []'));
      expect(backend, contains('virtual_rewards: dict = {}'));
      expect(backend, contains('focus_rooms: dict = {}'));
      expect(backend, contains('theme_shop_state: dict = {}'));
      expect(backend, contains('calendar_events: list = []'));
      expect(
        backend,
        contains('server_calendar_events = _list("calendar_events")'),
      );
      expect(backend, contains('merged_calendar_events = _merge_by_timestamp'));
      expect(backend, contains('calendar_events=excluded.calendar_events'));
      expect(backend, contains('"calendar_events": merged_calendar_events'));
      expect(backend, contains("calendar_events='[]'"));
      expect(
        backend,
        contains(
          'length(sd.diaries) + length(sd.goals) + length(sd.calendar_events)',
        ),
      );
    },
  );
}
