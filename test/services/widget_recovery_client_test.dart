import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _facts() => {
  'storeRevision': 8,
  'ownerEpoch': 'old/epoch %2F',
  'binding': {'kind': 'account', 'key': 'foreign literal / é'},
  'desiredPresentation': {'revision': 12, 'locale': 'en'},
  'appliedPresentationRevision': 11,
  'lastOperationId': 'previous-recovery',
  'lastRequestDigest': List.filled(64, 'a').join(),
};

WidgetPublication _presentation() => WidgetPublication(
  ownerEpoch: 'unassigned',
  publicationRevision: 0,
  localeRevision: 13,
  state: WidgetPublicationState.cleared,
  locale: AppLocale.en,
  snapshotDay: '',
  snapshotUtcOffsetMinutes: 0,
  capturedAtMillis: 0,
  values: WidgetPublication.clearedValuesFrom({
    for (final key in WidgetPublication.valueKeys)
      key: HomeWidgetService.accountPayloadDefaults[key]!,
  }),
);

Map<String, Object?> _ack() => {
  'status': 'applied',
  'operationId': 'new-recovery',
  'committedStoreRevision': 9,
  'ownerEpoch': 'new/epoch',
  'publicationRevision': 0,
  'desiredPresentationRevision': 13,
  'appliedPresentationRevision': 13,
  'documentState': 'cleared',
  'refreshRequested': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('duoyi/recovery-client-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late WidgetPublicationClient client;
  late FutureOr<Object?> Function(MethodCall) handler;
  setUp(() {
    client = WidgetPublicationClient(channel: channel);
    handler = (_) => throw StateError('Unscripted channel call');
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<WidgetRecoveryFacts> inspect() async {
    handler = (call) {
      expect(call.method, 'inspectWidgetStoreRecovery');
      expect(call.arguments, isNull);
      return {'status': 'inspected', 'facts': _facts()};
    };
    return (await client.inspectRecovery()).facts!;
  }

  Future<WidgetStoreRequest> request({bool cleanup = false}) async =>
      WidgetStoreRequest.recover(
        operationId: 'new-recovery',
        expected: await inspect(),
        context: cleanup
            ? WidgetRecoveryContext.cleanup(scopeToken: 'cleanup-generation')
            : WidgetRecoveryContext.workspace(
                scopeToken: 'workspace-generation',
                workspaceBinding: WidgetWorkspaceBinding(
                  kind: 'guest',
                  key: 'validated local / é',
                ),
              ),
        presentation: _presentation(),
      );

  test(
    'inspection preserves literal facts without document or capability',
    () async {
      final facts = await inspect();
      expect(facts.ownerEpoch, 'old/epoch %2F');
      expect(facts.binding!.key, 'foreign literal / é');
      expect(facts.desiredRevision, 12);
      expect(facts.desiredLocale, AppLocale.en);
      expect(facts.appliedRevision, 11);
      expect(facts.lastOperationId, 'previous-recovery');
    },
  );

  for (final field in _facts().keys) {
    test('inspection rejects missing $field', () async {
      final facts = _facts()..remove(field);
      handler = (_) => {'status': 'inspected', 'facts': facts};
      final result = await client.inspectRecovery();
      expect(result.status, 'invalidResponse');
      expect(result.facts, isNull);
    });
  }

  final malformedFacts = <String, Map<String, Object?>>{
    'fractional revision': {..._facts(), 'storeRevision': 8.0},
    'zero revision': {..._facts(), 'storeRevision': 0},
    'overflow revision': {
      ..._facts(),
      'storeRevision': WidgetPublication.maxExactJsonInteger + 1,
    },
    'blank epoch': {..._facts(), 'ownerEpoch': ' \n'},
    'invalid binding': {
      ..._facts(),
      'binding': {'kind': 'account', 'key': ''},
    },
    'unknown binding kind': {
      ..._facts(),
      'binding': {'kind': 'anonymous', 'key': 'x'},
    },
    'binding extra field': {
      ..._facts(),
      'binding': {'kind': 'guest', 'key': 'x', 'lease': 'x'},
    },
    'desired float': {
      ..._facts(),
      'desiredPresentation': {'revision': 12.0, 'locale': 'en'},
    },
    'desired bool': {
      ..._facts(),
      'desiredPresentation': {'revision': true, 'locale': 'en'},
    },
    'negative desired': {
      ..._facts(),
      'desiredPresentation': {'revision': -1, 'locale': 'en'},
    },
    'unknown locale': {
      ..._facts(),
      'desiredPresentation': {'revision': 12, 'locale': 'EN'},
    },
    'desired extra field': {
      ..._facts(),
      'desiredPresentation': {'revision': 12, 'locale': 'en', 'values': {}},
    },
    'applied exceeds desired': {..._facts(), 'appliedPresentationRevision': 13},
    'negative applied': {..._facts(), 'appliedPresentationRevision': -1},
    'float applied': {..._facts(), 'appliedPresentationRevision': 11.0},
    'blank receipt': {..._facts(), 'lastOperationId': ''},
    'uppercase digest': {
      ..._facts(),
      'lastRequestDigest': List.filled(64, 'A').join(),
    },
    'short digest': {..._facts(), 'lastRequestDigest': 'a'},
    'document leak': {..._facts(), 'document': {}},
    'lease leak': {..._facts(), 'writerLeaseId': 'not-authority'},
  };
  for (final entry in malformedFacts.entries) {
    test('inspection rejects ${entry.key}', () async {
      handler = (_) => {'status': 'inspected', 'facts': entry.value};
      final result = await client.inspectRecovery();
      expect(result.status, 'invalidResponse');
      expect(result.facts, isNull);
    });
  }

  for (final invalid in <Object?>[
    null,
    {'status': 'ready', 'facts': _facts()},
    {'status': 'inspected'},
    {'status': 'inspected', 'facts': _facts(), 'writerLeaseId': 'x'},
    {'status': 'absent'},
    {'status': 'busy', 'facts': _facts()},
  ]) {
    test('inspection rejects unexpected response shape $invalid', () async {
      handler = (_) => invalid;
      expect((await client.inspectRecovery()).status, 'invalidResponse');
    });
  }

  test('sealed facts admit null binding and exact integer ceiling', () async {
    handler = (_) => {
      'status': 'inspected',
      'facts': {
        ..._facts(),
        'binding': null,
        'storeRevision': WidgetPublication.maxExactJsonInteger,
        'desiredPresentation': {
          'revision': WidgetPublication.maxExactJsonInteger,
          'locale': 'zh',
        },
        'appliedPresentationRevision': WidgetPublication.maxExactJsonInteger,
      },
    };
    final facts = (await client.inspectRecovery()).facts!;
    expect(facts.binding, isNull);
    expect(facts.storeRevision, WidgetPublication.maxExactJsonInteger);
    expect(facts.desiredLocale, AppLocale.zh);
  });

  for (final cleanup in [false, true]) {
    test(
      '${cleanup ? 'cleanup' : 'workspace'} intent is immutable and seals only',
      () async {
        final operation = await request(cleanup: cleanup);
        final args = operation.arguments;
        final context = args['recoveryContext'] as Map;
        expect(operation.expected, isNull);
        expect(operation.recoveryFacts!.storeRevision, 8);
        expect(args['expectedOwnerEpoch'], 'old/epoch %2F');
        expect(context['kind'], cleanup ? 'cleanup' : 'workspace');
        expect(
          context['binding'],
          cleanup ? null : {'kind': 'guest', 'key': 'validated local / é'},
        );
        expect(() => args['operationId'] = 'changed', throwsUnsupportedError);
        expect(() => context['scopeToken'] = 'changed', throwsUnsupportedError);
        expect(
          () => (args['presentation'] as Map)['revision'] = 0,
          throwsUnsupportedError,
        );
        handler = (call) {
          expect(call.method, 'recoverWidgetStore');
          expect(call.arguments, args);
          return _ack();
        };
        final result = await client.submit(operation);
        expect(result.committed, isTrue);
        expect(result.writerLeaseId, isNull);
        expect(result.refreshRequested, isFalse);
      },
    );
  }

  test('visible receipt cannot be reused as a new recovery identity', () async {
    final facts = await inspect();
    for (final id in ['', '  ', facts.lastOperationId]) {
      expect(
        () => WidgetStoreRequest.recover(
          operationId: id,
          expected: facts,
          context: WidgetRecoveryContext.cleanup(scopeToken: 'current-cleanup'),
          presentation: _presentation(),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => WidgetRecoveryContext.cleanup(scopeToken: ' '),
      throwsFormatException,
    );
  });

  final malformedAcks = <String, Map<String, Object?>>{
    'receipt replay': {..._ack(), 'status': 'alreadyApplied'},
    'unchanged epoch': {..._ack(), 'ownerEpoch': 'old/epoch %2F'},
    'wrong identity': {..._ack(), 'operationId': 'previous-recovery'},
    'wrong revision': {..._ack(), 'committedStoreRevision': 10},
    'fractional revision': {..._ack(), 'committedStoreRevision': 9.0},
    'nonzero publication': {..._ack(), 'publicationRevision': 1},
    'stale presentation': {..._ack(), 'desiredPresentationRevision': 12},
    'unapplied presentation': {..._ack(), 'appliedPresentationRevision': 12},
    'published content': {..._ack(), 'documentState': 'published'},
    'blocked content': {..._ack(), 'documentState': 'blocked'},
    'refresh': {..._ack(), 'refreshRequested': true},
    'lease grant': {..._ack(), 'writerLeaseId': 'forbidden'},
    'extra binding': {..._ack(), 'binding': null},
  };
  for (final entry in malformedAcks.entries) {
    test('recovery acknowledgement rejects ${entry.key}', () async {
      final operation = await request();
      handler = (_) => entry.value;
      final result = await client.submit(operation);
      expect(result.status, 'invalidResponse');
      expect(result.committed, isFalse);
      expect(result.writerLeaseId, isNull);
    });
  }

  test(
    'native uncertainty never becomes a committed recovery receipt',
    () async {
      final operation = await request();
      handler = (_) => {
        'status': 'durabilityUnknown',
        'operationId': 'new-recovery',
        'refreshRequested': false,
      };
      final result = await client.submit(operation);
      expect(result.status, 'durabilityUnknown');
      expect(result.committed, isFalse);
    },
  );

  for (final failure in ['platform', 'missing', 'timeout']) {
    test(
      '$failure inspection grants no facts and mutation remains uncertain',
      () async {
        final operation = await request();
        client = WidgetPublicationClient(
          channel: channel,
          responseTimeout: const Duration(milliseconds: 20),
        );
        final lateResponses = <Completer<Object?>>[];
        handler = (_) {
          if (failure == 'platform') throw PlatformException(code: 'lost');
          if (failure == 'missing') throw MissingPluginException();
          final late = Completer<Object?>();
          lateResponses.add(late);
          return late.future;
        };
        final inspection = await client.inspectRecovery();
        expect(inspection.status, 'unavailable');
        expect(inspection.facts, isNull);
        final result = await client.submit(operation);
        expect(
          result.status,
          failure == 'missing' ? 'unavailable' : 'responseUnknown',
        );
        expect(result.committed, isFalse);
        for (final late in lateResponses) {
          late.complete(_ack());
        }
        await Future<void>.delayed(Duration.zero);
        expect(result.committed, isFalse);
      },
    );
  }
}
