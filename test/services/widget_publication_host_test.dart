import 'dart:async';

import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:duoyi/services/widget_publication_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _values(String title) => {
  for (final key in WidgetPublication.valueKeys)
    key: HomeWidgetService.accountPayloadDefaults[key]!,
  'todo_count': title.isEmpty ? 0 : 1,
  'todo_top3_count': title.isEmpty ? 0 : 1,
  'todo_top3_1': title,
  'todo_top3_1_id': title.isEmpty ? '' : 'synthetic-item',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const homeChannel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final homeCalls = <MethodCall>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.en);
    messenger.setMockMethodCallHandler(homeChannel, (call) async {
      homeCalls.add(call);
      return call.method == 'getWidgetData' ? null : true;
    });
    HomeWidgetService.supportedForTesting = true;
    HomeWidgetService.nativePublicationForTesting = true;
    HomeWidgetService.publicationWriter = null;
    HomeWidgetService.resetAccountCache();
    await HomeWidgetService.waitForAccountClear();
    homeCalls.clear();
  });
  tearDown(() async {
    await HomeWidgetService.waitForAccountClear();
    HomeWidgetService.publicationWriter = null;
    HomeWidgetService.nativePublicationForTesting = null;
    HomeWidgetService.supportedForTesting = null;
    messenger.setMockMethodCallHandler(homeChannel, null);
    I18n.setLocale(AppLocale.zh);
  });

  test('healthy host publishes and refreshes once', () async {
    final f = _Fixture();
    expect(await f.publish(_values('synthetic initial')), isTrue);
    expect(f.peer.document!.values['todo_top3_1'], 'synthetic initial');
    expect(f.refreshes, 1);
    expect(f.freshRequests, 0);
  });

  for (final change in ['session', 'accountGeneration']) {
    test('$change while awaiting refresh rejects late host success', () async {
      final f = _Fixture();
      final started = Completer<void>(), reply = Completer<bool>();
      f.refresh = () {
        started.complete();
        return reply.future;
      };
      final publishing = f.publish(_values('before refresh'));
      await started.future;
      if (change == 'session') {
        f.session++;
      } else {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      }
      reply.complete(true);
      expect(await publishing, isFalse);
      expect(f.freshRequests, 0);
    });
  }

  test(
    'payload cannot change while workspace open is awaiting acknowledgement',
    () async {
      final f = _Fixture();
      final started = Completer<void>(), release = Completer<void>();
      f.peer.intercept = (call, result) async {
        if (call.method == 'openWidgetWorkspace') {
          started.complete();
          await release.future;
        }
        return result;
      };
      final values = _values('captured before await');
      final publishing = f.publish(values);
      await started.future;
      values['todo_top3_1'] = 'mutated during await';
      release.complete();
      expect(await publishing, isTrue);
      expect(f.peer.document!.values['todo_top3_1'], 'captured before await');
    },
  );

  test(
    'real payload FIFO discards recovery input, then opens and captures fresh provider values without deadlock',
    () async {
      final f = _Fixture();
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      var providerTitle = 'initial provider';
      Future<bool> push({bool force = false}) => HomeWidgetService.push(
        todoCount: 1,
        habitPercent: 0,
        pomodoroToday: 0,
        focusMinutesToday: 0,
        strings: BrandStrings.defaultBrand,
        todoTop3: [providerTitle],
        todoTop3Ids: ['synthetic-item'],
        theme: HomeWidgetThemePayload.fromThemeProvider(theme),
        force: force,
      );
      final freshDone = Completer<bool>();
      f.requestFresh = () async {
        final result = await push(force: true);
        freshDone.complete(result);
        return result;
      };
      f.refresh = HomeWidgetService.refreshPublishedWidgets;
      HomeWidgetService.publicationWriter = (values, at) =>
          f.publish(values, capturedAt: at);
      expect(await push(), isTrue);
      f.peer.unknown = true;
      expect(await push(force: true), isFalse);
      providerTitle = 'obsolete pre-recovery payload';
      f.peer.intercept = (call, result) {
        if (call.method == 'recoverWidgetStore') {
          providerTitle = 'new provider value after seal';
        }
        return result;
      };
      expect(await push(force: true), isFalse);
      expect(await freshDone.future, isTrue);
      expect(f.freshRequests, 1);
      expect(f.peer.publishedTitles, [
        '· initial provider',
        '· new provider value after seal',
      ]);
      expect(
        f.peer.document!.values['todo_top3_1'],
        '· new provider value after seal',
      );
      final methods = f.peer.calls.map((c) => c.method).toList();
      final recovered = methods.indexOf('recoverWidgetStore');
      expect(
        methods.sublist(recovered + 1),
        containsAllInOrder([
          'readWidgetStore',
          'openWidgetWorkspace',
          'publishWidgetPublication',
        ]),
      );
      final publications = f.peer.publishedTitles.length;
      expect(await push(), isTrue);
      expect(
        f.peer.publishedTitles,
        hasLength(publications),
        reason: 'only accepted fresh push installs the signature',
      );
      expect(homeCalls.any((c) => c.method == 'updateWidget'), isTrue);
      expect(homeCalls.where((c) => c.method == 'saveWidgetData'), isEmpty);
    },
  );

  test(
    'revoked follow-up intent cannot schedule a new capture or refresh',
    () async {
      final f = _Fixture();
      await f.publish(_values('initial'));
      f.peer.unknown = true;
      await f.publish(_values('uncertain'));
      f.invalidate = () => f.session++;
      final refreshes = f.refreshes;
      expect(await f.publish(_values('must discard')), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(f.freshRequests, 0);
      expect(f.refreshes, refreshes);
      expect(f.controller.ready, isFalse);
    },
  );

  test(
    'failed asynchronous fresh pass is observed without publishing old values',
    () async {
      final f = _Fixture();
      await f.publish(_values('initial'));
      f.peer.unknown = true;
      await f.publish(_values('uncertain'));
      f.requestFresh = () =>
          Future<bool>.error(StateError('synthetic recapture failure'));
      expect(await f.publish(_values('must discard')), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(f.messages, contains(contains('post-recovery push failed')));
      expect(f.peer.publishedTitles, ['initial']);
    },
  );

  test('synchronous fresh-pass failure is observed after the seal', () async {
    final f = _Fixture();
    await f.publish(_values('initial'));
    f.peer.unknown = true;
    await f.publish(_values('uncertain'));
    f.requestFresh = () => throw StateError('synchronous recapture failure');
    expect(await f.publish(_values('must discard')), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(f.messages, contains(contains('post-recovery push failed')));
    expect(f.peer.publishedTitles, ['initial']);
  });

  test(
    'real push cannot cache a late refresh success from a previous session',
    () async {
      final f = _Fixture();
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final arrived = Completer<void>(), reply = Completer<bool>();
      f.refresh = () {
        arrived.complete();
        return reply.future;
      };
      HomeWidgetService.publicationWriter = (values, at) =>
          f.publish(values, capturedAt: at);
      final pushing = HomeWidgetService.push(
        todoCount: 1,
        habitPercent: 0,
        pomodoroToday: 0,
        focusMinutesToday: 0,
        strings: BrandStrings.defaultBrand,
        todoTop3: ['old session'],
        todoTop3Ids: ['synthetic-item'],
        theme: HomeWidgetThemePayload.fromThemeProvider(theme),
      );
      await arrived.future;
      f.session++;
      reply.complete(true);
      expect(await pushing, isFalse);
      expect(f.freshRequests, 0);
    },
  );

  test('absent cleanup barrier requires no native initialization', () async {
    final f = _Fixture();
    expect((await f.clear()).barrierConfirmed, isTrue);
    expect(f.cacheClears, 1);
    expect(f.peer.calls.map((c) => c.method), ['readWidgetStore']);
  });

  test('unknown cleanup seals and confirms before legacy cache work', () async {
    final f = _Fixture();
    await f.publish(_values('initial'));
    f.peer.unknown = true;
    expect((await f.clear()).barrierConfirmed, isTrue);
    expect(f.cacheClears, 1);
    expect(f.peer.document!.state, WidgetPublicationState.cleared);
    expect(f.controller.ready, isFalse);
    final methods = f.peer.calls.map((c) => c.method).toList();
    expect(
      methods,
      containsAllInOrder([
        'inspectWidgetStoreRecovery',
        'recoverWidgetStore',
        'readWidgetStore',
      ]),
    );
  });

  for (final stage in ['inspection', 'recovery', 'confirmation', 'cache']) {
    for (final change in [
      'session',
      'cleanupGeneration',
      'accountGeneration',
    ]) {
      test('$change during $stage cannot authorize model cleanup', () async {
        final f = _Fixture();
        await f.publish(_values('initial'));
        f.peer.unknown = true;
        final arrived = Completer<void>(), release = Completer<void>();
        f.peer.intercept = (call, result) async {
          if (f.peer.stage(call) == stage) {
            arrived.complete();
            await release.future;
          }
          return result;
        };
        if (stage == 'cache') {
          f.clearCache = () async {
            arrived.complete();
            await release.future;
            return true;
          };
        }
        final clearing = f.clear();
        await arrived.future;
        switch (change) {
          case 'session':
            f.session++;
          case 'cleanupGeneration':
            f.cleanupGeneration++;
          case 'accountGeneration':
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        }
        final calls = f.peer.calls.length;
        release.complete();
        final result = await clearing;
        expect(result.barrierConfirmed, isFalse);
        expect(result.status, 'supersededContext');
        expect(f.cacheClears, stage == 'cache' ? 1 : 0);
        expect(f.peer.calls, hasLength(calls));
      });
    }
  }

  for (final stage in ['inspectWidgetStoreRecovery', 'recoverWidgetStore']) {
    for (final status in [
      'busy',
      'corrupt',
      'unavailable',
      'durabilityUnknown',
    ]) {
      test('$status at $stage prohibits account cache/model cleanup', () async {
        final f = _Fixture();
        await f.publish(_values('initial'));
        f.peer.unknown = true;
        f.peer.intercept = (call, result) =>
            call.method == stage ? {'status': status} : result;
        final result = await f.clear();
        expect(result.barrierConfirmed, isFalse);
        expect(f.cacheClears, 0);
        expect(f.controller.ready, isFalse);
      });
    }
  }

  test('failed legacy cache work is not a completed cleanup barrier', () async {
    final f = _Fixture();
    f.clearCache = () async => false;
    expect((await f.clear()).barrierConfirmed, isFalse);
    expect(f.cacheClears, 1);
  });
}

class _Fixture {
  _Fixture() {
    peer = _Peer();
    controller = WidgetPublicationController(
      client: WidgetPublicationClient(channel: peer.channel),
    );
    host = WidgetPublicationHost(
      controller: controller,
      onStatus: messages.add,
    );
    addTearDown(controller.dispose);
  }
  late final _Peer peer;
  late final WidgetPublicationController controller;
  late final WidgetPublicationHost host;
  final messages = <String>[];
  int session = 0,
      cleanupGeneration = 0,
      refreshes = 0,
      freshRequests = 0,
      cacheClears = 0;
  Future<bool> Function()? refresh, requestFresh, clearCache;
  void Function()? invalidate;

  Future<bool> publish(Map<String, Object> values, {DateTime? capturedAt}) {
    final capturedSession = session;
    final workspace = ValidatedWidgetWorkspace(
      binding: WidgetWorkspaceBinding(kind: 'guest', key: 'synthetic-local'),
      accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
      isCurrent: () => session == capturedSession,
    );
    return host.publish(
      workspace: workspace,
      presentation: WidgetDevicePresentation(
        locale: AppLocale.en,
        completeValues: {
          for (final key in WidgetPublication.valueKeys) key: values[key]!,
        },
      ),
      completeValues: values,
      capturedAt: capturedAt ?? DateTime.now(),
      refreshWidgets: () {
        refreshes++;
        return refresh?.call() ?? Future.value(true);
      },
      requestFreshCapture: () {
        freshRequests++;
        return requestFresh?.call() ?? Future.value(true);
      },
      invalidatePushSignature: () {
        HomeWidgetService.invalidatePushSignature();
        invalidate?.call();
      },
    );
  }

  Future<WidgetPublicationOutcome> clear() {
    final capturedSession = session, generation = ++cleanupGeneration;
    return host.clearForCleanup(
      cleanup: ValidatedWidgetCleanup(
        accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
        isCurrent: () =>
            session == capturedSession && cleanupGeneration == generation,
      ),
      presentation: WidgetDevicePresentation(
        locale: AppLocale.en,
        completeValues: _values(''),
      ),
      clearCachedWidgetData: () {
        cacheClears++;
        return clearCache?.call() ?? Future.value(true);
      },
    );
  }
}

// Scripted native facts and delivery, not a replacement for native CAS/SQLite.
class _Peer {
  _Peer() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final result = respond(call);
      return intercept == null ? result : intercept!(call, result);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
  final channel = const MethodChannel('duoyi/widget-publication-host-test');
  final calls = <MethodCall>[];
  final publishedTitles = <String>[];
  FutureOr<Object?> Function(MethodCall, Object)? intercept;
  WidgetPublication? document;
  Map? binding;
  int revision = 0, desired = 0;
  String epoch = '', operation = '';
  bool unknown = false, recovering = false;

  String stage(MethodCall call) => switch (call.method) {
    'inspectWidgetStoreRecovery' => 'inspection',
    'recoverWidgetStore' => 'recovery',
    'readWidgetStore' when recovering => 'confirmation',
    _ => 'other',
  };

  Object respond(MethodCall call) {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'readWidgetStore':
        if (unknown) return {'status': 'durabilityUnknown'};
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
      case 'publishWidgetPublication':
        if (unknown) return {'status': 'durabilityUnknown'};
        revision++;
        operation = args!['operationId'];
        document = WidgetPublication.tryFromJson(args['document'])!;
        publishedTitles.add(document!.values['todo_top3_1'] as String);
        return ack();
      case 'openWidgetWorkspace':
      case 'invalidateWidgetWorkspace':
      case 'recoverWidgetStore':
        final open = call.method == 'openWidgetWorkspace';
        if (call.method == 'recoverWidgetStore') {
          unknown = false;
          recovering = true;
        }
        revision++;
        operation = args!['operationId'];
        epoch = 'epoch-$revision';
        binding = open ? args['binding'] as Map : null;
        final p = args['presentation'] as Map;
        desired = p['revision'];
        document = WidgetPublication(
          ownerEpoch: epoch,
          publicationRevision: 0,
          localeRevision: desired,
          state: WidgetPublicationState.cleared,
          locale: AppLocale.en,
          snapshotDay: '',
          snapshotUtcOffsetMinutes: 0,
          capturedAtMillis: 0,
          values: Map<String, Object>.from(p['values'] as Map),
        );
        return ack(open: open);
      default:
        throw StateError('Unexpected native call ${call.method}');
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
