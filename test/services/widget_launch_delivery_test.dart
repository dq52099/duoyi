import 'dart:async';

import 'package:duoyi/services/widget_launch_service.dart';
import 'package:duoyi/services/widget_link_dispatch.dart';
import 'package:duoyi/services/widget_calendar_link.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initial drain overlapping a hot delivery emits one copy and waits for ACK',
    () async {
      final harness = _LaunchHarness('initial_hot_overlap');
      addTearDown(harness.close);
      final subscribeEntered = Completer<void>();
      final subscribeResult = Completer<Object?>();
      final events = <Uri>[];
      final delivery = _delivery('initial-1');
      final uri = Uri.parse(delivery['uri']! as String);

      harness.respond = (call) async {
        if (call.method == 'subscribe') {
          subscribeEntered.complete();
          return subscribeResult.future;
        }
        return null;
      };
      harness.listen(events.add);

      await subscribeEntered.future;
      await harness.emit(delivery);
      expect(events, isEmpty, reason: 'hot taps wait for the ordered backlog');
      expect(harness.acknowledged, isEmpty);
      expect(harness.service.ownsDelivery(uri), isFalse);

      subscribeResult.complete([delivery]);
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        uri,
      ], reason: 'the overlapping snapshot has the same delivery ID');
      expect(harness.service.ownsDelivery(uri), isTrue);
      expect(
        harness.acknowledged,
        isEmpty,
        reason: 'an in-flight duplicate is not terminal',
      );

      await harness.service.acknowledge(uri);
      expect(harness.acknowledged, ['initial-1']);
    },
  );

  for (final snapshotIncludesHot in [false, true]) {
    testWidgets(
      'older backlog precedes newer hot date with snapshot overlap $snapshotIncludesHot',
      (tester) async {
        final harness = _LaunchHarness('ordered_dates_$snapshotIncludesHot');
        addTearDown(harness.close);
        final entered = Completer<void>();
        final snapshot = Completer<Object?>();
        final requests = WidgetNavigationRequests();
        final events = <Uri>[];
        final tickets = <WidgetNavigationRequest>[];
        final older = _dateDelivery('older-date', '2024-02-28');
        final newer = _dateDelivery('newer-date', '2024-02-29');
        harness.respond = (call) async {
          if (call.method == 'subscribe') {
            entered.complete();
            return snapshot.future;
          }
          return null;
        };
        harness.listen((uri) {
          events.add(uri);
          tickets.add(requests.capture());
        });
        await entered.future;
        await harness.emit(newer);
        expect(events, isEmpty);
        expect(harness.service.ownsDelivery(_uri(newer)), isFalse);

        snapshot.complete([older, if (snapshotIncludesHot) newer]);
        await tester.pump();
        expect(events, [_uri(older), _uri(newer)]);
        expect(tickets.map((ticket) => ticket.isLatest), [false, true]);
        expect(
          WidgetCalendarLink.dateFromUri(events.last),
          DateTime(2024, 2, 29),
        );
        expect(harness.acknowledged, isEmpty);
      },
    );
  }

  testWidgets('hot dates wait while a backlog ACK is in flight', (
    tester,
  ) async {
    final harness = _LaunchHarness('hot_during_snapshot_ack');
    addTearDown(harness.close);
    final ackEntered = Completer<void>();
    final ackResult = Completer<Object?>();
    final first = _dateDelivery('first-date', '2024-02-27');
    final second = _dateDelivery('second-date', '2024-02-28');
    final hot = _dateDelivery('hot-date', '2024-02-29');
    final events = <Uri>[];
    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        return [
          first,
          {'id': 'corrupt', 'uri': 'invalid'},
          second,
        ];
      }
      if (call.method == 'ack' && call.arguments == 'corrupt') {
        ackEntered.complete();
        return ackResult.future;
      }
      return null;
    };
    harness.listen(events.add);
    await ackEntered.future;
    await harness.emit(hot);
    await tester.pump();
    expect(events, [_uri(first)]);
    expect(harness.service.ownsDelivery(_uri(hot)), isFalse);

    ackResult.complete();
    await tester.pump();
    expect(events, [_uri(first), _uri(second), _uri(hot)]);
    expect(harness.acknowledged, ['corrupt']);
  });

  testWidgets('failed drain keeps hot dates until the ordered retry', (
    tester,
  ) async {
    final harness = _LaunchHarness('buffered_hot_retry');
    addTearDown(harness.close);
    final entered = Completer<void>();
    final firstResult = Completer<Object?>();
    final older = _dateDelivery('retry-old-date', '2024-02-28');
    final newer = _dateDelivery('retry-new-date', '2024-02-29');
    final events = <Uri>[];
    var subscribeCount = 0;
    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        subscribeCount++;
        if (subscribeCount == 1) {
          entered.complete();
          return firstResult.future;
        }
        return [older, newer];
      }
      return null;
    };
    harness.listen(events.add);
    await entered.future;
    await harness.emit(newer);
    firstResult.completeError(PlatformException(code: 'subscribe_failed'));
    await tester.pump();
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 999));
    expect(subscribeCount, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(subscribeCount, 2);
    expect(events, [_uri(older), _uri(newer)]);
    expect(harness.acknowledged, isEmpty);
  });

  test('cancel clears buffered hot dates before reconnect', () async {
    final harness = _LaunchHarness('cancel_buffered_hot');
    addTearDown(harness.close);
    final entered = Completer<void>();
    final firstResult = Completer<Object?>();
    final canceled = _dateDelivery('canceled-hot', '2024-02-28');
    final replacement = _dateDelivery('reconnected-date', '2024-02-29');
    final events = <Uri>[];
    var subscribeCount = 0;
    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        subscribeCount++;
        if (subscribeCount == 1) {
          entered.complete();
          return firstResult.future;
        }
        return [replacement];
      }
      return null;
    };
    final first = harness.listen(events.add);
    await entered.future;
    await harness.emit(canceled);
    await first.cancel();
    final reconnected = Completer<Uri>();
    harness.listen((uri) {
      events.add(uri);
      reconnected.complete(uri);
    });
    await reconnected.future;
    expect(events, [_uri(replacement)]);

    firstResult.complete([canceled]);
    await Future<void>.delayed(Duration.zero);
    expect(events, [_uri(replacement)]);
    expect(harness.service.ownsDelivery(_uri(canceled)), isFalse);
    expect(harness.acknowledged, isEmpty);
  });

  testWidgets('a retry due during a slow backlog ACK runs after the drain', (
    tester,
  ) async {
    final harness = _LaunchHarness('retry_while_draining');
    addTearDown(harness.close);
    final slowAckEntered = Completer<void>();
    final slowAckResult = Completer<Object?>();
    final events = <Uri>[];
    var subscribeCount = 0;
    var failedAckCount = 0;
    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        subscribeCount++;
        return [
          {'id': 'failed-ack', 'uri': 'invalid'},
          if (subscribeCount == 1) {'id': 'slow-ack', 'uri': 'invalid'},
        ];
      }
      if (call.method == 'ack' && call.arguments == 'failed-ack') {
        failedAckCount++;
        if (failedAckCount == 1) throw PlatformException(code: 'ack_failed');
      }
      if (call.method == 'ack' && call.arguments == 'slow-ack') {
        slowAckEntered.complete();
        return slowAckResult.future;
      }
      return null;
    };
    harness.listen(events.add);
    await slowAckEntered.future;
    await tester.pump(const Duration(seconds: 1));
    expect(subscribeCount, 1, reason: 'drains never run concurrently');
    expect(failedAckCount, 1);

    slowAckResult.complete();
    await tester.pump();
    expect(subscribeCount, 2, reason: 'the expired retry is retained');
    expect(failedAckCount, 2);
    expect(events, isEmpty);
    await tester.pump(const Duration(seconds: 16));
    expect(
      subscribeCount,
      2,
      reason: 'a successful retry leaves no spare timer',
    );
  });

  test('distinct delivery IDs for the same action are both emitted', () async {
    final harness = _LaunchHarness('same_action_distinct_taps');
    addTearDown(harness.close);
    final subscribed = Completer<void>();
    final delivered = Completer<void>();
    final events = <Uri>[];
    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        subscribed.complete();
        return <Object?>[];
      }
      return null;
    };
    harness.listen((uri) {
      events.add(uri);
      if (events.length == 2) delivered.complete();
    });
    await subscribed.future;

    await harness.emit(_delivery('tap-1'));
    await harness.emit(_delivery('tap-2'));
    await delivered.future;

    expect(events, hasLength(2));
    expect(
      events.map((uri) => uri.queryParameters['widget_delivery']),
      unorderedEquals(['tap-1', 'tap-2']),
    );
    expect(events.map((uri) => uri.path), everyElement('/checkin_habit'));
  });

  test('a failed ACK can be retried by a repeated terminal delivery', () async {
    final harness = _LaunchHarness('failed_ack_retry');
    addTearDown(harness.close);
    final subscribed = Completer<void>();
    final delivered = Completer<Uri>();
    final repeatedAck = Completer<void>();
    final events = <Uri>[];
    var ackAttempts = 0;
    final delivery = _delivery('retry-1');
    final uri = Uri.parse(delivery['uri']! as String);

    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        subscribed.complete();
        return <Object?>[];
      }
      if (call.method == 'ack') {
        ackAttempts++;
        if (ackAttempts == 1) {
          throw PlatformException(code: 'ack_failed');
        }
        repeatedAck.complete();
        return null;
      }
      return null;
    };
    harness.listen((uri) {
      events.add(uri);
      if (!delivered.isCompleted) delivered.complete(uri);
    });
    await subscribed.future;

    await harness.emit(delivery);
    await delivered.future;
    expect(events, [uri]);
    await harness.service.acknowledge(uri);
    expect(ackAttempts, 1);

    await harness.emit(delivery);
    await repeatedAck.future;
    expect(events, [
      uri,
    ], reason: 'terminal redelivery retries ACK without redispatch');
    expect(ackAttempts, 2);
  });

  test(
    'cancel invalidates an in-flight drain and reconnect drains the queue',
    () async {
      final harness = _LaunchHarness('cancel_reconnect');
      addTearDown(harness.close);
      final firstSubscribeEntered = Completer<void>();
      final firstSubscribeResult = Completer<Object?>();
      final events = <Uri>[];
      final delivery = _delivery('reconnect-1');
      var subscribeCount = 0;

      harness.respond = (call) async {
        if (call.method == 'subscribe') {
          subscribeCount++;
          if (subscribeCount == 1) {
            firstSubscribeEntered.complete();
            return firstSubscribeResult.future;
          }
          return [delivery];
        }
        return null;
      };
      final firstSubscription = harness.listen(events.add);
      await firstSubscribeEntered.future;

      await firstSubscription.cancel();
      firstSubscribeResult.complete([delivery]);
      await Future<void>.delayed(Duration.zero);
      expect(
        events,
        isEmpty,
        reason: 'the canceled generation drops its late snapshot',
      );

      final reconnected = Completer<Uri>();
      harness.listen((uri) {
        events.add(uri);
        reconnected.complete(uri);
      });
      await reconnected.future;

      expect(subscribeCount, 2);
      expect(events, [Uri.parse(delivery['uri']! as String)]);
      expect(
        harness.calls.where((call) => call.method == 'unsubscribe'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'failed subscription automatically drains after the retry timer',
    (tester) async {
      final harness = _LaunchHarness('subscription_retry');
      addTearDown(harness.close);
      final firstAttempt = Completer<void>();
      final delivery = _delivery('subscription-retry-1');
      final events = <Uri>[];
      var subscribeCount = 0;

      harness.respond = (call) async {
        if (call.method == 'subscribe') {
          subscribeCount++;
          if (subscribeCount == 1) {
            firstAttempt.complete();
            throw PlatformException(code: 'subscribe_failed');
          }
          return [delivery];
        }
        return null;
      };
      harness.listen(events.add);

      await firstAttempt.future;
      await tester.pump();
      expect(subscribeCount, 1);

      await tester.pump(const Duration(milliseconds: 999));
      expect(subscribeCount, 1);
      await tester.pump(const Duration(milliseconds: 1));

      expect(subscribeCount, 2);
      expect(events, [Uri.parse(delivery['uri']! as String)]);
    },
  );

  testWidgets(
    'failed ACK automatically re-drains and retries without re-emitting',
    (tester) async {
      final harness = _LaunchHarness('ack_retry_timer');
      addTearDown(harness.close);
      final firstSubscribe = Completer<void>();
      final delivery = _delivery('ack-retry-1');
      final uri = Uri.parse(delivery['uri']! as String);
      final events = <Uri>[];
      var subscribeCount = 0;
      var ackCount = 0;

      harness.respond = (call) async {
        if (call.method == 'subscribe') {
          subscribeCount++;
          if (!firstSubscribe.isCompleted) firstSubscribe.complete();
          return subscribeCount == 1 ? <Object?>[] : [delivery];
        }
        if (call.method == 'ack') {
          ackCount++;
          if (ackCount == 1) throw PlatformException(code: 'ack_failed');
        }
        return null;
      };
      harness.listen(events.add);
      await firstSubscribe.future;
      await tester.pump();

      await harness.emit(delivery);
      await harness.service.acknowledge(uri);
      expect(events, [uri]);
      expect(ackCount, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(subscribeCount, 2);
      expect(ackCount, 2);
      expect(events, [uri], reason: 'the terminal replay retries ACK only');
    },
  );

  test(
    'corrupt envelopes with valid IDs are terminally ACKed without emission',
    () async {
      final harness = _LaunchHarness('corrupt_envelopes');
      addTearDown(harness.close);
      final subscribed = Completer<void>();
      final lastAck = Completer<void>();
      final events = <Uri>[];
      final corrupt = <Map<String, Object?>>[
        {'id': 'bad-uri', 'uri': 'not-a-widget-uri'},
        {
          'id': 'opaque-uri',
          'uri':
              'duoyi:action/complete_todo?source=widget&widget_delivery=opaque-uri',
        },
        {
          'id': 'bad-query',
          'uri':
              'duoyi://action/quick_todo?source=widget&widget_delivery=bad-query&text=%FF',
        },
      ];
      harness.respond = (call) async {
        if (call.method == 'subscribe') {
          subscribed.complete();
          return corrupt;
        }
        if (call.method == 'ack' && call.arguments == 'bad-query') {
          lastAck.complete();
        }
        return null;
      };
      harness.listen(events.add);
      await subscribed.future;
      await lastAck.future;

      expect(events, isEmpty);
      expect(harness.acknowledged, ['bad-uri', 'opaque-uri', 'bad-query']);
    },
  );

  test('ambiguous transport fields are rejected before emitting a date', () async {
    final harness = _LaunchHarness('ambiguous_calendar_transport');
    addTearDown(harness.close);
    final subscribed = Completer<void>();
    final events = <Uri>[];
    harness.respond = (call) async {
      if (call.method == 'subscribe') {
        subscribed.complete();
        return <Object?>[];
      }
      return null;
    };
    harness.listen(events.add);
    await subscribed.future;

    final corrupt = {
      'source-first': 'source=widget&source=other&widget_delivery=source-first',
      'source-last': 'source=other&source=widget&widget_delivery=source-last',
      'delivery-first':
          'source=widget&widget_delivery=delivery-first&widget_delivery=other',
      'delivery-last':
          'source=widget&widget_delivery=other&widget_delivery=delivery-last',
      'same-delivery':
          'source=widget&widget_delivery=same-delivery&widget_delivery=same-delivery',
      'mismatched': 'source=widget&widget_delivery=another-id',
    };
    for (final entry in corrupt.entries) {
      await harness.emit({
        'id': entry.key,
        'uri': 'duoyi://calendar?date=2024-02-29&${entry.value}',
      });
    }
    expect(events, isEmpty);
    expect(harness.acknowledged, corrupt.keys.toList());
  });

  for (final isValid in [true, false]) {
    test(
      'calendar drain preserves delivery until ${isValid ? 'date dispatch' : 'root normalization'} ACK',
      () async {
        final harness = _LaunchHarness('calendar_date_dispatch_$isValid');
        addTearDown(harness.close);
        final id = 'calendar-$isValid';
        final date = isValid ? '2024-02-29' : '2025-02-29';
        final delivered = Completer<Uri>();
        harness.respond = (call) async {
          if (call.method == 'subscribe') {
            return [
              {
                'id': id,
                'uri':
                    'duoyi://calendar?date=$date&source=widget&widget_delivery=$id'
                    '&widget_day=2026-10-11&widget_offset=0&widget_account=owner',
              },
            ];
          }
          return null;
        };
        harness.listen(delivered.complete);
        final original = await delivered.future;
        expect(harness.service.ownsDelivery(original), isTrue);
        expect(harness.acknowledged, isEmpty);
        final result = await WidgetLinkDispatch.resolve(
          original,
          hydrate: () async {},
          validate: (_) async => true,
          isCurrent: () => true,
        );
        if (isValid) {
          expect(
            WidgetCalendarLink.dateFromUri(result.uri!),
            DateTime(2024, 2, 29),
          );
          expect(harness.service.ownsDelivery(result.uri!), isTrue);
          await harness.service.acknowledge(result.uri!);
        } else {
          expect(result.uri, Uri.parse('duoyi://calendar'));
          expect(harness.service.ownsDelivery(result.uri!), isFalse);
          await harness.service.acknowledge(original);
        }
        expect(harness.acknowledged, [id]);
      },
    );
  }

  test('acknowledging malformed or unreceived app links is a no-op', () async {
    final harness = _LaunchHarness('ignore_unreceived_ack');
    addTearDown(harness.close);
    await harness.service.acknowledge(
      Uri.parse('duoyi://calendar?date=%FF&widget_delivery=missing'),
    );
    await harness.service.acknowledge(
      Uri.parse('duoyi://calendar?date=2024-02-29&widget_delivery=missing'),
    );
    expect(harness.acknowledged, isEmpty);
  });
}

class _LaunchHarness {
  _LaunchHarness(String name)
    : channel = MethodChannel('test/widget_launch/$name') {
    respond = (call) async {
      if (call.method == 'subscribe') return <Object?>[];
      return null;
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ack') acknowledged.add(call.arguments! as String);
      return respond(call);
    });
    service = WidgetLaunchService(channel: channel);
  }

  final MethodChannel channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final acknowledged = <String>[];
  final subscriptions = <StreamSubscription<Uri>>[];
  late final WidgetLaunchService service;
  late Future<Object?> Function(MethodCall) respond;

  StreamSubscription<Uri> listen(void Function(Uri) onData) {
    final subscription = service.links.listen(onData);
    subscriptions.add(subscription);
    return subscription;
  }

  Future<void> emit(Map<String, Object?> delivery) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('onLaunch', delivery)),
      null,
    );
  }

  Future<void> close() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
  }
}

Map<String, Object?> _delivery(String id) {
  final uri = Uri.parse('duoyi://action/checkin_habit?id=habit-1').replace(
    queryParameters: {
      'id': 'habit-1',
      'source': 'widget',
      'widget_delivery': id,
    },
  );
  return {'id': id, 'uri': uri.toString()};
}

Uri _uri(Map<String, Object?> delivery) =>
    Uri.parse(delivery['uri']! as String);

Map<String, Object?> _dateDelivery(String id, String date) {
  return {
    'id': id,
    'uri':
        'duoyi://calendar?date=$date&source=widget&widget_delivery=$id'
        '&widget_day=2026-10-11&widget_offset=0&widget_account=owner',
  };
}
