import 'dart:async';

import 'package:duoyi/services/android_widget_manager.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _widgetsChannel = MethodChannel('duoyi/widgets');
const _waitChannel = MethodChannel('duoyi/widget_pin_results');
final widgetCalls = <MethodCall>[];
final waitCalls = <MethodCall>[];
final callOrder = <String>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final receipts = <String, Map<String, Object?>>{};
  final waitTokens = <String, String>{};
  final clearFailures = <String>{};
  final endFailures = <String>{};
  final emptyTokenRequestIds = <String>{};
  String? beginFailureRequestId;
  String? mismatchedReceiptRequestId;
  Completer<void>? beginEntered;
  Completer<void>? beginRelease;
  Completer<String>? endEntered;
  Completer<void>? endRelease;
  Completer<String>? clearEntered;
  Completer<void>? clearRelease;
  Completer<String>? lastPinResultEntered;
  Completer<void>? lastPinResultRelease;

  void installHandlers() {
    messenger.setMockMethodCallHandler(_widgetsChannel, (call) async {
      widgetCalls.add(call);
      callOrder.add('widgets.${call.method}');
      final args =
          (call.arguments as Map?)?.cast<Object?, Object?>() ?? const {};
      switch (call.method) {
        case 'lastPinResult':
          final requestId = args['requestId'] as String? ?? '';
          lastPinResultEntered?.complete(requestId);
          if (lastPinResultRelease != null) {
            await lastPinResultRelease!.future;
          }
          final receipt = receipts[requestId];
          if (receipt == null) return null;
          if (requestId == mismatchedReceiptRequestId) {
            mismatchedReceiptRequestId = null;
            return <String, Object?>{...receipt, 'requestId': 'other-id'};
          }
          return receipt;
        case 'clearPinResult':
          final requestId = args['requestId'] as String? ?? '';
          clearEntered?.complete(requestId);
          if (clearRelease != null) await clearRelease!.future;
          if (clearFailures.contains(requestId)) {
            throw PlatformException(code: 'clear_failed', message: requestId);
          }
          receipts.remove(requestId);
          return null;
        case 'cancelPinRequest':
          return null;
        default:
          return null;
      }
    });

    messenger.setMockMethodCallHandler(_waitChannel, (call) async {
      waitCalls.add(call);
      callOrder.add('wait.${call.method}');
      final args =
          (call.arguments as Map?)?.cast<Object?, Object?>() ?? const {};
      final requestId = args['requestId'] as String? ?? '';
      switch (call.method) {
        case 'beginWait':
          beginEntered?.complete();
          if (beginRelease != null) await beginRelease!.future;
          if (requestId == beginFailureRequestId) {
            throw PlatformException(code: 'begin_failed', message: requestId);
          }
          if (emptyTokenRequestIds.contains(requestId)) return null;
          final token = 'token:$requestId';
          waitTokens[requestId] = token;
          return token;
        case 'endWait':
          endEntered?.complete(requestId);
          if (endRelease != null) await endRelease!.future;
          if (endFailures.contains(requestId)) {
            throw PlatformException(code: 'end_failed', message: requestId);
          }
          waitTokens.remove(requestId);
          return null;
        default:
          return null;
      }
    });
  }

  void resetFakes() {
    widgetCalls.clear();
    waitCalls.clear();
    callOrder.clear();
    receipts.clear();
    waitTokens.clear();
    clearFailures.clear();
    endFailures.clear();
    emptyTokenRequestIds.clear();
    beginFailureRequestId = null;
    mismatchedReceiptRequestId = null;
    beginEntered = null;
    beginRelease = null;
    endEntered = null;
    endRelease = null;
    clearEntered = null;
    clearRelease = null;
    lastPinResultEntered = null;
    lastPinResultRelease = null;
  }

  setUp(() {
    resetFakes();
    AndroidWidgetManager.debugIsAndroidOverride = true;
    installHandlers();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_widgetsChannel, null);
    messenger.setMockMethodCallHandler(_waitChannel, null);
    AndroidWidgetManager.debugIsAndroidOverride = null;
  });

  test(
    'matching confirmation awaits clear acknowledgement before return',
    () async {
      const requestId = 'pin-success';
      receipts[requestId] = _receipt(
        requestId,
        kind: 'todo',
        style: 'compact',
        widgetId: 101,
        status: 'confirmed',
      );
      clearEntered = Completer<String>();
      clearRelease = Completer<void>();
      endEntered = Completer<String>();
      endRelease = Completer<void>();
      var completed = false;

      final pending =
          AndroidWidgetManager.waitForPinResult(
            requestId,
            timeout: const Duration(seconds: 10),
            pollInterval: const Duration(seconds: 1),
          ).then((value) {
            completed = true;
            return value;
          });

      await clearEntered!.future;
      expect(completed, isFalse);
      expect(_waitMethods, ['beginWait']);
      expect(_widgetMethods, ['lastPinResult', 'clearPinResult']);
      expect(callOrder, [
        'wait.beginWait',
        'widgets.lastPinResult',
        'widgets.clearPinResult',
      ]);
      expect(waitCalls.first.arguments, {
        'requestId': requestId,
        'timeoutMillis': 10000,
      });

      clearRelease!.complete();
      expect(await endEntered!.future, requestId);
      expect(completed, isFalse);
      expect(waitTokens[requestId], 'token:$requestId');
      expect(callOrder.last, 'wait.endWait');
      endRelease!.complete();
      final result = await pending;

      expect(result.status, AndroidWidgetPinFinalStatus.success);
      expect(result.requestId, requestId);
      expect(result.kind, 'todo');
      expect(result.style, AndroidWidgetStyle.compact);
      expect(result.widgetId, 101);
      expect(_waitMethods, ['beginWait', 'endWait']);
      expect(waitCalls.last.arguments, {
        'requestId': requestId,
        'token': 'token:$requestId',
      });
      expect(callOrder.last, 'wait.endWait');
      expect(waitTokens, isEmpty);
      expect(receipts.containsKey(requestId), isFalse);
    },
  );

  test(
    'confirmed_unverified waits for clear acknowledgement before return',
    () async {
      const requestId = 'pin-unverified';
      receipts[requestId] = _receipt(
        requestId,
        kind: 'anniversary',
        style: 'standard',
        widgetId: 0,
        status: 'confirmed_unverified',
      );
      clearEntered = Completer<String>();
      clearRelease = Completer<void>();
      var completed = false;

      final pending =
          AndroidWidgetManager.waitForPinResult(
            requestId,
            timeout: const Duration(seconds: 3),
            pollInterval: const Duration(milliseconds: 10),
          ).then((value) {
            completed = true;
            return value;
          });

      expect(await clearEntered!.future, requestId);
      expect(completed, isFalse);
      expect(_waitMethods, ['beginWait']);
      clearRelease!.complete();

      final result = await pending;

      expect(result.status, AndroidWidgetPinFinalStatus.success);
      expect(result.widgetId, 0);
      expect(_widgetMethods, ['lastPinResult', 'clearPinResult']);
      expect(_waitMethods, ['beginWait', 'endWait']);
      expect(callOrder.last, 'wait.endWait');
      expect(receipts.containsKey(requestId), isFalse);
    },
  );

  test(
    'concurrent request ids retain independent receipt fields and wait tokens',
    () async {
      const requestA = 'pin-A';
      const requestB = 'pin-B';
      receipts[requestA] = _receipt(
        requestA,
        kind: 'todo',
        style: 'compact',
        widgetId: 111,
      );
      receipts[requestB] = _receipt(
        requestB,
        kind: 'habit',
        style: 'detailed',
        widgetId: 222,
      );

      final results = await Future.wait([
        AndroidWidgetManager.waitForPinResult(
          requestA,
          timeout: const Duration(seconds: 5),
          pollInterval: const Duration(milliseconds: 5),
        ),
        AndroidWidgetManager.waitForPinResult(
          requestB,
          timeout: const Duration(seconds: 5),
          pollInterval: const Duration(milliseconds: 5),
        ),
      ]);

      expect(results.map((result) => result.requestId), [requestA, requestB]);
      expect(results.map((result) => result.kind), ['todo', 'habit']);
      expect(results.map((result) => result.style), [
        AndroidWidgetStyle.compact,
        AndroidWidgetStyle.detailed,
      ]);
      expect(results.map((result) => result.widgetId), [111, 222]);
      expect(
        waitCalls.where((call) => call.method == 'beginWait').map(_requestId),
        containsAll([requestA, requestB]),
      );
      expect(
        waitCalls.where((call) => call.method == 'endWait').map(_requestId),
        containsAll([requestA, requestB]),
      );
      expect(
        widgetCalls
            .where((call) => call.method == 'clearPinResult')
            .map(_requestId),
        containsAll([requestA, requestB]),
      );
    },
  );

  test(
    'custom timeout is registered and zero or blank requests do no channel work',
    () async {
      const requestId = 'custom-timeout';
      receipts[requestId] = _receipt(
        requestId,
        kind: 'schedule',
        style: 'detailed',
        widgetId: 131,
      );
      final result = await AndroidWidgetManager.waitForPinResult(
        requestId,
        timeout: const Duration(milliseconds: 4321),
        pollInterval: const Duration(milliseconds: 3),
      );

      expect(result.isSuccess, isTrue);
      expect(waitCalls.first.method, 'beginWait');
      expect(waitCalls.first.arguments, {
        'requestId': requestId,
        'timeoutMillis': 4321,
      });

      resetFakes();
      final zero = await AndroidWidgetManager.waitForPinResult(
        'zero-timeout',
        timeout: Duration.zero,
        pollInterval: const Duration(milliseconds: 5),
      );
      final negative = await AndroidWidgetManager.waitForPinResult(
        'negative-timeout',
        timeout: const Duration(milliseconds: -1),
      );
      final blank = await AndroidWidgetManager.waitForPinResult(
        '   ',
        timeout: const Duration(seconds: 1),
      );

      expect(zero.status, AndroidWidgetPinFinalStatus.timeout);
      expect(negative.status, AndroidWidgetPinFinalStatus.timeout);
      expect(blank.status, AndroidWidgetPinFinalStatus.unavailable);
      expect(waitCalls, isEmpty);
      expect(widgetCalls, isEmpty);

      await expectLater(
        AndroidWidgetManager.waitForPinResult(
          'bad-poll-interval',
          timeout: const Duration(seconds: 1),
          pollInterval: Duration.zero,
        ),
        throwsArgumentError,
      );
      await expectLater(
        AndroidWidgetManager.waitForPinResult(
          'negative-poll-interval',
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(waitCalls, isEmpty);
      expect(widgetCalls, isEmpty);
    },
  );

  test('begin registration time counts toward the timeout', () {
    const requestId = 'slow-registration';
    const timeout = Duration(seconds: 2);
    AndroidWidgetPinConfirmation? result;

    fakeAsync((async) {
      beginEntered = Completer<void>();
      beginRelease = Completer<void>();
      unawaited(
        AndroidWidgetManager.waitForPinResult(
          requestId,
          timeout: timeout,
          pollInterval: const Duration(milliseconds: 250),
        ).then((value) => result = value),
      );
      async.flushMicrotasks();

      expect(beginEntered!.isCompleted, isTrue);
      expect(_waitMethods, ['beginWait']);
      async.elapse(timeout);
      beginRelease!.complete();
      async.flushMicrotasks();
    });

    expect(result?.status, AndroidWidgetPinFinalStatus.timeout);
    expect(_widgetMethods, isEmpty);
    expect(_waitMethods, ['beginWait', 'endWait']);
    expect(waitCalls.first.arguments, {
      'requestId': requestId,
      'timeoutMillis': timeout.inMilliseconds,
    });
    expect(waitCalls.last.arguments, {
      'requestId': requestId,
      'token': 'token:$requestId',
    });
    expect(waitTokens, isEmpty);
  });

  test('keeps the active token until an in-flight poll RPC completes', () {
    const requestId = 'slow-poll';
    const timeout = Duration(seconds: 2);
    AndroidWidgetPinConfirmation? result;

    fakeAsync((async) {
      lastPinResultEntered = Completer<String>();
      lastPinResultRelease = Completer<void>();
      unawaited(
        AndroidWidgetManager.waitForPinResult(
          requestId,
          timeout: timeout,
          pollInterval: const Duration(milliseconds: 250),
        ).then((value) => result = value),
      );
      async.flushMicrotasks();

      expect(lastPinResultEntered!.isCompleted, isTrue);
      expect(waitTokens[requestId], 'token:$requestId');
      async.elapse(timeout);
      async.flushMicrotasks();
      expect(result, isNull);
      expect(_waitMethods, ['beginWait']);

      lastPinResultRelease!.complete();
      async.flushMicrotasks();
    });

    expect(result?.status, AndroidWidgetPinFinalStatus.timeout);
    expect(_waitMethods, ['beginWait', 'endWait']);
    expect(_widgetMethods, ['lastPinResult']);
    expect(callOrder, [
      'wait.beginWait',
      'widgets.lastPinResult',
      'wait.endWait',
    ]);
    expect(waitTokens, isEmpty);
  });

  test('late matching receipts succeed after clear acknowledgement', () {
    for (final status in ['confirmed', 'confirmed_unverified']) {
      resetFakes();
      final requestId = 'late-$status';
      const timeout = Duration(seconds: 2);
      receipts[requestId] = _receipt(
        requestId,
        kind: 'todo',
        style: 'compact',
        widgetId: 191,
        status: status,
      );
      AndroidWidgetPinConfirmation? result;

      fakeAsync((async) {
        lastPinResultEntered = Completer<String>();
        lastPinResultRelease = Completer<void>();
        clearEntered = Completer<String>();
        clearRelease = Completer<void>();
        endEntered = Completer<String>();
        endRelease = Completer<void>();
        unawaited(
          AndroidWidgetManager.waitForPinResult(
            requestId,
            timeout: timeout,
            pollInterval: const Duration(milliseconds: 250),
          ).then((value) => result = value),
        );
        async.flushMicrotasks();

        expect(lastPinResultEntered!.isCompleted, isTrue);
        expect(waitTokens[requestId], 'token:$requestId');
        async.elapse(timeout + const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(result, isNull);
        expect(_waitMethods, ['beginWait']);

        lastPinResultRelease!.complete();
        async.flushMicrotasks();
        expect(clearEntered!.isCompleted, isTrue);
        expect(result, isNull);
        expect(waitTokens[requestId], 'token:$requestId');
        expect(_waitMethods, ['beginWait']);

        clearRelease!.complete();
        async.flushMicrotasks();
        expect(endEntered!.isCompleted, isTrue);
        expect(result, isNull);
        expect(waitTokens[requestId], 'token:$requestId');

        endRelease!.complete();
        async.flushMicrotasks();
      });

      expect(result?.status, AndroidWidgetPinFinalStatus.success);
      expect(result?.requestId, requestId);
      expect(result?.widgetId, 191);
      expect(_widgetMethods, ['lastPinResult', 'clearPinResult']);
      expect(_waitMethods, ['beginWait', 'endWait']);
      expect(waitTokens, isEmpty);
      expect(receipts.containsKey(requestId), isFalse);
      expect(callOrder, [
        'wait.beginWait',
        'widgets.lastPinResult',
        'widgets.clearPinResult',
        'wait.endWait',
      ]);
    }
  });

  test(
    'timeout ends retention without clearing or cancelling the pending pin',
    () {
      const requestId = 'pin-timeout';
      AndroidWidgetPinConfirmation? result;

      fakeAsync((async) {
        unawaited(
          AndroidWidgetManager.waitForPinResult(
            requestId,
            timeout: const Duration(seconds: 2),
            pollInterval: const Duration(milliseconds: 500),
          ).then((value) => result = value),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
      });

      expect(result?.status, AndroidWidgetPinFinalStatus.timeout);
      expect(result?.requestId, requestId);
      expect(waitCalls.first.method, 'beginWait');
      expect(waitCalls.last.method, 'endWait');
      expect(
        waitCalls.where((call) => call.method == 'beginWait'),
        hasLength(1),
      );
      expect(waitCalls.where((call) => call.method == 'endWait'), hasLength(1));
      expect(
        widgetCalls.where((call) => call.method == 'lastPinResult'),
        hasLength(4),
      );
      expect(
        widgetCalls.where((call) => call.method == 'clearPinResult'),
        isEmpty,
      );
      expect(
        widgetCalls.where((call) => call.method == 'cancelPinRequest'),
        isEmpty,
      );
    },
  );

  test('mismatched receipt is ignored until matching id arrives', () async {
    const requestId = 'pin-match-only';
    receipts[requestId] = _receipt(
      requestId,
      kind: 'goal',
      style: 'standard',
      widgetId: 141,
    );
    mismatchedReceiptRequestId = requestId;

    final result = await AndroidWidgetManager.waitForPinResult(
      requestId,
      timeout: const Duration(seconds: 5),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(result.requestId, requestId);
    expect(result.kind, 'goal');
    expect(
      widgetCalls.where((call) => call.method == 'lastPinResult'),
      hasLength(2),
    );
    expect(_widgetMethods, [
      'lastPinResult',
      'lastPinResult',
      'clearPinResult',
    ]);
  });

  test('begin clear and end failures stay scoped to their request', () async {
    const requestA = 'pin-begin-clear-error';
    const requestB = 'pin-clear-end-error';
    const requestC = 'pin-empty-token';
    beginFailureRequestId = requestA;
    emptyTokenRequestIds.add(requestC);
    clearFailures.add(requestB);
    endFailures.add(requestB);
    receipts[requestA] = _receipt(
      requestA,
      kind: 'todo',
      style: 'compact',
      widgetId: 151,
    );
    receipts[requestB] = _receipt(
      requestB,
      kind: 'habit',
      style: 'detailed',
      widgetId: 152,
    );
    receipts[requestC] = _receipt(
      requestC,
      kind: 'calendar',
      style: 'compact',
      widgetId: 153,
    );

    final results = await Future.wait([
      AndroidWidgetManager.waitForPinResult(
        requestA,
        timeout: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 2),
      ),
      AndroidWidgetManager.waitForPinResult(
        requestB,
        timeout: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 2),
      ),
      AndroidWidgetManager.waitForPinResult(
        requestC,
        timeout: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 2),
      ),
    ]);

    expect(results.map((result) => result.requestId), [
      requestA,
      requestB,
      requestC,
    ]);
    expect(results.map((result) => result.widgetId), [-1, 152, -1]);
    expect(results.map((result) => result.status), [
      AndroidWidgetPinFinalStatus.unavailable,
      AndroidWidgetPinFinalStatus.success,
      AndroidWidgetPinFinalStatus.unavailable,
    ]);
    expect(
      waitCalls.where((call) => call.method == 'endWait').map(_requestId),
      [requestB],
      reason: 'A and C failed to obtain a token; only B owns one to release.',
    );
    expect(
      widgetCalls
          .where((call) => call.method == 'lastPinResult')
          .map(_requestId),
      [requestB],
      reason:
          'An unprotected request must not poll and consume an unretained receipt.',
    );
    expect(
      widgetCalls
          .where((call) => call.method == 'clearPinResult')
          .map(_requestId),
      [requestB],
    );
    expect(waitTokens[requestA], isNull);
    expect(waitTokens[requestB], 'token:$requestB');
    expect(waitTokens[requestC], isNull);

    // Failed begin/clear leaves those per-request receipts untouched.
    expect(receipts.containsKey(requestA), isTrue);
    expect(receipts.containsKey(requestB), isTrue);
    expect(receipts.containsKey(requestC), isTrue);
  });

  test(
    'lastPinResult reads a receipt without beginning retention or clearing it',
    () async {
      const requestId = 'direct-read';
      final receipt = _receipt(
        requestId,
        kind: 'diary',
        style: 'detailed',
        widgetId: 161,
        status: 'confirmed_unverified',
      );
      receipts[requestId] = receipt;

      final result = await AndroidWidgetManager.lastPinResult(requestId);

      expect(result?.requestId, requestId);
      expect(result?.status, AndroidWidgetPinFinalStatus.success);
      expect(_widgetMethods, ['lastPinResult']);
      expect(waitCalls, isEmpty);
      expect(receipts[requestId], receipt);
    },
  );

  test('clearPinResult remains idempotent for UI callers', () async {
    const requestId = 'ui-cleared-receipt';
    receipts[requestId] = _receipt(
      requestId,
      kind: 'todo',
      style: 'standard',
      widgetId: 171,
    );

    await AndroidWidgetManager.clearPinResult(requestId);
    await AndroidWidgetManager.clearPinResult(requestId);

    expect(_widgetMethods, ['clearPinResult', 'clearPinResult']);
    expect(widgetCalls.map(_requestId), [requestId, requestId]);
    expect(receipts.containsKey(requestId), isFalse);
    expect(waitCalls, isEmpty);
  });
}

Map<String, Object?> _receipt(
  String requestId, {
  required String kind,
  required String style,
  required int widgetId,
  String status = 'confirmed',
}) => {
  'requestId': requestId,
  'kind': kind,
  'style': style,
  'widgetId': widgetId,
  'status': status,
  'confirmedAt': 1700000000000,
};

String _requestId(MethodCall call) =>
    ((call.arguments as Map?)?.cast<Object?, Object?>() ??
            const {})['requestId']
        as String;

List<String> get _widgetMethods =>
    widgetCalls.map((call) => call.method).toList();

List<String> get _waitMethods => waitCalls.map((call) => call.method).toList();
