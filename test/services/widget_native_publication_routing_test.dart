import 'dart:async';

import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late ThemeProvider theme;
  Future<bool> push() => HomeWidgetService.push(
    todoCount: 2,
    habitPercent: 25,
    habitActiveCount: 4,
    pomodoroToday: 1,
    focusMinutesToday: 30,
    strings: BrandStrings.defaultBrand,
    todoTop3: ['Synthetic task'],
    todoTop3Ids: ['literal/%2F task'],
    theme: HomeWidgetThemePayload.fromThemeProvider(theme),
    firstDayOfWeek: 7,
  );

  setUp(() async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getWidgetData' ? null : true;
    });
    HomeWidgetService.supportedForTesting = true;
    HomeWidgetService.nativePublicationForTesting = true;
    HomeWidgetService.publicationWriter = null;
    HomeWidgetService.publicationActionValidator = null;
    HomeWidgetService.resetAccountCache();
    await HomeWidgetService.waitForAccountClear();
    calls.clear();
    theme = ThemeProvider();
  });
  tearDown(() async {
    await HomeWidgetService.waitForAccountClear();
    HomeWidgetService.publicationWriter = null;
    HomeWidgetService.publicationActionValidator = null;
    HomeWidgetService.nativePublicationForTesting = null;
    HomeWidgetService.supportedForTesting = null;
    theme.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'mobile publisher missing fails closed without preference writes',
    () async {
      expect(await push(), isFalse);
      expect(calls, isEmpty);
    },
  );
  test(
    'complete native publication keeps legacy payload out of preferences',
    () async {
      var publications = 0;
      HomeWidgetService.publicationWriter = (values, capturedAt) async {
        publications++;
        expect(
          values.keys.toSet().containsAll(WidgetPublication.valueKeys),
          isTrue,
        );
        expect(values['todo_top3_1_id'], 'literal/%2F task');
        expect(values['widget_first_day_of_week'], 7);
        expect(
          capturedAt.isAfter(
            DateTime.now().subtract(const Duration(minutes: 1)),
          ),
          isTrue,
        );
        return true;
      };
      expect(await push(), isTrue);
      expect(await push(), isTrue);
      expect(publications, 1);
      expect(calls, isEmpty);
    },
  );
  test('failed native publication retries without a legacy fallback', () async {
    var publications = 0;
    HomeWidgetService.publicationWriter = (_, _) async => ++publications > 1;
    expect(await push(), isFalse);
    expect(await push(), isTrue);
    expect(publications, 2);
    expect(calls, isEmpty);
  });
  test(
    'account reset rejects a late native publisher acknowledgement',
    () async {
      final arrived = Completer<void>(), response = Completer<bool>();
      HomeWidgetService.publicationWriter = (_, _) {
        arrived.complete();
        return response.future;
      };
      final pending = push();
      await arrived.future;
      HomeWidgetService.resetAccountCache();
      response.complete(true);
      expect(await pending, isFalse);
      await HomeWidgetService.waitForAccountClear();
    },
  );
  test(
    'native action validator is required even for a matching legacy link',
    () async {
      final now = DateTime.now();
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('duoyi://todo/x').replace(
        queryParameters: {
          'source': 'widget',
          'widget_day': day,
          'widget_account': 'legacy',
          'widget_offset': now.timeZoneOffset.inMinutes.toString(),
        },
      );
      expect(await HomeWidgetService.isCurrentWidgetAction(uri), isFalse);
      expect(calls, isEmpty);
    },
  );
  test(
    'native action validation result and exceptions never fall back',
    () async {
      final uri = Uri.parse('duoyi://todo/x?source=widget');
      HomeWidgetService.publicationActionValidator = (request) async {
        expect(request, uri);
        return false;
      };
      expect(await HomeWidgetService.isCurrentWidgetAction(uri), isFalse);
      HomeWidgetService.publicationActionValidator = (_) async => true;
      expect(await HomeWidgetService.isCurrentWidgetAction(uri), isTrue);
      HomeWidgetService.publicationActionValidator = (_) async =>
          throw StateError('synthetic unavailable');
      expect(await HomeWidgetService.isCurrentWidgetAction(uri), isFalse);
      expect(calls, isEmpty);
    },
  );
  test('ordinary app links do not require widget authority', () async {
    expect(
      await HomeWidgetService.isCurrentWidgetAction(
        Uri.parse('duoyi://todo/x'),
      ),
      isTrue,
    );
    expect(calls, isEmpty);
  });
  test(
    'standalone native theme update writes no fragmented theme keys',
    () async {
      final payload = HomeWidgetThemePayload.fromThemeProvider(theme);
      expect(await HomeWidgetService.updateTheme(payload), isFalse);
      HomeWidgetService.publicationWriter = (_, _) async => true;
      expect(await HomeWidgetService.updateTheme(payload), isTrue);
      expect(calls, isEmpty);
    },
  );
  test(
    'native init establishes app group without reading legacy account nonce',
    () async {
      expect(await HomeWidgetService.init(), isTrue);
      expect(calls.map((call) => call.method), ['setAppGroupId']);
    },
  );
}
