import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('duoyi/widget-publication-action-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DateTime now;
  late bool current;
  late int reads;
  late String bindingKind, bindingKey;
  late FutureOr<Object?> Function() response;
  final client = WidgetPublicationClient(channel: channel);

  String day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  Map<String, Object?> snapshot({
    String kind = 'account',
    String key = 'owner',
    bool active = true,
    WidgetPublicationState state = WidgetPublicationState.published,
    DateTime? at,
    String epoch = 'literal /%2F é',
  }) {
    final captured = at ?? now;
    final published = state == WidgetPublicationState.published;
    return {
      'status': active ? 'ready' : 'sealed',
      'storeRevision': 3,
      'binding': active ? {'kind': kind, 'key': key} : null,
      'ownerEpoch': epoch,
      'leaseState': active ? 'active' : 'sealed',
      'desiredPresentation': {'revision': 2, 'locale': 'en'},
      'document': WidgetPublication(
        ownerEpoch: epoch,
        publicationRevision: 1,
        localeRevision: 2,
        state: state,
        locale: AppLocale.en,
        snapshotDay: published ? day(captured) : '',
        snapshotUtcOffsetMinutes: published
            ? captured.timeZoneOffset.inMinutes
            : 0,
        capturedAtMillis: captured.millisecondsSinceEpoch,
        values: WidgetPublication.clearedValuesFrom({
          for (final key in WidgetPublication.valueKeys)
            key: HomeWidgetService.accountPayloadDefaults[key]!,
        }),
      ).toJson(),
      'lastOperationId': 'synthetic-operation',
      'lastRequestDigest': 'a' * 64,
    };
  }

  Uri link({String? epoch, DateTime? at}) {
    final date = at ?? now;
    return Uri.parse('duoyi://todo/literal%2Fid').replace(
      queryParameters: {
        'source': 'widget',
        'widget_day': day(date),
        'widget_offset': date.timeZoneOffset.inMinutes.toString(),
        'widget_account': epoch ?? 'literal /%2F é',
      },
    );
  }

  Future<bool> validate(Uri uri, {int? generation}) =>
      isCurrentWidgetPublicationAction(
        uri: uri,
        client: client,
        clock: () => now,
        workspace: ValidatedWidgetWorkspace(
          binding: WidgetWorkspaceBinding(kind: bindingKind, key: bindingKey),
          accountGeneration:
              generation ?? AccountLocalDataCleaner.accountDataGeneration,
          isCurrent: () => current,
        ),
      );
  setUp(() {
    now = DateTime(2026, 10, 20, 12);
    current = true;
    reads = 0;
    bindingKind = 'account';
    bindingKey = 'owner';
    response = () => snapshot();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readWidgetStore');
      reads++;
      return response();
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('current account and literal snapshot link are accepted', () async {
    expect(await validate(link()), isTrue);
    expect(reads, 1);
  });
  test('guest snapshot requires the current guest binding', () async {
    bindingKind = 'guest';
    bindingKey = 'local-device';
    response = () => snapshot(kind: 'guest', key: 'local-device');
    expect(await validate(link()), isTrue);
    bindingKind = 'account';
    bindingKey = 'owner';
    expect(await validate(link()), isFalse);
  });
  for (final binding in [
    ('account', 'other-owner'),
    ('guest', 'owner'),
    ('account', ' owner '),
  ]) {
    test('matching epoch cannot authorize workspace $binding', () async {
      response = () => snapshot(kind: binding.$1, key: binding.$2);
      expect(await validate(link()), isFalse);
    });
  }
  test('revoked host scope does not read storage', () async {
    current = false;
    expect(await validate(link()), isFalse);
    expect(reads, 0);
  });
  test('obsolete account generation does not read storage', () async {
    expect(
      await validate(
        link(),
        generation: AccountLocalDataCleaner.accountDataGeneration - 1,
      ),
      isFalse,
    );
    expect(reads, 0);
  });
  test(
    'account scope revoked while awaiting read rejects late old snapshot',
    () async {
      final reply = Completer<Object?>(), arrived = Completer<void>();
      response = () {
        arrived.complete();
        return reply.future;
      };
      final pending = validate(link());
      await arrived.future;
      current = false;
      reply.complete(snapshot());
      expect(await pending, isFalse);
    },
  );
  test(
    'clock is checked after the read, including midnight rollover',
    () async {
      final reply = Completer<Object?>(), arrived = Completer<void>();
      response = () {
        arrived.complete();
        return reply.future;
      };
      final old = snapshot();
      final pending = validate(link());
      await arrived.future;
      now = DateTime(2026, 10, 21);
      reply.complete(old);
      expect(await pending, isFalse);
    },
  );
  for (final failure in [
    'absent',
    'busy',
    'unavailable',
    'corrupt',
    'unsupported',
    'durabilityUnknown',
  ]) {
    test('storage $failure never authorizes an action', () async {
      response = () => {'status': failure};
      expect(await validate(link()), isFalse);
    });
  }
  for (final state in [
    WidgetPublicationState.cleared,
    WidgetPublicationState.blocked,
  ]) {
    test('${state.name} documents never authorize an action', () async {
      response = () => snapshot(state: state);
      expect(await validate(link()), isFalse);
      response = () => snapshot(active: false, state: state);
      expect(await validate(link()), isFalse);
    });
  }
  test(
    'stale day, different epoch and non-widget sources are rejected',
    () async {
      expect(await validate(link(at: DateTime(2026, 10, 19))), isFalse);
      expect(await validate(link(epoch: 'literal /%2F é')), isFalse);
      expect(await validate(Uri.parse('duoyi://todo/x')), isFalse);
      response = () => snapshot(at: DateTime(2026, 10, 19));
      expect(await validate(link()), isFalse);
    },
  );
}
