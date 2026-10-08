import 'dart:async';

import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object?> stored;
  late List<String> writes;
  late int refreshes;
  var failRefresh = false;
  String? failSave;
  Completer<void>? saveEntered;
  Completer<void>? saveRelease;
  Completer<void>? refreshEntered;
  Completer<void>? refreshRelease;
  late HomeWidgetThemePayload theme;

  Future<bool> push({
    String title = 'today',
    DateTime? at,
    bool force = false,
  }) => HomeWidgetService.push(
    todoCount: 1,
    habitPercent: 0,
    pomodoroToday: 0,
    focusMinutesToday: 0,
    strings: BrandStrings.defaultBrand,
    todoTop3: [title],
    todoTop3Ids: ['task'],
    theme: theme,
    snapshotAt: at,
    force: force,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stored = {};
    writes = [];
    refreshes = 0;
    failRefresh = false;
    failSave = null;
    saveEntered = null;
    saveRelease = null;
    refreshEntered = null;
    refreshRelease = null;
    theme = HomeWidgetThemePayload.fromThemeProvider(ThemeProvider());
    HomeWidgetService.supportedForTesting = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'setAppGroupId':
          return true;
        case 'getWidgetData':
          return stored[args!['id']];
        case 'saveWidgetData':
          final key = args!['id'] as String;
          if (key == 'todo_top3_1' && saveRelease != null) {
            saveEntered!.complete();
            await saveRelease!.future;
            saveRelease = null;
          }
          if (key == failSave) return false;
          stored[key] = args['data'];
          writes.add(key);
          return true;
        case 'updateWidget':
          refreshes++;
          if (refreshRelease != null) {
            refreshEntered!.complete();
            await refreshRelease!.future;
            refreshRelease = null;
          }
          if (failRefresh) throw PlatformException(code: 'refresh_failed');
          return true;
        default:
          return null;
      }
    });
    HomeWidgetService.resetAccountCache();
    expect(await HomeWidgetService.waitForAccountClear(), isTrue);
    writes.clear();
    refreshes = 0;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    messenger.setMockMethodCallHandler(channel, null);
    HomeWidgetService.supportedForTesting = null;
  });

  test(
    'empty highlights contain no invented rows and follow language changes',
    () async {
      Future<bool> pushEmpty() => HomeWidgetService.push(
        todoCount: 0,
        habitPercent: 0,
        habitActiveCount: 0,
        pomodoroToday: 0,
        focusMinutesToday: 0,
        strings: BrandStrings.defaultBrand,
        theme: theme,
      );
      expect(await pushEmpty(), isTrue);
      expect(stored['widget_locale'], 'zh');
      expect(stored['todo_top3_1'], '今天没有未完成待办');
      expect(stored['goal_highlight_3'], isEmpty);
      expect(stored['schedule_highlight_2'], isEmpty);
      expect(stored['schedule_highlight_3'], isEmpty);
      final previousRefreshes = refreshes;
      I18n.setLocale(AppLocale.en);
      expect(await pushEmpty(), isTrue);
      expect(stored['widget_locale'], 'en');
      expect(stored['todo_top3_1'], 'No open tasks today');
      expect(stored['note_highlight_1'], 'No notes yet');
      expect(
        stored['today_event_summary'],
        I18n.tr('widget.no_schedule_today'),
      );
      expect(stored['focus_summary'], I18n.tr('widget.focus_not_started'));
      expect(stored['habit_summary'], I18n.tr('widget.habit_pending'));
      expect(stored['focus_timer_label'], I18n.tr('widget.focus_countdown'));
      expect(refreshes, greaterThan(previousRefreshes));
    },
  );

  test('account clearing preserves the selected widget language', () async {
    I18n.setLocale(AppLocale.en);
    HomeWidgetService.resetAccountCache();
    expect(await HomeWidgetService.waitForAccountClear(), isTrue);
    expect(stored['widget_locale'], 'en');
    expect(stored['todo_top3_1'], 'No open tasks today');
  });

  test('a language change during native refresh invalidates success', () async {
    refreshEntered = Completer<void>();
    refreshRelease = Completer<void>();
    final pending = push();
    await refreshEntered!.future;
    I18n.setLocale(AppLocale.en);
    refreshRelease!.complete();
    expect(await pending, isFalse);
    final previousRefreshes = refreshes;
    expect(await push(), isTrue);
    expect(stored['widget_locale'], 'en');
    expect(refreshes, greaterThan(previousRefreshes));
  });

  test(
    'language changes invalidate an in-flight snapshot without translating user content',
    () async {
      saveEntered = Completer<void>();
      saveRelease = Completer<void>();
      final old = push(title: '用户原始内容');
      await saveEntered!.future;
      I18n.setLocale(AppLocale.en);
      saveRelease!.complete();
      expect(await old, isFalse);
      expect(stored['widget_snapshot_day'], '');
      expect(refreshes, 0);

      expect(await push(title: '用户原始内容'), isTrue);
      expect(stored['widget_locale'], 'en');
      expect(stored['todo_top3_1'], '· 用户原始内容');
      expect(stored['widget_snapshot_day'], isNotEmpty);
    },
  );

  test(
    'active habit count invalidates deduplication and clears with account',
    () async {
      Future<bool> pushHabits(int count) => HomeWidgetService.push(
        todoCount: 0,
        habitPercent: 0,
        habitActiveCount: count,
        pomodoroToday: 0,
        focusMinutesToday: 0,
        strings: BrandStrings.defaultBrand,
        theme: theme,
      );
      expect(await pushHabits(0), isTrue);
      expect(stored['habit_active_count'], 0);
      final previousRefreshes = refreshes;
      expect(await pushHabits(1), isTrue);
      expect(stored['habit_active_count'], 1);
      expect(refreshes, greaterThan(previousRefreshes));
      HomeWidgetService.resetAccountCache();
      expect(await HomeWidgetService.waitForAccountClear(), isTrue);
      expect(stored['habit_active_count'], 0);
    },
  );

  test(
    'snapshot day is published last and widget actions bind to day, offset and account',
    () async {
      expect(await push(), isTrue);
      expect(writes.last, 'widget_snapshot_day');
      expect(
        writes.indexOf('widget_snapshot_utc_offset_minutes'),
        lessThan(writes.lastIndexOf('widget_snapshot_day')),
      );
      expect(stored['widget_account_nonce'], isNotEmpty);
      final uri = Uri.parse('duoyi://action/complete_todo').replace(
        queryParameters: {
          'source': 'widget',
          'id': 'task',
          'widget_day': stored['widget_snapshot_day'].toString(),
          'widget_offset': stored['widget_snapshot_utc_offset_minutes']
              .toString(),
          'widget_account': stored['widget_account_nonce'].toString(),
        },
      );
      expect(await HomeWidgetService.isCurrentWidgetAction(uri), isTrue);
      expect(
        await HomeWidgetService.isCurrentWidgetAction(
          uri.replace(
            queryParameters: {...uri.queryParameters, 'widget_offset': '10000'},
          ),
        ),
        isFalse,
      );
      HomeWidgetService.resetAccountCache();
      await HomeWidgetService.waitForAccountClear();
      expect(await HomeWidgetService.isCurrentWidgetAction(uri), isFalse);
    },
  );

  test(
    'same payload retries a failed refresh and force always repaints',
    () async {
      failRefresh = true;
      expect(await push(), isFalse);
      final failedCalls = refreshes;
      failRefresh = false;
      expect(await push(), isTrue);
      expect(refreshes, greaterThan(failedCalls));
      final successfulCalls = refreshes;
      expect(await push(), isTrue);
      expect(refreshes, successfulCalls);
      expect(await push(force: true), isTrue);
      expect(refreshes, greaterThan(successfulCalls));
    },
  );

  test('old-date snapshot never gets published as today', () async {
    expect(
      await push(at: DateTime.now().subtract(const Duration(days: 2))),
      isFalse,
    );
    expect(stored['widget_snapshot_day'], '');
    expect(refreshes, 0);
  });

  test(
    'reset invalidates an in-flight payload and queued previous-account push',
    () async {
      saveEntered = Completer<void>();
      saveRelease = Completer<void>();
      final old = push(title: 'old account');
      await saveEntered!.future;
      final queued = push(title: 'queued old account');
      HomeWidgetService.resetAccountCache();
      saveRelease!.complete();
      expect(await old, isFalse);
      expect(await queued, isFalse);
      expect(await HomeWidgetService.waitForAccountClear(), isTrue);
      expect(stored['todo_top3_1_id'], '');
      expect(stored['todo_top3_1'], isNot(contains('old account')));
      expect(stored['widget_snapshot_day'], '');
    },
  );

  test(
    'storage-clear failure is separate from a cleared snapshot refresh failure',
    () async {
      failSave = 'todo_top3_1';
      HomeWidgetService.resetAccountCache();
      expect(await HomeWidgetService.waitForAccountClear(), isFalse);
      failSave = null;
      failRefresh = true;
      HomeWidgetService.resetAccountCache();
      expect(await HomeWidgetService.waitForAccountClear(), isTrue);
      expect(stored['todo_top3_1_id'], '');
      failRefresh = false;
      expect(await push(), isTrue);
    },
  );
}
