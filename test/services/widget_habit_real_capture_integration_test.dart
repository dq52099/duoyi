// NEW2774, UNEXECUTED. Requires main's owner-implemented WidgetActionTestAccess.
// Real private handler/full capture; harness listener/native peer; no OS credit.
// Four controls: confirmed, confirmationUnavailable, responseUnknown/lost_reply,
// rejected preferences ACK. Durability quarantine/recovery remains out of scope.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/main.dart' show WidgetActionTestAccess, mainShellKey;
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_push_queue.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_launch_access.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:duoyi/services/widget_publication_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _waitBound2774 = Duration(seconds: 10);
Future<T> _bounded2774<T>(Future<T> pending, String stage) => pending.timeout(
  _waitBound2774,
  onTimeout: () => throw TimeoutException('NEW2774: $stage', _waitBound2774),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final outcome in [
    'confirmed', 'confirmationMismatch', 'responseUnknown', 'storageRejected',
  ]) {
    testWidgets('Habit real handler and full capture joined $outcome',
        (tester) async {
      // The actual action handler stays unchanged. No mounted main shell means
      // its extra dashboard-refresh branch cannot compete with the queue test.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(mainShellKey.currentContext, isNull);
      await tester.runAsync(() => _runCase2774(outcome));
      // Collect queued feedback callbacks against the intentionally absent shell.
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _runCase2774(String outcome) async {
  const rawId = ' habit /?#&=é ';
  const otherId = 'habit /?#&=é';
  const authoredName = '  喝水 / & é  ';
  const homeChannel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final oldLocale = I18n.current;
  final oldStore = SharedPreferencesStorePlatform.instance;
  final oldWriter = HomeWidgetService.publicationWriter;
  final oldSupported = HomeWidgetService.supportedForTesting;
  final oldNative = HomeWidgetService.nativePublicationForTesting;
  SharedPreferences.setMockInitialValues({});
  final store = _HabitStore2774();
  SharedPreferencesStorePlatform.instance = store;
  I18n.setLocale(AppLocale.en);
  final providers = _Providers2774();
  final habits = providers.habits;
  final peer = _PublicationPeer2774();
  final controller = WidgetPublicationController(
    client: WidgetPublicationClient(channel: peer.channel),
  );
  final trace = peer.trace;
  final hostStatuses = <String>[];
  final host = WidgetPublicationHost(
    controller: controller,
    onStatus: hostStatuses.add,
  );
  final homeCalls = <MethodCall>[];
  final captures = <Future<bool>>[];
  final pendingActions = <Future<void>>[];
  Future<void>? draining;
  var accepted = false;
  var notices = 0;
  final capturedTimes = <DateTime>[];
  Future<bool> capture({bool force = false}) {
    final pending = providers.capture(force: force);
    captures.add(pending);
    return pending;
  }
  final queue = HomeWidgetPushQueue(
    canPublish: () => true,
    readSignature: () => jsonEncode(
      habits.habits.map((habit) => habit.toJson()).toList(),
    ),
    publish: () async {
      accepted = await capture();
      return accepted;
    },
  );
  void onChange() {
    notices++;
    trace.add('provider:notify');
    HomeWidgetService.invalidatePushSignature();
    queue.queue();
  }
  var listening = false;
  try {
    messenger.setMockMethodCallHandler(homeChannel, (call) async {
      homeCalls.add(call);
      trace.add('home:${call.method}');
      return call.method == 'getWidgetData' ? null : true;
    });
    HomeWidgetService.supportedForTesting = true;
    HomeWidgetService.nativePublicationForTesting = true;
    HomeWidgetService.publicationWriter = null;
    HomeWidgetService.resetAccountCache();
    await _bounded2774(HomeWidgetService.waitForAccountClear(), 'initial clear');
    HomeWidgetService.publicationWriter = (values, capturedAt) {
      capturedTimes.add(capturedAt);
      return host.publish(
        workspace: ValidatedWidgetWorkspace(
          binding: WidgetWorkspaceBinding(kind: 'guest', key: 'local-device'),
          accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
          isCurrent: () => true,
        ),
        // Match main's canonical presentation boundary; legacy metadata
        // remains in the real payload supplied to the host below.
        presentation: WidgetDevicePresentation(
          locale: I18n.current,
          completeValues: <String, Object>{
            for (final key in WidgetPublication.valueKeys) key: values[key]!,
          },
        ),
        completeValues: values,
        capturedAt: capturedAt,
        refreshWidgets: HomeWidgetService.refreshPublishedWidgets,
        requestFreshCapture: () => capture(force: true),
        invalidatePushSignature: HomeWidgetService.invalidatePushSignature,
      );
    };
    await _bounded2774(habits.addHabit(Habit(
      id: rawId, name: authoredName, targetCount: 1, sortOrder: 0,
    )), 'first real habit creation');
    await _bounded2774(habits.addHabit(Habit(
      id: otherId, name: 'Distinct exact-ID record', targetCount: 1,
      sortOrder: 1,
    )), 'second real habit creation');
    expect(await _bounded2774(capture(force: true), 'baseline capture'), isTrue);
    expect(peer.document!.values['habit_percent'], 0);
    expect(peer.document!.values['habit_active_count'], 2);
    expect(peer.document!.values['habit_quick_check_id'], rawId);
    expect(peer.document!.values['habit_quick_check_label'], contains(authoredName));
    final baselineDocument = peer.document!.toJson();
    final prefs = await SharedPreferences.getInstance();
    final diskBefore = (await store.getAll())['flutter.habits'];
    expect(diskBefore, isA<String>());
    final sentinelBefore = habits.habits.last.toJson();
    peer.outcome = outcome;
    peer.hold = outcome == 'confirmed';
    store.hold = true;
    store.reject = outcome == 'storageRejected';
    habits.addListener(onChange);
    listening = true;
    trace.clear();
    homeCalls.clear();
    final baselinePublications = peer.publications;
    final requests = WidgetNavigationRequests(accountGeneration: () =>
        AccountLocalDataCleaner.accountDataGeneration);
    var receiptAcknowledgements = 0;
    final uri = Uri(
      scheme: 'duoyi', host: 'action', path: '/checkin_habit',
      queryParameters: {'id': rawId, 'widget_delivery': 'integrated-2774'},
    );
    final access = WidgetLaunchAccess(
      uri: uri,
      request: requests.capture(),
      isBlocked: () => false,
      requeue: (_, _) => fail('Unexpected requeue'),
      acknowledge: (_) async { receiptAcknowledgements++; },
    );
    final action = access.run(() => WidgetActionTestAccess.checkInHabit(
      habits, habits.habits.first, access,
    ));
    pendingActions.add(action);
    access.finishDispatch();
    await _bounded2774(store.started.future, 'held preferences write entered');
    expect(habits.habits.first.todayCount(), 0);
    // SharedPreferences' optimistic cache is not a platform-ACK oracle.
    expect((await store.getAll())['flutter.habits'], diskBefore);
    expect(notices, 0);
    expect(peer.publications, baselinePublications);
    expect(peer.document!.toJson(), baselineDocument);
    expect(homeCalls.where((c) => c.method == 'updateWidget'), isEmpty);
    store.release.complete();
    await _bounded2774(action, 'real check-in handler completion');
    expect(receiptAcknowledgements, 1,
        reason: 'access consumption is separate from publication storage ACK');
    if (outcome == 'storageRejected') {
      expect(habits.habits.first.todayCount(), 0);
      expect((await store.getAll())['flutter.habits'], diskBefore);
      expect(prefs.getString('habits'), diskBefore);
      draining = queue.flush();
      await _bounded2774(draining, 'rejected-write empty queue');
      expect(notices, 0);
      expect(peer.publications, baselinePublications);
      expect(peer.document!.toJson(), baselineDocument);
      expect(homeCalls.where((c) => c.method == 'updateWidget'), isEmpty);
      expect(homeCalls.where((c) => c.method == 'saveWidgetData'), isEmpty);
      return;
    }
    final durableJson = jsonDecode(
      (await store.getAll())['flutter.habits'] as String,
    ) as List;
    expect(durableJson, habits.habits.map((habit) => habit.toJson()).toList());
    expect(jsonDecode(prefs.getString('habits')!), durableJson);
    final saved = durableJson
        .map((raw) => Habit.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
    expect(saved.first.id, rawId);
    expect(saved.first.name, authoredName);
    expect(saved.first.todayCount(), 1);
    expect(saved.last.id, otherId);
    expect(saved.last.todayCount(), 0);
    expect(saved.last.toJson(), sentinelBefore);
    expect(habits.habits.first.todayCount(), 1);
    expect(notices, 1);
    final captureStart = DateTime.now();
    draining = queue.flush();
    if (outcome == 'confirmed') {
      await _bounded2774(peer.ackStarted.future, 'publication ACK gate');
      expect(homeCalls.where((c) => c.method == 'updateWidget'), isEmpty);
      peer.ackRelease.complete();
      await _bounded2774(peer.readStarted.future, 'ordered fresh-read gate');
      expect(homeCalls.where((c) => c.method == 'updateWidget'), isEmpty,
          reason: 'committed ACK alone cannot request refresh');
      peer.readRelease.complete();
    }
    await _bounded2774(draining, 'publication queue terminal');
    final captureEnd = DateTime.now();
    final document = peer.document!;
    expect(document.values.keys.toSet(), WidgetPublication.valueKeys.toSet());
    expect(document.values['habit_percent'], 50);
    expect(document.values['habit_active_count'], 2);
    expect(document.values['habit_quick_check_id'], otherId);
    expect(document.values['habit_quick_check_label'],
        contains('Distinct exact-ID record'));
    expect(document.capturedAtMillis, capturedTimes.last.millisecondsSinceEpoch);
    expect(document.capturedAtMillis, inInclusiveRange(
      captureStart.millisecondsSinceEpoch, captureEnd.millisecondsSinceEpoch,
    ));
    expect(document.snapshotUtcOffsetMinutes, capturedTimes.last.timeZoneOffset.inMinutes);
    final capturedDay = capturedTimes.last;
    expect(document.snapshotDay,
        '${capturedDay.year.toString().padLeft(4, '0')}-'
        '${capturedDay.month.toString().padLeft(2, '0')}-'
        '${capturedDay.day.toString().padLeft(2, '0')}');
    expect(peer.publications, baselinePublications + 1);
    expect(accepted, outcome == 'confirmed');
    if (outcome == 'confirmed') {
      expect(trace, containsAllInOrder([
        'provider:notify', 'native:publishWidgetPublication',
        'native:readWidgetStore', 'home:updateWidget',
      ]));
      expect(controller.ready, isTrue);
      expect(homeCalls.any((call) => call.method == 'updateWidget' &&
          (call.arguments as Map)['android'] == 'DuoyiHabitWidgetProvider'), isTrue);
    } else {
      expect(homeCalls.where((call) => call.method == 'updateWidget'), isEmpty);
      expect(controller.ready, isFalse);
      expect(trace.where((entry) => entry == 'native:readWidgetStore'),
          outcome == 'confirmationMismatch' ? hasLength(1) : isEmpty);
      expect(controller.hasPendingOperation, isTrue);
      expect(controller.requiresDurabilityRecovery, isFalse);
      expect(hostStatuses, contains(outcome == 'confirmationMismatch'
          ? 'native publication: confirmationUnavailable'
          : 'native publication: responseUnknown'));
      expect(trace.where((entry) => entry == 'native:inspectWidgetStoreRecovery' ||
          entry == 'native:recoverWidgetStore'), isEmpty);
      expect(saved.first.todayCount(), 1,
          reason: 'publication uncertainty cannot undo an acknowledged model');
    }
    expect(homeCalls.where((call) => call.method == 'saveWidgetData'), isEmpty);
  } finally {
    queue.dispose();
    if (listening) habits.removeListener(onChange);
    if (!store.release.isCompleted) store.release.complete();
    if (!peer.ackRelease.isCompleted) peer.ackRelease.complete();
    if (!peer.readRelease.isCompleted) peer.readRelease.complete();
    try {
      await _bounded2774(Future.wait<void>([
        ...pendingActions,
        ?draining,
      ]), 'owned action/drain cleanup');
      await _bounded2774(Future.wait<bool>(captures), 'owned captures cleanup');
      await _bounded2774(AccountPreferenceWrites.drain(), 'preferences cleanup');
      await _bounded2774(HomeWidgetService.waitForAccountClear(), 'account-clear cleanup');
    } finally {
      HomeWidgetService.publicationWriter = oldWriter;
      HomeWidgetService.nativePublicationForTesting = oldNative;
      HomeWidgetService.supportedForTesting = oldSupported;
      messenger.setMockMethodCallHandler(homeChannel, null);
      messenger.setMockMethodCallHandler(peer.channel, null);
      controller.dispose();
      providers.dispose();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = oldStore;
      I18n.setLocale(oldLocale);
    }
  }
}

class _Providers2774 {
  final todos = TodoProvider();
  final habits = HabitProvider();
  final pomodoros = PomodoroProvider();
  final calendar = CalendarProvider();
  final countdowns = CountdownProvider();
  final audit = TimeAuditProvider();
  final goals = GoalProvider();
  final anniversaries = AnniversaryProvider();
  final courses = CourseProvider();
  final notes = NoteProvider();
  final diaries = DiaryProvider();
  final theme = ThemeProvider();
  final preferences = PreferencesProvider();

  Future<bool> capture({bool force = false}) => WidgetActionTestAccess.pushHomeWidget(
    todos, habits, pomodoros, calendar, countdowns, audit, goals,
    anniversaries, courses, notes, diaries, theme, preferences,
    force: force,
  );

  void dispose() {
    for (final provider in <ChangeNotifier>[
      todos, habits, pomodoros, calendar, countdowns, audit, goals,
      anniversaries, courses, notes, diaries, theme, preferences,
    ]) {
      provider.dispose();
    }
  }
}

class _HabitStore2774 extends InMemorySharedPreferencesStore {
  _HabitStore2774() : super.withData({});
  bool hold = false, reject = false;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.habits' && hold && !started.isCompleted) {
      started.complete();
      await _bounded2774(release.future, 'preferences backend release');
      await super.setValue(type, key, value);
      if (reject) {
        reject = false;
        return false;
      }
      return true;
    }
    return super.setValue(type, key, value);
  }
}

// Native facts/delivery only. Business document always comes from the outgoing
// production request; the cleared open fixture copies actual presentation values.
class _PublicationPeer2774 {
  _PublicationPeer2774() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, respond);
  }
  final channel = const MethodChannel('duoyi/habit-joined-integrated-2774');
  final trace = <String>[];
  WidgetPublication? document;
  Map? binding;
  int revision = 0, desired = 0, publications = 0;
  String epoch = '', operation = '', outcome = 'confirmed';
  bool hold = false, awaitingPublicationRead = false;
  final ackStarted = Completer<void>(), ackRelease = Completer<void>();
  final readStarted = Completer<void>(), readRelease = Completer<void>();

  Future<Object?> respond(MethodCall call) async {
    trace.add('native:${call.method}');
    final args = call.arguments as Map?;
    if (call.method == 'readWidgetStore') {
      if (document == null) return {'status': 'absent'};
      if (hold && awaitingPublicationRead) {
        readStarted.complete();
        await _bounded2774(readRelease.future, 'peer fresh-read release');
        awaitingPublicationRead = false;
      }
      return {
        'status': binding == null ? 'sealed' : 'ready',
        'storeRevision': revision, 'ownerEpoch': epoch, 'binding': binding,
        'leaseState': binding == null ? 'sealed' : 'active',
        'desiredPresentation': {'revision': desired, 'locale': 'en'},
        'document': document!.toJson(),
        'lastOperationId': outcome == 'confirmationMismatch'
            ? 'another-operation' : operation,
        'lastRequestDigest': List.filled(64, 'a').join(),
      };
    }
    final open = call.method == 'openWidgetWorkspace';
    if (open || call.method == 'invalidateWidgetWorkspace') {
      revision++;
      operation = args!['operationId'];
      epoch = 'epoch-$revision';
      binding = open ? args['binding'] as Map : null;
      final presentation = args['presentation'] as Map;
      desired = presentation['revision'];
      document = WidgetPublication(
        ownerEpoch: epoch, publicationRevision: 0, localeRevision: desired,
        state: WidgetPublicationState.cleared, locale: AppLocale.en,
        snapshotDay: '', snapshotUtcOffsetMinutes: 0, capturedAtMillis: 0,
        values: Map<String, Object>.from(presentation['values'] as Map),
      );
    } else if (call.method == 'publishWidgetPublication') {
      revision++;
      operation = args!['operationId'];
      document = WidgetPublication.tryFromJson(args['document']);
      expect(document, isNotNull);
      publications++;
      awaitingPublicationRead = true;
      if (hold) {
        ackStarted.complete();
        await _bounded2774(ackRelease.future, 'peer publication ACK release');
      }
      if (outcome == 'responseUnknown') {
        // The original outgoing document has been accepted by this peer, but
        // the response is lost. The actual client maps this to responseUnknown.
        throw PlatformException(code: 'lost_reply');
      }
    } else {
      throw StateError('Unexpected NEW2774 native call ${call.method}');
    }
    return {
      'status': 'applied', 'operationId': operation,
      'committedStoreRevision': revision, 'ownerEpoch': epoch,
      'publicationRevision': document!.publicationRevision,
      'desiredPresentationRevision': desired,
      'appliedPresentationRevision': document!.localeRevision,
      'documentState': document!.state.name, 'refreshRequested': false,
      if (open) 'writerLeaseId': 'lease-$revision',
    };
  }
}
