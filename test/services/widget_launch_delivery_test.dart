import 'dart:async';

import 'package:duoyi/services/widget_launch_service.dart';
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
      expect(events, [uri]);
      expect(harness.acknowledged, isEmpty);
      expect(harness.service.ownsDelivery(uri), isTrue);

      subscribeResult.complete([delivery]);
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        uri,
      ], reason: 'the overlapping snapshot has the same delivery ID');
      expect(
        harness.acknowledged,
        isEmpty,
        reason: 'an in-flight duplicate is not terminal',
      );

      await harness.service.acknowledge(uri);
      expect(harness.acknowledged, ['initial-1']);
    },
  );

  test('distinct delivery IDs for the same action are both emitted', () async {
    final harness = _LaunchHarness('same_action_distinct_taps');
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

    await harness.emit(_delivery('tap-1'));
    await harness.emit(_delivery('tap-2'));

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
        return null;
      }
      return null;
    };
    harness.listen(events.add);
    await subscribed.future;

    await harness.emit(delivery);
    expect(events, [uri]);
    await harness.service.acknowledge(uri);
    expect(ackAttempts, 1);

    await harness.emit(delivery);
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
