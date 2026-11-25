import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> _values({int first = 1, String title = ''}) => {
  for (final key in WidgetPublication.valueKeys)
    key: HomeWidgetService.accountPayloadDefaults[key]!,
  'widget_first_day_of_week': first,
  'todo_count': title.isEmpty ? 0 : 1,
  'todo_top3_count': title.isEmpty ? 0 : 1,
  'todo_top3_1': title,
  'todo_top3_1_id': title.isEmpty ? '' : 'synthetic-id',
};

WidgetDevicePresentation _presentation([int first = 1]) =>
    WidgetDevicePresentation(
      locale: AppLocale.en,
      completeValues: _values(first: first),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final cleanup in [false, true]) {
    test(
      '${cleanup ? 'cleanup' : 'workspace'} recovery seals, then requires separate open and fresh capture',
      () async {
        final fixture = _Peer();
        await fixture.quarantine();
        final originalCapture = fixture.oldCapture!;
        final result = await fixture.recover(cleanup: cleanup);
        expect(result.storeCommitted, isTrue);
        expect(result.barrierConfirmed, isTrue);
        expect(result.refreshRequested, isFalse);
        expect(fixture.controller.ready, isFalse);
        expect(fixture.controller.requiresDurabilityRecovery, isFalse);
        expect(fixture.controller.hasPendingOperation, isFalse);
        expect(fixture.controller.capture(_values()), isNull);
        final calls = fixture.calls.length;
        expect(
          (await fixture.controller.publish(originalCapture)).storeCommitted,
          isFalse,
        );
        expect((await fixture.controller.retryPending()).status, 'blocked');
        expect(fixture.calls.length, calls);
        final recovery = fixture.calls.singleWhere(
          (call) => call.method == 'recoverWidgetStore',
        );
        final context = (recovery.arguments as Map)['recoveryContext'] as Map;
        expect(context['kind'], cleanup ? 'cleanup' : 'workspace');
        expect(
          context['binding'],
          cleanup ? null : fixture.workspace.binding.toJson(),
        );
        expect(fixture.document!.values['todo_top3_1'], '');
        expect(fixture.document!.ownerEpoch, isNot('epoch-1'));
        expect(
          (await fixture.controller.openWorkspace(
            fixture.workspace,
            forceReset: false,
          )).storeCommitted,
          isTrue,
        );
        expect(fixture.controller.ready, isTrue);
        expect(
          (await fixture.controller.publish(originalCapture)).storeCommitted,
          isFalse,
        );
        final newCapture = fixture.controller.capture(
          _values(title: 'freshly hydrated'),
        )!;
        expect(
          (await fixture.controller.publish(newCapture)).storeCommitted,
          isTrue,
        );
        expect(fixture.document!.values['todo_top3_1'], 'freshly hydrated');
      },
    );
  }

  for (final cleanup in [false, true]) {
    for (final stage in ['inspection', 'mutation', 'confirmation']) {
      for (final change in [
        'revoke',
        'invalidHost',
        'accountGeneration',
        'presentationRoundTrip',
        'dispose',
      ]) {
        test(
          '${cleanup ? 'cleanup' : 'workspace'} $change during $stage rejects late recovery',
          () async {
            final fixture = _Peer();
            await fixture.quarantine();
            final arrived = Completer<void>();
            final response = Completer<Object?>();
            fixture.intercept = (call, value) {
              if (fixture.stage(call) != stage) return value;
              arrived.complete();
              return response.future;
            };
            final recovering = fixture.recover(cleanup: cleanup);
            await arrived.future;
            final value = fixture.lastResponse;
            switch (change) {
              case 'revoke':
                fixture.controller.revoke();
              case 'invalidHost':
                fixture.current = false;
              case 'accountGeneration':
                AccountLocalDataCleaner.invalidateInFlightAccountWrites();
              case 'presentationRoundTrip':
                fixture.controller.selectPresentation(_presentation(7));
                fixture.controller.selectPresentation(_presentation());
              case 'dispose':
                fixture.controller.dispose();
            }
            final calls = fixture.calls.length;
            response.complete(value);
            final result = await recovering;
            expect(result.status, 'supersededContext');
            expect(result.barrierConfirmed, isFalse);
            expect(result.storeCommitted, isFalse);
            expect(result.refreshRequested, isFalse);
            expect(fixture.controller.ready, isFalse);
            expect(fixture.controller.requiresDurabilityRecovery, isTrue);
            expect(
              fixture.calls.length,
              calls,
              reason: 'No dependent call after obsolete await',
            );
            expect(
              (await fixture.controller.publish(
                fixture.oldCapture!,
              )).storeCommitted,
              isFalse,
            );
            expect((await fixture.controller.retryPending()).status, 'blocked');
            expect(fixture.calls.length, calls);
          },
        );
      }
    }
  }

  for (final status in ['corrupt', 'unsupported', 'unavailable', 'busy']) {
    test(
      '$status inspection cannot create, clear quarantine or submit recovery',
      () async {
        final fixture = _Peer();
        await fixture.quarantine();
        fixture.intercept = (call, value) =>
            call.method == 'inspectWidgetStoreRecovery'
            ? {'status': status}
            : value;
        expect((await fixture.recover()).status, status);
        expect(
          fixture.calls.where((c) => c.method == 'recoverWidgetStore'),
          isEmpty,
        );
        expect(fixture.controller.requiresDurabilityRecovery, isTrue);
      },
    );
  }

  for (final stage in ['mutation', 'confirmation']) {
    for (final failure in ['unknown', 'malformed', 'platform']) {
      test(
        '$failure $stage stays quarantined and next attempt inspects with a new immutable identity',
        () async {
          final fixture = _Peer();
          await fixture.quarantine();
          fixture.intercept = (call, value) {
            if (fixture.stage(call) != stage) return value;
            if (failure == 'platform') throw PlatformException(code: 'lost');
            if (failure == 'unknown') return {'status': 'durabilityUnknown'};
            return {...value as Map, 'unexpected': true};
          };
          final first = await fixture.recover();
          expect(first.storeCommitted, isFalse);
          expect(first.barrierConfirmed, isFalse);
          expect(fixture.controller.requiresDurabilityRecovery, isTrue);
          final firstRequest = fixture.calls.singleWhere(
            (c) => c.method == 'recoverWidgetStore',
          );
          final firstArguments = Map.of(firstRequest.arguments as Map);
          expect((await fixture.controller.retryPending()).status, 'blocked');
          fixture.intercept = null;
          expect((await fixture.recover()).storeCommitted, isTrue);
          final requests = fixture.calls
              .where((c) => c.method == 'recoverWidgetStore')
              .toList();
          expect(requests, hasLength(2));
          expect(
            (requests.last.arguments as Map)['operationId'],
            isNot(firstArguments['operationId']),
          );
          expect(
            (requests.last.arguments as Map)['expectedStoreRevision'],
            (firstArguments['expectedStoreRevision'] as int) + 1,
          );
          expect(firstRequest.arguments, firstArguments);
          expect(
            fixture.calls.where(
              (c) => c.method == 'inspectWidgetStoreRecovery',
            ),
            hasLength(2),
          );
          expect(fixture.controller.ready, isFalse);
        },
      );
    }
  }

  for (final changed in ['receipt', 'binding', 'presentation', 'document']) {
    test('intervening $changed cannot satisfy recovery confirmation', () async {
      final fixture = _Peer();
      await fixture.quarantine();
      fixture.intercept = (call, value) {
        if (fixture.stage(call) != 'confirmation') return value;
        final read = {...value as Map};
        switch (changed) {
          case 'receipt':
            read['lastOperationId'] = 'another-engine';
          case 'binding':
            read['status'] = 'ready';
            read['leaseState'] = 'active';
            read['binding'] = {'kind': 'guest', 'key': 'other'};
          case 'presentation':
            read['desiredPresentation'] = {'revision': 8, 'locale': 'en'};
          case 'document':
            final document = {...read['document'] as Map};
            document['values'] = {
              ...document['values'] as Map,
              'widget_first_day_of_week': 7,
            };
            read['document'] = document;
        }
        return read;
      };
      expect((await fixture.recover()).status, 'confirmationUnavailable');
      expect(fixture.controller.requiresDurabilityRecovery, isTrue);
      expect(fixture.controller.ready, isFalse);
    });
  }

  for (final field in ['storeRevision', 'desiredPresentation']) {
    test('$field exhaustion cannot wrap or submit a recovery', () async {
      final fixture = _Peer();
      await fixture.quarantine();
      fixture.intercept = (call, value) {
        if (call.method != 'inspectWidgetStoreRecovery') return value;
        final facts = {...(value as Map)['facts'] as Map};
        facts[field] = field == 'storeRevision'
            ? WidgetPublication.maxExactJsonInteger
            : {
                'revision': WidgetPublication.maxExactJsonInteger,
                'locale': 'en',
              };
        return {'status': 'inspected', 'facts': facts};
      };
      expect((await fixture.recover()).status, 'revisionExhausted');
      expect(
        fixture.calls.where((c) => c.method == 'recoverWidgetStore'),
        isEmpty,
      );
      expect(fixture.controller.requiresDurabilityRecovery, isTrue);
    });
  }

  test('healthy controller rejects recovery without channel work', () async {
    final fixture = _Peer();
    final result = await fixture.recover();
    expect(result.status, 'blocked');
    expect(fixture.calls, isEmpty);
  });

  test(
    'obsolete cleanup and throwing cleanup predicates never inspect',
    () async {
      final fixture = _Peer();
      await fixture.quarantine();
      final before = fixture.calls.length;
      for (final cleanup in [
        ValidatedWidgetCleanup(accountGeneration: -1, isCurrent: () => true),
        ValidatedWidgetCleanup(
          accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
          isCurrent: () => throw StateError('revoked'),
        ),
      ]) {
        expect(
          (await fixture.controller.recoverCleanup(cleanup)).status,
          'supersededContext',
        );
        expect(fixture.calls.length, before);
        expect(fixture.controller.requiresDurabilityRecovery, isTrue);
      }
    },
  );
}

// Scripted transport controls facts/delivery, not native durability or FIFO.
// Native production integration is a separate acceptance scope.
class _Peer {
  _Peer() {
    const channel = MethodChannel('duoyi/seal-recovery-controller-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    controller = WidgetPublicationController(
      client: WidgetPublicationClient(channel: channel),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      lastResponse = respond(call);
      return intercept?.call(call, lastResponse) ?? lastResponse;
    });
    addTearDown(() {
      controller.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    workspace = ValidatedWidgetWorkspace(
      binding: WidgetWorkspaceBinding(kind: 'guest', key: 'validated-local'),
      accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
      isCurrent: () => current,
    );
    controller.selectPresentation(_presentation());
  }
  late final WidgetPublicationController controller;
  late final ValidatedWidgetWorkspace workspace;
  final calls = <MethodCall>[];
  FutureOr<Object?> Function(MethodCall, Object?)? intercept;
  Object? lastResponse;
  WidgetPublicationCapture? oldCapture;
  WidgetPublication? document;
  bool current = true, nativeUnknown = false, recovering = false;
  int revision = 0, desired = 0;
  String operation = '', epoch = 'epoch-1';
  Map? binding;

  String stage(MethodCall call) => switch (call.method) {
    'inspectWidgetStoreRecovery' => 'inspection',
    'recoverWidgetStore' => 'mutation',
    'readWidgetStore' when recovering => 'confirmation',
    _ => 'other',
  };

  Future<void> quarantine() async {
    expect(
      (await controller.openWorkspace(
        workspace,
        forceReset: false,
      )).storeCommitted,
      isTrue,
    );
    oldCapture = controller.capture(_values(title: 'old account capture'));
    nativeUnknown = true;
    expect((await controller.publish(oldCapture!)).status, 'durabilityUnknown');
    expect(controller.requiresDurabilityRecovery, isTrue);
  }

  Future<WidgetPublicationOutcome> recover({bool cleanup = false}) => cleanup
      ? controller.recoverCleanup(
          ValidatedWidgetCleanup(
            accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
            isCurrent: () => current,
          ),
        )
      : controller.recoverWorkspace(workspace);

  Object respond(MethodCall call) {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'inspectWidgetStoreRecovery':
        return {
          'status': 'inspected',
          'facts': {
            'storeRevision': revision,
            'ownerEpoch': epoch,
            'binding': binding,
            'desiredPresentation': {'revision': desired, 'locale': 'en'},
            'appliedPresentationRevision': document!.localeRevision,
            'lastOperationId': operation,
            'lastRequestDigest': List.filled(64, 'a').join(),
          },
        };
      case 'readWidgetStore':
        if (nativeUnknown) return {'status': 'durabilityUnknown'};
        if (document == null) return {'status': 'absent'};
        return {
          'status': binding == null ? 'sealed' : 'ready',
          'storeRevision': revision,
          'ownerEpoch': epoch,
          'binding': binding,
          'leaseState': binding == null ? 'sealed' : 'active',
          'desiredPresentation': {'revision': desired, 'locale': 'en'},
          'document': document!.toJson(),
          'lastOperationId': operation,
          'lastRequestDigest': List.filled(64, 'a').join(),
        };
      case 'publishWidgetPublication':
        if (nativeUnknown) {
          return {
            'status': 'durabilityUnknown',
            'operationId': args!['operationId'],
          };
        }
        revision++;
        operation = args!['operationId'] as String;
        document = WidgetPublication.tryFromJson(args['document'])!;
        return ack();
      case 'openWidgetWorkspace':
      case 'recoverWidgetStore':
        final recovery = call.method == 'recoverWidgetStore';
        if (recovery) {
          recovering = true;
          nativeUnknown = false;
        }
        revision++;
        operation = args!['operationId'] as String;
        if (recovery || args['mode'] != 'resume') epoch = 'epoch-$revision';
        binding = recovery ? null : args['binding'] as Map;
        final presentation = args['presentation'] as Map;
        desired = presentation['revision'] as int;
        document = WidgetPublication(
          ownerEpoch: epoch,
          publicationRevision: 0,
          localeRevision: desired,
          state: WidgetPublicationState.cleared,
          locale: AppLocale.en,
          snapshotDay: '',
          snapshotUtcOffsetMinutes: 0,
          capturedAtMillis: 0,
          values: Map<String, Object>.from(presentation['values'] as Map),
        );
        return ack(open: !recovery);
      default:
        throw StateError('Unexpected ${call.method}');
    }
  }

  Map<String, Object?> ack({bool open = false}) => {
    'status': 'applied',
    'operationId': operation,
    'committedStoreRevision': revision,
    'ownerEpoch': epoch,
    'publicationRevision': document!.publicationRevision,
    'desiredPresentationRevision': desired,
    'appliedPresentationRevision': document!.localeRevision,
    'documentState': document!.state.name,
    'refreshRequested': false,
    if (open) 'writerLeaseId': 'lease-$revision',
  };
}
