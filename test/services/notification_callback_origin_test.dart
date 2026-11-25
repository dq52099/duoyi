import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:duoyi/services/notification_action_envelope.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _ownerKey = AccountLocalDataCleaner.accountDataOwnerKey;
const _owner = 'synthetic-callback-account-A';
const _otherOwner = 'synthetic-callback-account-B';
const _notificationId = 421;
const _todoId = 'synthetic-todo-A_42';
const _todoPayload = 'duoyi://todo/$_todoId?workspace=alpha';
const _completeAction = 'todo_complete_$_todoId';
const _quickActions = ['quick_todo', 'quick_todo_open', 'quick_focus'];

NotificationResponse _response(
  String? payload, {
  int id = _notificationId,
  String? actionId,
  String? input,
}) => NotificationResponse(
  id: id,
  payload: payload,
  actionId: actionId,
  input: input,
  notificationResponseType: actionId == null || actionId.isEmpty
      ? NotificationResponseType.selectedNotification
      : NotificationResponseType.selectedNotificationAction,
);

Future<String> _signed(
  String payload, {
  int id = _notificationId,
  Iterable<String> actions = const [],
}) async {
  final result = await NotificationActionEnvelope.signPayload(
    id,
    payload,
    actions: actions,
  );
  expect(result, isNotNull);
  return result!;
}

// Dispatch returns void. All non-held mock operations finish in microtasks;
// crossing one event turn observes both the verification and dispatch awaits.
Future<void> _settleDispatch() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final notifications = LocalNotifications.instance;
  late SharedPreferencesStorePlatform originalStore;
  late void Function(String)? originalOnTap;
  late _CallbackStore store;

  setUp(() async {
    await AccountPreferenceWrites.drain();
    originalStore = SharedPreferencesStorePlatform.instance;
    originalOnTap = notifications.onTap;
    notifications.onTap = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _CallbackStore(initial: {'flutter.$_ownerKey': _owner});
    SharedPreferencesStorePlatform.instance = store;
  });

  tearDown(() async {
    store.releaseRead();
    await _settleDispatch();
    await AccountPreferenceWrites.drain();
    notifications.onTap = originalOnTap;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesStorePlatform.instance = originalStore;
  });

  const forged = <({String name, String? payload, String actionId})>[
    (
      name: 'quick todo with remote input',
      payload: 'duoyi://action/quick_todo',
      actionId: 'quick_todo',
    ),
    (
      name: 'quick focus',
      payload: 'duoyi://action/quick_todo',
      actionId: 'quick_focus',
    ),
    (
      name: 'todo completion suffix',
      payload: _todoPayload,
      actionId: _completeAction,
    ),
    (
      name: 'habit check-in',
      payload: 'duoyi://habit/synthetic-habit',
      actionId: 'habit_checkin',
    ),
    (
      name: 'todo completion suffix without a payload',
      payload: null,
      actionId: _completeAction,
    ),
  ];
  for (final item in forged) {
    test('unsigned ${item.name} reaches neither live handler', () async {
      final taps = <String>[];
      final fallbacks = <String>[];
      notifications.onTap = taps.add;
      final response = _response(
        item.payload,
        actionId: item.actionId,
        input: 'forged draft',
      );

      expect(
        await notifications.payloadForNotificationResponse(response),
        isNull,
      );
      notifications.dispatchNotificationResponse(
        response,
        fallback: fallbacks.add,
      );
      await _settleDispatch();

      expect(taps, isEmpty);
      expect(fallbacks, isEmpty);
      expect(store.capabilityWrites, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NotificationActionEnvelope.key), isNull);
    });
  }

  test('unsigned action links cannot bypass verification as body taps', () async {
    for (final payload in [
      'duoyi://action/quick_todo?text=forged',
      'duoyi://action/start_pomodoro',
      'duoyi://action/complete_todo?id=$_todoId',
      'duoyi://action/checkin_habit?id=synthetic-habit',
    ]) {
      expect(
        await notifications.payloadForNotificationResponse(_response(payload)),
        isNull,
        reason: payload,
      );
    }
    expect(store.capabilityWrites, 0);
  });

  for (final action in ['quick_todo', 'quick_todo_open']) {
    test('signed $action maps remote input to the quick-todo URI', () async {
      const input = '  Literal 用户 🗓️\nwith % & ? / =  ';
      final signed = await _signed(
        'duoyi://action/quick_todo',
        id: LocalNotifications.quickAddNotificationId,
        actions: _quickActions,
      );
      final mapped = await notifications.payloadForNotificationResponse(
        _response(
          signed,
          id: LocalNotifications.quickAddNotificationId,
          actionId: action,
          input: input,
        ),
      );

      expect(
        mapped,
        'duoyi://action/quick_todo?text=${Uri.encodeComponent(input.trim())}',
      );
      expect(Uri.parse(mapped!).queryParameters['text'], input.trim());
    });
  }

  for (final input in <String?>[null, '', ' \n\t ']) {
    final label = input == null ? 'missing' : input.isEmpty ? 'empty' : 'whitespace';
    test('signed quick todo with $label input opens the editor', () async {
      final signed = await _signed(
        'duoyi://action/quick_todo',
        id: LocalNotifications.quickAddNotificationId,
        actions: _quickActions,
      );
      expect(
        await notifications.payloadForNotificationResponse(
          _response(
            signed,
            id: LocalNotifications.quickAddNotificationId,
            actionId: 'quick_todo',
            input: input,
          ),
        ),
        'duoyi://action/quick_todo',
      );
    });
  }

  test('signed ongoing focus action maps to start pomodoro', () async {
    final signed = await _signed(
      'duoyi://action/quick_todo',
      id: LocalNotifications.quickAddNotificationId,
      actions: _quickActions,
    );
    expect(
      await notifications.payloadForNotificationResponse(
        _response(
          signed,
          id: LocalNotifications.quickAddNotificationId,
          actionId: 'quick_focus',
          input: 'input does not become a focus target',
        ),
      ),
      'duoyi://action/start_pomodoro',
    );
  });

  test('signed local completion suffix maps only the issued todo target', () async {
    final signed = await _signed(_todoPayload, actions: [_completeAction]);
    expect(
      await notifications.payloadForNotificationResponse(
        _response(signed, actionId: _completeAction),
      ),
      'duoyi://action/complete_todo?id=$_todoId',
    );
    expect(
      await notifications.payloadForNotificationResponse(
        _response(signed, actionId: 'todo_complete_different-target'),
      ),
      isNull,
    );
  });

  test('signed completion rejects another notification id', () async {
    final signed = await _signed(_todoPayload, actions: [_completeAction]);
    expect(
      await notifications.payloadForNotificationResponse(
        _response(signed, id: _notificationId + 1, actionId: _completeAction),
      ),
      isNull,
    );
  });

  for (final item in [
    (host: 'todo', action: 'todo_complete', target: 'complete_todo'),
    (host: 'habit', action: 'habit_checkin', target: 'checkin_habit'),
  ]) {
    test('signed ${item.action} extracts the original object id', () async {
      const objectId = 'literal 用户 &/?';
      final payload = 'duoyi://${item.host}/${Uri.encodeComponent(objectId)}'
          '?workspace=alpha';
      final signed = await _signed(payload, actions: [item.action]);
      final mapped = await notifications.payloadForNotificationResponse(
        _response(signed, actionId: item.action),
      );
      expect(
        mapped,
        'duoyi://action/${item.target}?id=${Uri.encodeComponent(objectId)}',
      );
      expect(Uri.parse(mapped!).queryParameters['id'], objectId);
    });
  }

  test('signed snooze suffix carries the original payload and notification id', () async {
    const original = '$_todoPayload&label=literal%20%26%20draft#details';
    const action = 'todo_snooze_$_todoId';
    final signed = await _signed(original, actions: [action]);
    final mapped = await notifications.payloadForNotificationResponse(
      _response(signed, actionId: action),
    );
    expect(
      mapped,
      'duoyi://snooze/$_notificationId?delay=5&payload=${Uri.encodeComponent(original)}',
    );
    expect(Uri.parse(mapped!).queryParameters['payload'], original);
  });

  test('signed body tap restores the original URI', () async {
    const original = '$_todoPayload&label=literal%20%26%20draft#details';
    final signed = await _signed(original);
    expect(
      await notifications.payloadForNotificationResponse(_response(signed)),
      original,
    );
  });

  test('live signed callback dispatches asynchronously once to onTap', () async {
    final signed = await _signed(_todoPayload, actions: [_completeAction]);
    final delivered = Completer<String>();
    final taps = <String>[];
    final fallbacks = <String>[];
    notifications.onTap = (payload) {
      taps.add(payload);
      delivered.complete(payload);
    };

    notifications.dispatchNotificationResponse(
      _response(signed, actionId: _completeAction),
      fallback: fallbacks.add,
    );
    expect(taps, isEmpty, reason: 'Verification must finish before dispatch.');
    expect(await delivered.future, 'duoyi://action/complete_todo?id=$_todoId');
    await _settleDispatch();
    expect(taps, ['duoyi://action/complete_todo?id=$_todoId']);
    expect(fallbacks, isEmpty);
  });

  test('live signed callback uses fallback when onTap is absent', () async {
    final signed = await _signed(
      'duoyi://action/quick_todo',
      actions: _quickActions,
    );
    final delivered = Completer<String>();
    final fallbacks = <String>[];
    notifications.dispatchNotificationResponse(
      _response(signed, actionId: 'quick_focus'),
      fallback: (payload) {
        fallbacks.add(payload);
        delivered.complete(payload);
      },
    );
    expect(fallbacks, isEmpty);
    expect(await delivered.future, 'duoyi://action/start_pomodoro');
    await _settleDispatch();
    expect(fallbacks, ['duoyi://action/start_pomodoro']);
  });

  test('unsigned live callback cannot reach fallback without onTap', () async {
    final fallbacks = <String>[];
    notifications.dispatchNotificationResponse(
      _response('duoyi://action/quick_todo', actionId: 'quick_focus'),
      fallback: fallbacks.add,
    );
    await _settleDispatch();
    expect(fallbacks, isEmpty);
    expect(store.capabilityWrites, 0);
  });

  test('account invalidation drops a live callback awaiting verification', () async {
    final signed = await _signed(_todoPayload, actions: [_completeAction]);
    final persisted = await store.getAll();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _CallbackStore(initial: persisted)..holdNextRead = true;
    SharedPreferencesStorePlatform.instance = store;
    final oldTaps = <String>[];
    final newTaps = <String>[];
    final fallbacks = <String>[];
    final freshDelivered = Completer<String>();
    notifications.onTap = oldTaps.add;

    notifications.dispatchNotificationResponse(
      _response(signed, actionId: _completeAction),
      fallback: fallbacks.add,
    );
    await store.readStarted.future;
    expect(oldTaps, isEmpty);
    // Keep the signing key and owner unchanged until verification resumes.
    // Generation invalidation alone must prevent this already-started action.
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    notifications.onTap = (payload) {
      newTaps.add(payload);
      freshDelivered.complete(payload);
    };
    store.releaseRead();
    await _settleDispatch();

    expect(oldTaps, isEmpty);
    expect(newTaps, isEmpty);
    expect(fallbacks, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, _otherOwner);
    final fresh = await _signed(_todoPayload, actions: [_completeAction]);
    notifications.dispatchNotificationResponse(
      _response(fresh, actionId: _completeAction),
      fallback: fallbacks.add,
    );
    expect(await freshDelivered.future, 'duoyi://action/complete_todo?id=$_todoId');
    await _settleDispatch();
    expect(newTaps, ['duoyi://action/complete_todo?id=$_todoId']);
    expect(oldTaps, isEmpty);
    expect(fallbacks, isEmpty);
  });
}

class _CallbackStore extends InMemorySharedPreferencesStore {
  _CallbackStore({Map<String, Object> initial = const {}})
    : super.withData(initial);

  int capabilityWrites = 0;
  bool holdNextRead = false;
  final readStarted = Completer<void>();
  final _readRelease = Completer<void>();

  void releaseRead() {
    if (!_readRelease.isCompleted) _readRelease.complete();
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (holdNextRead) {
      holdNextRead = false;
      readStarted.complete();
      await _readRelease.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.${NotificationActionEnvelope.key}') {
      capabilityWrites++;
    }
    return super.setValue(type, key, value);
  }
}
