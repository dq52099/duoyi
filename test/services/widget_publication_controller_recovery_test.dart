import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> _values([int first = 1]) => {
  for (final key in WidgetPublication.valueKeys)
    key: HomeWidgetService.accountPayloadDefaults[key]!,
  'widget_first_day_of_week': first,
};
WidgetDevicePresentation _presentation([int first = 1]) =>
    WidgetDevicePresentation(
      locale: AppLocale.zh,
      completeValues: _values(first),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a late mutation reply cannot recover capability after its deadline',
    () async {
      final fixture = _Fixture();
      await fixture.bootstrap();
      final response = Completer<Object?>();
      final arrived = Completer<void>();
      fixture.step('publishWidgetPublication', (call) {
        fixture.commitPublish(call);
        arrived.complete();
        return response.future;
      });
      final publication = fixture.controller.publish(
        fixture.controller.capture(_values())!,
      );
      await arrived.future;
      final outcome = await publication;
      expect(outcome.status, 'responseUnknown');
      fixture.expectBlocked(pending: true);
      final callCount = fixture.calls.length;
      response.complete(fixture.ack());
      await Future<void>.delayed(Duration.zero);
      fixture.expectBlocked(pending: true);
      expect(fixture.calls, hasLength(callCount));
    },
  );

  for (final failure in ['platform', 'invalidAck']) {
    test(
      'exact retry keeps the full original request after $failure',
      () async {
        final fixture = _Fixture();
        await fixture.bootstrap();
        MethodCall? original;
        fixture.step('publishWidgetPublication', (call) {
          original = call;
          fixture.commitPublish(call);
          if (failure == 'platform') {
            throw PlatformException(code: 'messengerLost');
          }
          return {...fixture.ack(), 'operationId': 'different-operation'};
        });
        final outcome = await fixture.controller.publish(
          fixture.controller.capture(_values())!,
        );
        expect(
          outcome.status,
          failure == 'platform' ? 'responseUnknown' : 'invalidResponse',
        );
        fixture.expectBlocked(pending: true);
        final revision = fixture.revision;
        fixture.step('publishWidgetPublication', (call) {
          expect(call.arguments, original!.arguments);
          return fixture.ack(status: 'alreadyApplied');
        });
        fixture.readStep();
        final retried = await fixture.controller.retryPending();
        expect(retried.status, 'alreadyApplied');
        expect(retried.storeCommitted, isTrue);
        expect(fixture.controller.ready, isTrue);
        expect(fixture.controller.hasPendingOperation, isFalse);
        expect(fixture.revision, revision);
        expect(fixture.steps, isEmpty);
      },
    );
  }

  test(
    'read-fence recovery discards pending capability until a fresh open confirms',
    () async {
      final fixture = _Fixture();
      await fixture.bootstrap();
      fixture.step('publishWidgetPublication', (call) {
        fixture.commitPublish(call);
        throw PlatformException(code: 'messengerLost');
      });
      await fixture.controller.publish(fixture.controller.capture(_values())!);
      fixture.expectBlocked(pending: true);
      fixture.readStep();
      final openArrived = Completer<void>();
      final response = Completer<Object?>();
      fixture.step('openWidgetWorkspace', (call) {
        final args = call.arguments as Map;
        expect(args['mode'], 'resume');
        expect(args['expectedStoreRevision'], fixture.revision);
        expect(args['expectedOwnerEpoch'], 'fixture-owner');
        fixture.commitOpen(call);
        openArrived.complete();
        return response.future;
      });
      fixture.readStep();
      final recovered = fixture.controller.openWorkspace(
        fixture.workspace,
        forceReset: false,
      );
      await openArrived.future;
      fixture.expectBlocked(pending: true);
      response.complete(fixture.ack(open: true));
      expect((await recovered).storeCommitted, isTrue);
      expect(fixture.controller.ready, isTrue);
      expect(
        fixture.calls.where(
          (call) => call.method == 'publishWidgetPublication',
        ),
        hasLength(1),
      );
    },
  );

  for (final failure in ['unavailable', 'interveningOperation']) {
    test(
      'valid ack with $failure confirmation does not restore capability',
      () async {
        final fixture = _Fixture();
        await fixture.bootstrap();
        fixture.step('publishWidgetPublication', (call) {
          fixture.commitPublish(call);
          return fixture.ack();
        });
        fixture.step(
          'readWidgetStore',
          (_) => failure == 'unavailable'
              ? {'status': 'unavailable'}
              : {
                  ...fixture.snapshot(),
                  'storeRevision': fixture.revision + 1,
                  'lastOperationId': 'other-engine',
                },
        );
        final result = await fixture.controller.publish(
          fixture.controller.capture(_values())!,
        );
        expect(result.status, 'confirmationUnavailable');
        expect(result.storeCommitted, isFalse);
        fixture.expectBlocked(pending: true);
      },
    );
  }

  for (final stage in ['ack', 'confirmation']) {
    for (final change in [
      'revoke',
      'workspaceInvalid',
      'presentationRoundTrip',
    ]) {
      test(
        '$change while awaiting $stage cannot revive an old capture',
        () async {
          final fixture = _Fixture();
          await fixture.bootstrap();
          final response = Completer<Object?>();
          final arrived = Completer<void>();
          fixture.step('publishWidgetPublication', (call) {
            fixture.commitPublish(call);
            if (stage == 'ack') {
              arrived.complete();
              return response.future;
            }
            return fixture.ack();
          });
          fixture.step('readWidgetStore', (_) {
            if (stage == 'confirmation') {
              arrived.complete();
              return response.future;
            }
            return fixture.snapshot();
          });
          final capture = fixture.controller.capture(_values())!;
          final publishing = fixture.controller.publish(capture);
          await arrived.future;
          switch (change) {
            case 'revoke':
              fixture.controller.revoke();
            case 'workspaceInvalid':
              fixture.current = false;
            case 'presentationRoundTrip':
              fixture.controller.selectPresentation(_presentation(7));
              fixture.controller.selectPresentation(_presentation());
          }
          response.complete(
            stage == 'ack' ? fixture.ack() : fixture.snapshot(),
          );
          final result = await publishing;
          expect(result.status, 'supersededContext');
          fixture.expectBlocked(pending: false);
          final calls = fixture.calls.length;
          expect(
            (await fixture.controller.publish(capture)).storeCommitted,
            isFalse,
          );
          expect((await fixture.controller.retryPending()).status, 'blocked');
          if (change == 'revoke') {
            expect(
              (await fixture.controller.openWorkspace(
                fixture.workspace,
                forceReset: false,
              )).status,
              'barrierRequired',
            );
          }
          expect(fixture.calls, hasLength(calls));
        },
      );
    }
  }

  for (final foreign in [false, true]) {
    test(
      'failed ${foreign ? 'foreign owner handoff' : 'forced reset'} keeps clear barrier latched',
      () async {
        final fixture = _Fixture();
        await fixture.bootstrap();
        fixture.readStep();
        fixture.step(
          'invalidateWidgetWorkspace',
          (call) => {
            'status': 'busy',
            'operationId': (call.arguments as Map)['operationId'],
          },
        );
        final workspace = foreign
            ? fixture.newWorkspace('other-owner')
            : fixture.workspace;
        final result = await fixture.controller.openWorkspace(
          workspace,
          forceReset: !foreign,
        );
        expect(result.status, 'busy');
        fixture.expectBlocked(pending: false);
        final calls = fixture.calls.length;
        expect(
          (await fixture.controller.openWorkspace(
            workspace,
            forceReset: false,
          )).status,
          'barrierRequired',
        );
        expect(fixture.calls, hasLength(calls));
      },
    );
  }
}

// A scripted channel peer, not an implementation of native CAS, receipt replay,
// FIFO scheduling or SQLite. Tests control operation facts and response delivery
// separately and assert only the real Dart adapter/controller's public behavior.
class _Fixture {
  _Fixture() {
    const channel = MethodChannel('duoyi/publication-recovery-test');
    controller = WidgetPublicationController(
      client: WidgetPublicationClient(
        channel: channel,
        responseTimeout: const Duration(milliseconds: 100),
      ),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(steps, isNotEmpty, reason: 'unexpected ${call.method}');
      final next = steps.removeAt(0);
      expect(call.method, next.$1);
      return next.$2(call);
    });
    addTearDown(() {
      controller.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    workspace = newWorkspace('local-device');
    controller.selectPresentation(_presentation());
  }
  late final WidgetPublicationController controller;
  late final ValidatedWidgetWorkspace workspace;
  final steps = <(String, FutureOr<Object?> Function(MethodCall))>[];
  final calls = <MethodCall>[];
  bool current = true;
  int revision = 0;
  int desired = 0;
  String operation = '';
  String lease = 'fixture-lease-0';
  Map? binding;
  WidgetPublication? document;

  ValidatedWidgetWorkspace newWorkspace(String key) => ValidatedWidgetWorkspace(
    binding: WidgetWorkspaceBinding(kind: 'guest', key: key),
    accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
    isCurrent: () => current,
  );
  void step(String method, FutureOr<Object?> Function(MethodCall) handler) =>
      steps.add((method, handler));
  void readStep() => step('readWidgetStore', (_) => snapshot());
  Future<void> bootstrap() async {
    step('readWidgetStore', (_) => {'status': 'absent'});
    step('openWidgetWorkspace', (call) {
      commitOpen(call);
      return ack(open: true);
    });
    readStep();
    expect(
      (await controller.openWorkspace(
        workspace,
        forceReset: false,
      )).storeCommitted,
      isTrue,
    );
    expect(controller.ready, isTrue);
  }

  void commitOpen(MethodCall call) {
    final args = call.arguments as Map;
    revision++;
    operation = args['operationId'] as String;
    lease = 'fixture-lease-$revision';
    binding = args['binding'] as Map;
    final p = args['presentation'] as Map;
    desired = p['revision'] as int;
    if (args['mode'] != 'resume') {
      document = WidgetPublication(
        ownerEpoch: 'fixture-owner',
        publicationRevision: 0,
        localeRevision: desired,
        state: WidgetPublicationState.cleared,
        locale: AppLocale.zh,
        snapshotDay: '',
        snapshotUtcOffsetMinutes: 0,
        capturedAtMillis: 0,
        values: Map<String, Object>.from(p['values'] as Map),
      );
    }
  }

  void commitPublish(MethodCall call) {
    final args = call.arguments as Map;
    revision++;
    operation = args['operationId'] as String;
    document = WidgetPublication.tryFromJson(args['document'])!;
  }

  Map<String, Object?> ack({String status = 'applied', bool open = false}) => {
    'status': status,
    'operationId': operation,
    'committedStoreRevision': revision,
    'ownerEpoch': 'fixture-owner',
    'publicationRevision': document!.publicationRevision,
    'desiredPresentationRevision': desired,
    'appliedPresentationRevision': document!.localeRevision,
    'documentState': document!.state.name,
    'refreshRequested': false,
    if (open) 'writerLeaseId': lease,
  };
  Map<String, Object?> snapshot() => {
    'status': 'ready',
    'storeRevision': revision,
    'binding': binding,
    'ownerEpoch': 'fixture-owner',
    'leaseState': 'active',
    'desiredPresentation': {'revision': desired, 'locale': 'zh'},
    'document': document!.toJson(),
    'lastOperationId': operation,
    'lastRequestDigest': List.filled(64, 'a').join(),
  };
  void expectBlocked({required bool pending}) {
    expect(controller.ready, isFalse);
    expect(controller.hasPendingOperation, pending);
    expect(controller.capture(_values()), isNull);
  }
}
