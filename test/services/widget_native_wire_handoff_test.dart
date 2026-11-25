import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_launch_service.dart';
import 'package:duoyi/services/widget_link_dispatch.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Packets below are copied byte-for-byte from the real Java codec producer.
// The test messenger transports them to the real Dart consumer. The workspace
// and publication read are controlled fixtures, not authenticated storage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Java backlog bytes precede overlapping hot bytes without automatic ACK',
    () async {
      final wire = _NativeWire();
      final harness = _WireHarness('backlog', wire);
      addTearDown(harness.close);
      final entered = Completer<void>();
      final result = Completer<ByteData?>();
      final events = <Uri>[];
      harness.respond = (call) {
        if (call.method == 'subscribe') {
          entered.complete();
          return result.future;
        }
        return wire.bytes('successNullReply');
      };
      harness.listen(events.add);
      await entered.future;
      await harness.emit('overlapHot');
      await _settle();
      expect(events, isEmpty);
      expect(harness.acks, isEmpty);
      expect(harness.service.ownsDelivery(wire.uri('overlapHot')), isFalse);

      result.complete(wire.bytes('orderedBacklogReply'));
      await _settle();
      final backlog = wire.expected('orderedBacklogReply') as List;
      expect(
        events,
        backlog.map((row) => Uri.parse((row as Map)['uri'] as String)).toList(),
      );
      expect(events.first, wire.uri('overlapHot'));
      expect(harness.acks, isEmpty);
      await harness.emit('legacyHot');
      await _settle();
      expect(events.length, 3);
      expect(events.last, wire.uri('legacyHot'));
      expect(
        events.last.queryParameters.containsKey('widget_account'),
        isFalse,
      );
      expect(harness.acks, isEmpty);
      await harness.service.acknowledge(events.first);
      expect(harness.acks, [events.first.queryParameters['widget_delivery']]);
      expect(harness.requests.first, wire.byteList('subscribeRequest'));
    },
  );

  test(
    'Java receipts for the same target stay distinct and terminal replay only reACKs',
    () async {
      final wire = _NativeWire();
      final harness = _WireHarness('receipts', wire);
      addTearDown(harness.close);
      final events = <Uri>[];
      harness.listen(events.add);
      await _settle();
      await harness.emit('repeatedHotFirst');
      await harness.emit('repeatedHotSecond');
      await harness.emit('repeatedHotFirst');
      await _settle();
      final first = wire.uri('repeatedHotFirst');
      final second = wire.uri('repeatedHotSecond');
      expect(
        first.queryParameters['widget_delivery'],
        isNot(second.queryParameters['widget_delivery']),
      );
      Uri target(Uri uri) => uri.replace(
        queryParameters: Map<String, String>.from(uri.queryParameters)
          ..remove('widget_delivery'),
      );
      expect(target(first), target(second));
      expect(events, [first, second]);
      expect(harness.acks, isEmpty);
      await harness.service.acknowledge(first);
      await harness.emit('repeatedHotFirst');
      await _settle();
      expect(events, [first, second]);
      expect(harness.acks, [
        first.queryParameters['widget_delivery'],
        first.queryParameters['widget_delivery'],
      ]);
      expect(harness.requests.first, wire.byteList('subscribeRequest'));
      expect(harness.requests.skip(1).toList(), [
        wire.byteList('repeatAckRequest'),
        wire.byteList('repeatAckRequest'),
      ]);
    },
  );

  test(
    'Java action bytes keep literal IDs and reject a changed publication workspace',
    () async {
      final wire = _NativeWire();
      final harness = _WireHarness('action', wire);
      addTearDown(harness.close);
      final received = Completer<Uri>();
      harness.listen(received.complete);
      await _settle();
      await harness.emit('actionHot');
      final uri = await received.future;
      expect(uri, wire.uri('actionHot'));
      expect(uri.queryParameters['id'], 'read /中文?&=+');
      expect(uri.pathSegments, ['complete_todo']);
      expect(uri.queryParameters['widget_account'], 'account-A-fixture664');

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('duoyi/native-wire/publication-action');
      final client = WidgetPublicationClient(channel: channel);
      final now = DateTime.utc(2026, 11, 10, 12);
      expect(now.toLocal().timeZoneOffset, Duration.zero);
      var current = true;
      var binding = 'owner-A';
      var reads = 0;
      var hydrations = 0;
      FutureOr<Object?> Function() response = () =>
          _snapshot(now, binding, 'account-A-fixture664');
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readWidgetStore');
        reads++;
        return response();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<WidgetLinkDispatch> resolve() => WidgetLinkDispatch.resolve(
        uri,
        hydrate: () async {
          hydrations++;
        },
        validate: (candidate) => isCurrentWidgetPublicationAction(
          uri: candidate,
          client: client,
          clock: () => now,
          workspace: ValidatedWidgetWorkspace(
            binding: WidgetWorkspaceBinding(kind: 'account', key: binding),
            accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
            isCurrent: () => current,
          ),
        ),
        isCurrent: () => current,
      );

      final accepted = await resolve();
      expect(accepted.stale, isFalse);
      expect(accepted.uri?.queryParameters['id'], 'read /中文?&=+');
      expect(accepted.uri?.queryParameters.containsKey('source'), isFalse);
      expect(
        accepted.uri?.queryParameters['widget_delivery'],
        uri.queryParameters['widget_delivery'],
      );
      expect(harness.acks, isEmpty);
      await harness.service.acknowledge(accepted.uri!);
      expect(harness.requests.last, wire.byteList('actionAckRequest'));

      binding = 'owner-B';
      response = () => _snapshot(now, binding, 'account-B-fixture664');
      final rejected = await resolve();
      expect(rejected.stale, isTrue);
      expect(rejected.uri, isNull);
      expect(uri.queryParameters['widget_account'], 'account-A-fixture664');
      expect(reads, 2);
      expect(hydrations, 2);

      binding = 'owner-A';
      final entered = Completer<void>(), delayed = Completer<Object?>();
      response = () {
        entered.complete();
        return delayed.future;
      };
      final late = resolve();
      await entered.future;
      current = false;
      delayed.complete(_snapshot(now, binding, 'account-A-fixture664'));
      expect((await late).uri, isNull);
      expect(reads, 3);
      expect(hydrations, 3);
    },
  );
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _NativeWire {
  _NativeWire()
    : document =
          jsonDecode(
                File(
                  'test/fixtures/widget_native_wire_698.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic> {
    expect(document['schema'], 1);
    expect(
      (document['producer'] as Map)['wireLogSha256'],
      'af6294e651fcfb9c7ec47f9b0770014a72fdb6c3398cb8cdf15bfa19ce862092',
    );
  }
  final Map<String, dynamic> document;
  Map<String, dynamic> packet(String name) =>
      (document['packets'] as Map)[name] as Map<String, dynamic>;
  Object? expected(String name) => packet(name)['expected'];
  List<int> byteList(String name) =>
      base64Decode(packet(name)['wireBase64'] as String);
  ByteData bytes(String name) =>
      ByteData.sublistView(Uint8List.fromList(byteList(name)));
  Uri uri(String name) => Uri.parse((expected(name) as Map)['uri'] as String);
}

class _WireHarness {
  _WireHarness(String suffix, this.wire)
    : channel = MethodChannel('duoyi/native-wire/$suffix') {
    service = WidgetLaunchService(channel: channel);
    respond = (call) => wire.bytes(
      call.method == 'subscribe' ? 'emptyBacklogReply' : 'successNullReply',
    );
    messenger.setMockMessageHandler(channel.name, (data) async {
      expect(data, isNotNull);
      requests.add(
        data!.buffer
            .asUint8List(data.offsetInBytes, data.lengthInBytes)
            .toList(),
      );
      final call = codec.decodeMethodCall(data);
      if (call.method == 'ack') acks.add(call.arguments as String);
      return respond(call);
    });
  }
  final _NativeWire wire;
  final MethodChannel channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static const codec = StandardMethodCodec();
  late final WidgetLaunchService service;
  late FutureOr<ByteData?> Function(MethodCall) respond;
  final requests = <List<int>>[];
  final acks = <String>[];
  StreamSubscription<Uri>? subscription;
  void listen(void Function(Uri) callback) {
    subscription = service.links.listen(callback);
  }

  Future<void> emit(String name) async {
    await messenger.handlePlatformMessage(channel.name, wire.bytes(name), null);
  }

  Future<void> close() async {
    await subscription?.cancel();
    await _settle();
    messenger.setMockMessageHandler(channel.name, null);
    channel.setMethodCallHandler(null);
  }
}

Map<String, Object?> _snapshot(
  DateTime captured,
  String binding,
  String epoch,
) => {
  'status': 'ready',
  'storeRevision': 3,
  'binding': {'kind': 'account', 'key': binding},
  'ownerEpoch': epoch,
  'leaseState': 'active',
  'desiredPresentation': {'revision': 2, 'locale': 'en'},
  'document': WidgetPublication(
    ownerEpoch: epoch,
    publicationRevision: 1,
    localeRevision: 2,
    state: WidgetPublicationState.published,
    locale: AppLocale.en,
    snapshotDay: '2026-11-10',
    snapshotUtcOffsetMinutes: 0,
    capturedAtMillis: captured.millisecondsSinceEpoch,
    values: WidgetPublication.clearedValuesFrom({
      for (final key in WidgetPublication.valueKeys)
        key: HomeWidgetService.accountPayloadDefaults[key]!,
    }),
  ).toJson(),
  'lastOperationId': 'synthetic-native-wire-read',
  'lastRequestDigest': 'a' * 64,
};
