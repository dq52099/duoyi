// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/notification_action_envelope.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _ownerKey = AccountLocalDataCleaner.accountDataOwnerKey;
const _owner = 'synthetic-account-A';
const _capabilityField = 'duoyi_notification_capability';
const _notificationId = 421;
const _todoPayload = 'duoyi://todo/synthetic-target?workspace=alpha';
const _complete = 'todo_complete_synthetic-target';
const _snooze = 'todo_snooze_synthetic-target';

NotificationResponse _response(
  String? payload, {
  int? id = _notificationId,
  String? actionId,
  String? input,
  NotificationResponseType? type,
}) => NotificationResponse(
  id: id,
  payload: payload,
  actionId: actionId,
  input: input,
  notificationResponseType:
      type ??
      (actionId == null || actionId.isEmpty
          ? NotificationResponseType.selectedNotification
          : NotificationResponseType.selectedNotificationAction),
);

Future<String> _signTodo({Iterable<String> actions = const []}) async {
  final signed = await NotificationActionEnvelope.signPayload(
    _notificationId,
    _todoPayload,
    actions: actions,
  );
  expect(signed, isNotNull);
  return signed!;
}

String _withQuery(String payload, String key, String value) {
  final uri = Uri.parse(payload);
  return uri.replace(queryParameters: {...uri.queryParameters, key: value})
      .toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform originalStore;
  late _EnvelopeStore store;

  setUp(() async {
    await AccountPreferenceWrites.drain();
    originalStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _EnvelopeStore(initial: {'flutter.$_ownerKey': _owner});
    SharedPreferencesStorePlatform.instance = store;
  });

  tearDown(() async {
    store.releaseHeldWrite();
    await AccountPreferenceWrites.drain();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesStorePlatform.instance = originalStore;
  });

  test('old scheduling origin cannot mint a capability for the new account', () async {
    final originalGeneration = AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, 'synthetic-account-B');
    await expectLater(
      Future<String?>.sync(() => NotificationActionEnvelope.signPayload(
        _notificationId,
        _todoPayload,
        actions: [_complete],
        expectedAccountGeneration: originalGeneration,
      )),
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    expect(store.keyWriteAttempts, 0);
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
  });

  test('current scheduling origin can sign after an account change', () async {
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, 'synthetic-account-B');
    final payload = await NotificationActionEnvelope.signPayload(
      _notificationId,
      _todoPayload,
      actions: [_complete],
      expectedAccountGeneration: AccountLocalDataCleaner.accountDataGeneration,
    );
    final response = await NotificationActionEnvelope.verifyResponse(
      _response(payload, actionId: _complete),
    );
    expect(response?.payload, _todoPayload);
    expect(store.keyWriteAttempts, 1);
  });

  test('signed body tap restores the exact original payload and response', () async {
    const original =
        'duoyi://todo/literal%20%E7%94%A8%E6%88%B7'
        '?workspace=alpha&text=literal%20%26%20draft#details';
    final signed = await NotificationActionEnvelope.signPayload(
      _notificationId,
      original,
      actions: [_complete],
    );
    expect(signed, isNotNull);
    expect(signed, isNot(original));

    final verified = await NotificationActionEnvelope.verifyResponse(
      _response(signed),
    );

    expect(verified, isNotNull);
    expect(verified!.payload, original);
    expect(verified.id, _notificationId);
    expect(verified.actionId, isNull);
    expect(verified.input, isNull);
    expect(
      verified.notificationResponseType,
      NotificationResponseType.selectedNotification,
    );
    expect(store.keyWriteAttempts, 1);
  });

  for (final action in [_complete, _snooze, 'todo_complete']) {
    test('signed todo action $action keeps the original target', () async {
      final signed = await _signTodo(actions: [action]);

      final verified = await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: action),
      );

      expect(verified, isNotNull);
      expect(verified!.payload, _todoPayload);
      expect(verified.id, _notificationId);
      expect(verified.actionId, action);
      expect(
        verified.notificationResponseType,
        NotificationResponseType.selectedNotificationAction,
      );
    });
  }

  for (final action in ['quick_todo', 'quick_todo_open', 'quick_focus']) {
    test('ongoing quick action $action preserves literal input', () async {
      const original = 'duoyi://action/quick_todo';
      const input = 'Literal 用户草稿 🗓️\nwith % & ?';
      final signed = await NotificationActionEnvelope.signPayload(
        _notificationId,
        original,
        actions: ['quick_todo', 'quick_todo_open', 'quick_focus'],
      );

      final verified = await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: action, input: input),
      );

      expect(verified, isNotNull);
      expect(verified!.payload, original);
      expect(verified.actionId, action);
      expect(verified.input, input);
      expect(verified.id, _notificationId);
      expect(
        verified.notificationResponseType,
        NotificationResponseType.selectedNotificationAction,
      );
    });
  }

  test('empty body action remains a valid body tap', () async {
    final signed = await _signTodo();
    final verified = await NotificationActionEnvelope.verifyResponse(
      _response(signed, actionId: ''),
    );
    expect(verified, isNotNull);
    expect(verified!.payload, _todoPayload);
    expect(verified.actionId, '');
  });

  test('unsigned bodies and forged todo/quick actions never create a key', () async {
    for (final response in [
      _response(_todoPayload),
      _response(_todoPayload, actionId: _complete),
      _response(null, actionId: 'todo_complete_arbitrary-target'),
      _response('duoyi://action/quick_todo', actionId: 'quick_todo', input: 'draft'),
    ]) {
      expect(
        await NotificationActionEnvelope.verifyResponse(response),
        isNull,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
    expect(store.keyWriteAttempts, 0);
    expect(
      (await store.getAll())['flutter.${NotificationActionEnvelope.key}'],
      isNull,
    );
  });

  test('signing null or empty payload does not allocate a capability key', () async {
    expect(
      await NotificationActionEnvelope.signPayload(_notificationId, null),
      isNull,
    );
    expect(
      await NotificationActionEnvelope.signPayload(_notificationId, ''),
      '',
    );
    expect(store.keyWriteAttempts, 0);
    expect(
      (await SharedPreferences.getInstance()).getString(
        NotificationActionEnvelope.key,
      ),
      isNull,
    );
  });

  test('a capability cannot be moved to another notification id', () async {
    final signed = await _signTodo(actions: [_complete]);
    for (final id in <int?>[_notificationId + 1, null]) {
      expect(
        await NotificationActionEnvelope.verifyResponse(
          _response(signed, id: id, actionId: _complete),
        ),
        isNull,
      );
    }
  });

  test('modified target, workspace, or fragment rejects the signed payload', () async {
    final signed = await _signTodo(actions: [_complete]);
    final uri = Uri.parse(signed);
    for (final modified in [
      uri.replace(path: '/different-target').toString(),
      _withQuery(signed, 'workspace', 'different-workspace'),
      uri.replace(fragment: 'different-fragment').toString(),
    ]) {
      expect(
        await NotificationActionEnvelope.verifyResponse(
          _response(modified, actionId: _complete),
        ),
        isNull,
      );
    }
    expect(
      (await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: _complete),
      ))?.payload,
      _todoPayload,
    );
  });

  test('action allowlist rejects another suffix and unissued quick actions', () async {
    final signed = await _signTodo(actions: [_complete]);
    for (final action in [
      'todo_complete_different-target',
      'todo_snooze_synthetic-target',
      'todo_complete',
      'quick_todo',
      'quick_focus',
    ]) {
      expect(
        await NotificationActionEnvelope.verifyResponse(
          _response(signed, actionId: action, input: 'untrusted input'),
        ),
        isNull,
      );
    }
  });

  test('a body-only capability does not authorize an action callback', () async {
    final signed = await _signTodo();
    expect(
      await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: _complete),
      ),
      isNull,
    );
  });

  test('modified and malformed capabilities reject without signing writes', () async {
    final signed = await _signTodo(actions: [_complete]);
    final capability = Uri.parse(signed).queryParameters[_capabilityField]!;
    final parts = capability.split('.');
    final changedSignature =
        '${parts[1].startsWith('0') ? '1' : '0'}${parts[1].substring(1)}';
    final changedBody =
        '${parts[0].startsWith('A') ? 'B' : 'A'}${parts[0].substring(1)}';
    final writesBefore = store.keyWriteAttempts;
    for (final replacement in [
      '${parts[0]}.$changedSignature',
      '$changedBody.${parts[1]}',
      '${parts[0]}.${parts[1]}0',
      'not-an-envelope',
      '%%%.not-a-signature',
      '',
    ]) {
      expect(
        await NotificationActionEnvelope.verifyResponse(
          _response(
            _withQuery(signed, _capabilityField, replacement),
            actionId: _complete,
          ),
        ),
        isNull,
      );
    }
    expect(store.keyWriteAttempts, writesBefore);
  });

  test('changing account owner rejects a previously valid capability', () async {
    final signed = await _signTodo(actions: [_complete]);
    final prefs = await SharedPreferences.getInstance();
    final writesBefore = store.keyWriteAttempts;
    await prefs.setString(_ownerKey, 'synthetic-account-B');
    expect(
      await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: _complete),
      ),
      isNull,
    );
    await prefs.remove(_ownerKey);
    expect(
      await NotificationActionEnvelope.verifyResponse(_response(signed)),
      isNull,
    );
    expect(store.keyWriteAttempts, writesBefore);
  });

  test('guest capability remains guest-bound after an account appears', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ownerKey);
    final signed = await _signTodo();
    expect(
      (await NotificationActionEnvelope.verifyResponse(_response(signed)))?.payload,
      _todoPayload,
    );
    await prefs.setString(_ownerKey, _owner);
    expect(
      await NotificationActionEnvelope.verifyResponse(_response(signed)),
      isNull,
    );
  });

  test('verification with a removed key never creates a replacement', () async {
    final signed = await _signTodo(actions: [_complete]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(NotificationActionEnvelope.key);
    final writesBefore = store.keyWriteAttempts;

    expect(
      await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: _complete),
      ),
      isNull,
    );
    expect(store.keyWriteAttempts, writesBefore);
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
  });

  test('account cleanup removes the key and revokes even the same owner', () async {
    final oldSigned = await _signTodo(actions: [_complete]);
    final prefs = await SharedPreferences.getInstance();
    final oldKey = prefs.getString(NotificationActionEnvelope.key);
    await AccountLocalDataCleaner.clearSharedPreferences();
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
    expect(prefs.getString(_ownerKey), isNull);
    final writesAfterCleanup = store.keyWriteAttempts;
    expect(
      await NotificationActionEnvelope.verifyResponse(
        _response(oldSigned, actionId: _complete),
      ),
      isNull,
    );
    expect(store.keyWriteAttempts, writesAfterCleanup);

    await prefs.setString(_ownerKey, _owner);
    final newSigned = await _signTodo(actions: [_complete]);
    expect(prefs.getString(NotificationActionEnvelope.key), isNot(oldKey));
    expect(
      await NotificationActionEnvelope.verifyResponse(_response(oldSigned)),
      isNull,
    );
    expect(
      (await NotificationActionEnvelope.verifyResponse(_response(newSigned)))?.payload,
      _todoPayload,
    );
  });

  test('invalidation across the verification await rejects an in-flight response', () async {
    final signed = await _signTodo();
    final pending = NotificationActionEnvelope.verifyResponse(_response(signed));
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    expect(await pending, isNull);
    expect(store.keyWriteAttempts, 1);
  });

  test('an active cleanup boundary neither verifies nor signs capabilities', () async {
    final signed = await _signTodo();
    final writesBefore = store.keyWriteAttempts;
    await AccountPreferenceWrites.boundary(() async {
      expect(
        await NotificationActionEnvelope.verifyResponse(_response(signed)),
        isNull,
      );
      await expectLater(
        () => NotificationActionEnvelope.signPayload(
          _notificationId,
          _todoPayload,
        ),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
    });
    expect(store.keyWriteAttempts, writesBefore);
  });

  test('false key persistence restores cache and permits one fresh signing attempt', () async {
    store.rejectKeyOnce = true;
    await expectLater(
      NotificationActionEnvelope.signPayload(
        _notificationId,
        _todoPayload,
        actions: [_complete],
      ),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
    expect(
      (await store.getAll())['flutter.${NotificationActionEnvelope.key}'],
      isNull,
    );
    expect(store.keyWriteAttempts, 1);

    final signed = await _signTodo(actions: [_complete]);
    expect(store.keyWriteAttempts, 2);
    expect(
      (await NotificationActionEnvelope.verifyResponse(
        _response(signed, actionId: _complete),
      ))?.payload,
      _todoPayload,
    );
    expect(store.keyWriteAttempts, 2);
  });

  test('throwing key persistence cannot leave an authenticating cache key', () async {
    store.throwKeyOnce = true;
    await expectLater(
      NotificationActionEnvelope.signPayload(_notificationId, _todoPayload),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
    expect(
      (await store.getAll())['flutter.${NotificationActionEnvelope.key}'],
      isNull,
    );
  });

  test('concurrent signers share one acknowledged key and keep distinct ids', () async {
    store.holdKeyWrite = true;
    final first = _signTodo();
    await store.writeStarted.future.timeout(const Duration(seconds: 5));
    final second = NotificationActionEnvelope.signPayload(
      _notificationId + 1,
      'duoyi://habit/synthetic-habit',
      actions: ['habit_checkin'],
    );
    expect(store.keyWriteAttempts, 1);
    store.releaseHeldWrite();
    final firstSigned = await first;
    final secondSigned = await second;
    expect(store.keyWriteAttempts, 1);
    expect(
      (await NotificationActionEnvelope.verifyResponse(_response(firstSigned)))?.payload,
      _todoPayload,
    );
    expect(
      (await NotificationActionEnvelope.verifyResponse(
        _response(secondSigned, id: _notificationId + 1, actionId: 'habit_checkin'),
      ))?.payload,
      'duoyi://habit/synthetic-habit',
    );
  });

  test('cleanup drains a delayed key write and cancels queued old signers', () async {
    store.holdKeyWrite = true;
    final first = NotificationActionEnvelope.signPayload(_notificationId, _todoPayload);
    final firstRejected = expectLater(
      first,
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    await store.writeStarted.future.timeout(const Duration(seconds: 5));
    final queued = NotificationActionEnvelope.signPayload(
      _notificationId + 1,
      _todoPayload,
    );
    final queuedRejected = expectLater(
      queued,
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    var cleaned = false;
    final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((_) {
      cleaned = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cleaned, isFalse);
    expect(store.keyWriteAttempts, 1);
    store.releaseHeldWrite();
    await Future.wait([firstRejected, queuedRejected, cleanup]);

    final prefs = await SharedPreferences.getInstance();
    expect(cleaned, isTrue);
    expect(prefs.getString(NotificationActionEnvelope.key), isNull);
    expect(prefs.getString(_ownerKey), isNull);
    expect(store.keyWriteAttempts, 1);
    expect(
      (await store.getAll())['flutter.${NotificationActionEnvelope.key}'],
      isNull,
    );
  });
}

class _EnvelopeStore extends InMemorySharedPreferencesStore {
  _EnvelopeStore({Map<String, Object> initial = const {}})
    : super.withData(initial);

  bool rejectKeyOnce = false;
  bool throwKeyOnce = false;
  bool holdKeyWrite = false;
  int keyWriteAttempts = 0;
  final writeStarted = Completer<void>();
  final _writeRelease = Completer<void>();

  void releaseHeldWrite() {
    if (!_writeRelease.isCompleted) _writeRelease.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${NotificationActionEnvelope.key}') {
      keyWriteAttempts++;
      if (holdKeyWrite && !_writeRelease.isCompleted) {
        if (!writeStarted.isCompleted) writeStarted.complete();
        await _writeRelease.future;
      }
      if (rejectKeyOnce) {
        rejectKeyOnce = false;
        return false;
      }
      if (throwKeyOnce) {
        throwKeyOnce = false;
        throw StateError('Synthetic capability-key persistence failure');
      }
    }
    return super.setValue(type, key, value);
  }
}
