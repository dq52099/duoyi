import 'dart:async';

import 'package:duoyi/core/brand_strings.dart';
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
    messenger.setMockMethodCallHandler(channel, null);
    HomeWidgetService.supportedForTesting = null;
  });

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
