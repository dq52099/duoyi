import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold start replaces a blank stored nonce before publishing', () async {
    // Keep this in its own test isolate: account resets deliberately generate
    // a nonce and therefore cannot reproduce initialization from native data.
    const channel = MethodChannel('home_widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const oldNonce = ' \t\n\u00a0';
    final stored = <String, Object?>{'widget_account_nonce': oldNonce};
    final writes = <String>[];
    SharedPreferences.setMockInitialValues({});
    HomeWidgetService.supportedForTesting = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'getWidgetData':
          return stored[args!['id']];
        case 'saveWidgetData':
          final key = args!['id'] as String;
          stored[key] = args['data'];
          writes.add(key);
          return true;
        default:
          return true;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      HomeWidgetService.supportedForTesting = null;
    });

    expect(await HomeWidgetService.init(), isTrue);
    expect(writes, isEmpty, reason: 'init must not publish outside the queue');
    final theme = HomeWidgetThemePayload.fromThemeProvider(ThemeProvider());
    Future<bool> push() => HomeWidgetService.push(
      todoCount: 0,
      habitPercent: 0,
      pomodoroToday: 0,
      focusMinutesToday: 0,
      strings: BrandStrings.defaultBrand,
      theme: theme,
    );
    expect(await push(), isTrue);
    final nonce = stored['widget_account_nonce'] as String;
    expect(nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(nonce, isNot(oldNonce));
    expect(writes.last, 'widget_snapshot_day');
    final currentAction = Uri.parse('duoyi://action/complete_todo').replace(
      queryParameters: {
        'source': 'widget',
        'id': 'task',
        'widget_day': stored['widget_snapshot_day'].toString(),
        'widget_offset': stored['widget_snapshot_utc_offset_minutes']
            .toString(),
        'widget_account': nonce,
      },
    );
    expect(
      await HomeWidgetService.isCurrentWidgetAction(currentAction),
      isTrue,
    );
    expect(
      await HomeWidgetService.isCurrentWidgetAction(
        currentAction.replace(
          queryParameters: {
            ...currentAction.queryParameters,
            'widget_account': oldNonce,
          },
        ),
      ),
      isFalse,
    );
    expect(await HomeWidgetService.init(), isTrue);
    expect(await push(), isTrue);
    expect(stored['widget_account_nonce'], nonce);
  });
}
