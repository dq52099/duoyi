// ignore_for_file: depend_on_referenced_packages
// NEW2831 source candidate only; see todo-main-joined-candidate-2831/README.md.
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/main.dart' show WidgetActionTestAccess, mainShellKey;
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_push_queue.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:duoyi/services/widget_publication_host.dart';
import 'package:duoyi/services/widget_launch_access.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _deadline = Duration(seconds: 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const homeChannel = MethodChannel('home_widget');
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
    await HomeWidgetService.waitForAccountClear().timeout(_deadline);
    homeCalls.clear();
  });
  tearDown(() async {
    try {
      await AccountPreferenceWrites.drain().timeout(_deadline);
      await HomeWidgetService.waitForAccountClear().timeout(_deadline);
    } finally {
      HomeWidgetService.publicationWriter = null;
      HomeWidgetService.nativePublicationForTesting = null;
      HomeWidgetService.supportedForTesting = null;
      messenger.setMockMethodCallHandler(homeChannel, null);
      I18n.setLocale(AppLocale.zh);
      SharedPreferences.setMockInitialValues({});
    }
  });

  for (final action in ['quick_todo', 'complete_todo']) {
    for (final mismatch in [false, true]) {
      testWidgets('$action real main handler and capture after durable model; '
          '${mismatch ? 'mismatched' : 'matching'} confirmation '
          '${mismatch ? 'blocks' : 'permits'} HOST refresh', (tester) async {
        final auth = (await tester.runAsync(() async => AuthProvider()))!;
        final todos = (await tester.runAsync(() async => TodoProvider()))!;
        addTearDown(auth.dispose);
        addTearDown(todos.dispose);
        late BuildContext actionContext;
        try {
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
            ],
            child: Builder(builder: (context) {
              actionContext = context;
              return const SizedBox.shrink();
            }),
          ));
          expect(actionContext.mounted, isTrue);
          // This mounted provider context is not the production MainShell.
          // Keep shell feedback/extra dashboard refresh explicitly out of scope.
          expect(mainShellKey.currentContext, isNull);
          await tester.runAsync(() async {
        final disposers = <void Function()>[];
        final loads = <_Observed<void>>[];
        _Observed<void>? pending;
        _Observed<void>? flushing;
        _Observed<bool>? baselinePush;
        _HeldTodoStore? held;
        _PublicationPeer? nativePeer;
        TodoProvider? listenerOwner;
        void Function()? listener;
        HomeWidgetPushQueue? ownedQueue;
        PomodoroProvider? ownedPomodoro;
        Object? bodyError;
        StackTrace? bodyStack;
        final cleanupErrors = <Object>[];
        Future<void> cleanup(String label, Future<void> Function() operation) async {
          try { await operation().timeout(_deadline); }
          catch (error) { cleanupErrors.add(StateError('$label: $error')); }
        }
        try {
          final createdAt = DateTime.now();
          final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
          final sentinel = TodoItem(id: 'sentinel', title: 'Untouched row', date: day, sortOrder: 1);
          final target = TodoItem(id: ' todo /?#&=é ', title: ' 原始任务 / keep & text ', date: day, priority: TodoPriority.high, timeTargetSeconds: 600);
          final sentinelJson = Map<String, dynamic>.from(sentinel.toJson());
          final targetJson = Map<String, dynamic>.from(target.toJson());
          final initial = [sentinel, if (action == 'complete_todo') target];
          final stored = jsonEncode(initial.map((t) => t.toJson()).toList());
          SharedPreferences.setMockInitialValues({'todos': stored});
          final store = _HeldTodoStore({'flutter.todos': stored}); held = store;
          SharedPreferencesStorePlatform.instance = store;
          final prefs = await SharedPreferences.getInstance().timeout(_deadline);
          final habits = HabitProvider(); disposers.add(habits.dispose);
          final pomodoros = PomodoroProvider(); disposers.add(pomodoros.dispose);
          final calendar = CalendarProvider(); disposers.add(calendar.dispose);
          final countdowns = CountdownProvider(); disposers.add(countdowns.dispose);
          final timeAudit = TimeAuditProvider(); disposers.add(timeAudit.dispose);
          todos.timeAudit = timeAudit;
          final goals = GoalProvider(); disposers.add(goals.dispose);
          final anniversaries = AnniversaryProvider(); disposers.add(anniversaries.dispose);
          final courses = CourseProvider(); disposers.add(courses.dispose);
          final notes = NoteProvider(); disposers.add(notes.dispose);
          final diaries = DiaryProvider(); disposers.add(diaries.dispose);
          final theme = ThemeProvider(); disposers.add(theme.dispose);
          final preferences = PreferencesProvider(); disposers.add(preferences.dispose);
          ownedPomodoro = pomodoros;
          pomodoros.attachPreferences(preferences);
          // All actual providers hydrate their ordinary empty/default stores;
          // only Todo storage contains authored fixture models.
          // Hydrate real guest Auth first; no overridden availability getters.
          final authLoad = _Observed<void>(auth.loadFromStorage(refreshServerConfig: false));
          loads.add(authLoad);
          await authLoad.value('real guest Auth hydration');
          expect(auth.isGuestWorkspaceReady, isTrue);
          expect(auth.isLocalAccountDataBlocked, isFalse);
          expect(auth.isAccountTransitionInProgress, isFalse);
          loads.add(_Observed<void>(todos.loadFromStorage()));
          loads.add(_Observed<void>(habits.loadFromStorage()));
          loads.add(_Observed<void>(pomodoros.loadFromStorage()));
          loads.add(_Observed<void>(calendar.loadFromStorage()));
          loads.add(_Observed<void>(countdowns.loadFromStorage()));
          loads.add(_Observed<void>(timeAudit.loadFromStorage()));
          loads.add(_Observed<void>(goals.loadFromStorage()));
          loads.add(_Observed<void>(anniversaries.loadFromStorage()));
          loads.add(_Observed<void>(courses.loadFromStorage()));
          loads.add(_Observed<void>(notes.loadFromStorage()));
          loads.add(_Observed<void>(diaries.loadFromStorage()));
          loads.add(_Observed<void>(theme.loadFromStorage()));
          loads.add(_Observed<void>(preferences.loadFromStorage()));
          for (final load in loads) { await load.value('provider hydration'); }
          await AccountPreferenceWrites.drain().timeout(_deadline);
          expect(I18n.current, AppLocale.en);
          final peer = _PublicationPeer(); nativePeer = peer;
          final controller = WidgetPublicationController(client: WidgetPublicationClient(channel: peer.channel));
          disposers.add(controller.dispose);
          final hostStatuses = <String>[];
          final host = WidgetPublicationHost(controller: controller, onStatus: hostStatuses.add);
          final captures = <_CaptureWindow>[];
          _CaptureWindow? activeCapture;
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          bool isCurrent() => AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation);
          Future<bool> push() {
            final capture = _CaptureWindow(DateTime.now());
            captures.add(capture); activeCapture = capture;
            // Exact main wrapper: no mirrored comparator/business map/snapshotAt.
            return WidgetActionTestAccess.pushHomeWidget(
              todos, habits, pomodoros, calendar, countdowns, timeAudit,
              goals, anniversaries, courses, notes, diaries, theme, preferences,
              force: false, isPresentationCurrent: isCurrent,
            );
          }
          HomeWidgetService.publicationWriter = (values, capturedAt) {
            final invocation = activeCapture!;
            invocation.writerAt = DateTime.now();
            invocation.capturedAt = capturedAt;
            invocation.values = Map<String, Object>.from(values);
            _assertCapture(invocation, day);
            return host.publish(
              workspace: ValidatedWidgetWorkspace(
                binding: WidgetWorkspaceBinding(kind: 'guest', key: 'local-device'),
                accountGeneration: generation, isCurrent: isCurrent,
              ),
              // Match main's canonical presentation boundary; the host receives
              // the original full payload and selects its canonical values.
              presentation: WidgetDevicePresentation(
                locale: I18n.current,
                completeValues: <String, Object>{
                  for (final key in WidgetPublication.valueKeys) key: values[key]!,
                },
              ),
              completeValues: values, capturedAt: capturedAt,
              refreshWidgets: () {
                peer.events.add('refresh-request');
                return HomeWidgetService.refreshPublishedWidgets();
              },
              requestFreshCapture: push,
              invalidatePushSignature: HomeWidgetService.invalidatePushSignature,
            );
          };
          final pushResults = <bool>[];
          final queueErrors = <Object>[];
          final queue = HomeWidgetPushQueue(
            canPublish: isCurrent,
            readSignature: () => todos.revision.toString(),
            publish: () async {
              final result = await push(); pushResults.add(result); return result;
            },
            onFailure: (error, stack) => queueErrors.add(error),
          ); ownedQueue = queue;
          var notices = 0;
          void onChange() {
            notices++;
            HomeWidgetService.invalidatePushSignature();
            queue.queue();
          }
          // Queue/listener are a HOST harness, not mounted main orchestration.
          baselinePush = _Observed<bool>(push());
          expect(await baselinePush.value('baseline push'), isTrue);
          expect(captures, hasLength(1)); _assertCapture(captures.single, day);
          final baseline = peer.document!.toJson();
          todos.addListener(onChange); listenerOwner = todos; listener = onChange;
          peer.events.clear(); homeCalls.clear();
          store.holdNext = true; peer.holdPublicationConfirmation = true; peer.mismatchConfirmation = mismatch;
          final requests = WidgetNavigationRequests(accountGeneration: () =>
              AccountLocalDataCleaner.accountDataGeneration);
          var receiptAcknowledgements = 0;
          final access = WidgetLaunchAccess(
            uri: Uri(scheme: 'duoyi', host: 'action', path: '/$action',
              queryParameters: {'id': target.id, 'widget_delivery': 'todo-main-2831'}),
            request: requests.capture(),
            isCallerAvailable: () => actionContext.mounted && isCurrent(),
            isBlocked: () => false,
            requeue: (_, _) => fail('Unexpected Todo action requeue'),
            acknowledge: (_) async { receiptAcknowledgements++; },
          );
          bool? quickCreated;
          final mutationBefore = DateTime.now();
          pending = _Observed<void>(access.run(() async {
            if (action == 'quick_todo') {
              quickCreated = await WidgetActionTestAccess.createQuickTodo(
                actionContext, target, access: access,
              );
            } else {
              await WidgetActionTestAccess.completeTodo(
                actionContext, todos, target, access,
              );
            }
          }));
          access.finishDispatch();
          await _gate(store.entered.future, pending, 'Todo backend write gate');
          expect(notices, 0);
          expect(receiptAcknowledgements, 0);
          expect(timeAudit.entries, isEmpty);
          expect(prefs.getStringList(TimeAuditProvider.storageKey) ?? <String>[], isEmpty);
          expect((await store.getAll().timeout(_deadline))['flutter.${TimeAuditProvider.storageKey}'], isNull);
          // Legacy SharedPreferences cache is optimistic; backend is the held durability oracle.
          expect((await store.getAll().timeout(_deadline))['flutter.todos'], stored);
          expect(todos.todos.singleWhere((t) => t.id == sentinel.id).toJson(), sentinelJson);
          if (action == 'quick_todo') {
            expect(todos.todos.map((t) => t.id), isNot(contains(target.id)));
          } else {
            expect(todos.todos.singleWhere((t) => t.id == target.id).toJson(), targetJson);
          }
          expect(peer.document!.toJson(), baseline); expect(peer.events, isEmpty); expect(homeCalls, isEmpty);
          if (action == 'complete_todo') {
            // Preserve the original numeric duplicate-provider oracle; the
            // original action above goes through the real main handler.
            expect(await todos.completeTodos([target.id]).timeout(_deadline), 0);
            expect(notices, 0);
          }
          store.release.complete();
          await pending.value('original main action');
          final mutationAfter = DateTime.now();
          if (action == 'quick_todo') expect(quickCreated, isTrue);
          expect(receiptAcknowledgements, 1,
            reason: 'action consumption is distinct from publication ACK/readback');
          expect(notices, 1);
          final originals = todos.todos;
          expect(jsonDecode(prefs.getString('todos')!), unorderedEquals(originals.map((t) => t.toJson())));
          expect(jsonDecode((await store.getAll().timeout(_deadline))['flutter.todos'] as String), unorderedEquals(originals.map((t) => t.toJson())));
          expect(originals, hasLength(2));
          expect(originals.map((t) => t.id).toSet(), {sentinel.id, target.id});
          final savedTarget = originals.singleWhere((t) => t.id == target.id);
          expect(originals.singleWhere((t) => t.id == sentinel.id).toJson(), sentinelJson);
          if (action == 'quick_todo') {
            expect(savedTarget.toJson(), targetJson);
          } else {
            final after = Map<String, dynamic>.from(savedTarget.toJson());
            final expected = Map<String, dynamic>.from(targetJson);
            for (final key in ['isCompleted', 'completedAt', 'kanbanColumnId', 'updatedAt']) { after.remove(key); expected.remove(key); }
            expect(after, expected); expect(savedTarget.isCompleted, isTrue);
            expect(savedTarget.kanbanColumnId, defaultKanbanDoneColumnId);
            final completion = savedTarget.completedAt!;
            expect(completion.isBefore(mutationBefore), isFalse);
            expect(completion.isAfter(mutationAfter), isFalse);
            expect(savedTarget.updatedAt.isBefore(completion), isFalse);
            expect(savedTarget.updatedAt.isAfter(mutationAfter), isFalse);
          }
          // The real main completion handler uses the default time recording.
          // A positive duration makes that default observable, not a no-op.
          if (action == 'complete_todo') {
            expect(timeAudit.entries, hasLength(1));
            final entry = timeAudit.entries.single;
            expect(entry.source, TimeEntrySource.todo);
            expect(entry.category, TimeEntryCategory.todo);
            expect(entry.sourceId, target.id);
            expect(entry.title, target.title);
            expect(entry.durationSeconds, 600);
            expect(entry.endAt, savedTarget.completedAt);
            expect(entry.startAt, savedTarget.completedAt!.subtract(const Duration(seconds: 600)));
            final durableEntries = (await store.getAll().timeout(_deadline))[
                'flutter.${TimeAuditProvider.storageKey}'] as List;
            expect(durableEntries.map((raw) => jsonDecode(raw as String)),
              unorderedEquals(timeAudit.entries.map((entry) => entry.toJson())));
            expect(prefs.getStringList(TimeAuditProvider.storageKey)!.map(jsonDecode),
              unorderedEquals(timeAudit.entries.map((entry) => entry.toJson())));
          } else {
            expect(timeAudit.entries, isEmpty);
            expect(prefs.getStringList(TimeAuditProvider.storageKey) ?? <String>[], isEmpty);
            expect((await store.getAll().timeout(_deadline))['flutter.${TimeAuditProvider.storageKey}'], isNull);
          }
          // Only real provider notification queues the pass; flush drains it.
          flushing = _Observed<void>(queue.flush());
          await _gate(peer.confirmationEntered.future, flushing, 'ordered confirmation gate');
          expect(peer.events, ['publication-ack', 'confirmation-read']); expect(homeCalls, isEmpty);
          expect(captures, hasLength(2)); _assertCapture(captures.last, day);
          final expectedCount = action == 'quick_todo' ? 2 : 1;
          final document = peer.document!;
          expect(document.state, WidgetPublicationState.published);
          expect(document.values.keys.toSet(), WidgetPublication.valueKeys);
          expect(document.values['todo_count'], expectedCount); expect(document.values['todo_top3_count'], expectedCount);
          expect(document.values['todo_top3_1_id'], action == 'quick_todo' ? target.id : sentinel.id);
          expect(document.values['todo_top3_1'], '· ${action == 'quick_todo' ? target.title : sentinel.title}');
          expect(document.values['todo_top3_2_id'], action == 'quick_todo' ? sentinel.id : '');
          expect(document.values['todo_top3_2'], action == 'quick_todo' ? '· ${sentinel.title}' : '');
          expect(document.values['todo_top3_3_id'], ''); expect(document.values['todo_top3_3'], '');
          expect(document.capturedAtMillis, captures.last.capturedAt!.millisecondsSinceEpoch);
          expect(document.snapshotDay, _day(captures.last.capturedAt!));
          expect(document.snapshotUtcOffsetMinutes, captures.last.capturedAt!.timeZoneOffset.inMinutes);
          expect(peer.publications, hasLength(2));
          expect(peer.publications.last['document'], document.toJson());
          expect(peer.lastAcknowledgement!['operationId'], peer.publications.last['operationId']);
          final pendingRequest = Map<String, Object?>.from(peer.publications.last);
          peer.confirmationRelease.complete();
          await flushing.value('original queue flush');
          // Stop automatic HOST retry before assertions/cleanup; only original pass is in scope.
          queue.dispose();
          expect(pushResults, [!mismatch]);
          expect(peer.events, ['publication-ack', 'confirmation-read', if (!mismatch) 'refresh-request']);
          expect(homeCalls.where((c) => c.method == 'updateWidget').isNotEmpty, !mismatch);
          expect(homeCalls.any((c) => c.method == 'updateWidget' && (c.arguments as Map)['android'] == 'DuoyiTodoWidgetProvider'), !mismatch);
          expect(homeCalls.where((c) => c.method == 'saveWidgetData'), isEmpty);
          expect(peer.publications.last, pendingRequest); expect(peer.publications, hasLength(2));
          expect(controller.ready, !mismatch); expect(controller.hasPendingOperation, mismatch);
          final confirmedValues = ((peer.readReplies.last['document'] as Map)['values'] as Map);
          expect(confirmedValues['todo_count'], expectedCount + (mismatch ? 1 : 0));
          expect(confirmedValues['todo_top3_count'], expectedCount + (mismatch ? 1 : 0));
          expect(queueErrors, mismatch ? hasLength(1) : isEmpty);
          expect(hostStatuses.any((status) => status.contains('confirmationUnavailable')), mismatch);
        } catch (error, stack) {
          bodyError = error; bodyStack = stack;
        } finally {
          if (listenerOwner != null && listener != null) listenerOwner.removeListener(listener);
          ownedQueue?.dispose();
          if (held != null && !held.release.isCompleted) held.release.complete();
          if (nativePeer != null && !nativePeer.confirmationRelease.isCompleted) nativePeer.confirmationRelease.complete();
          if (pending != null) await cleanup('original action', () async { await pending!.value('cleanup action'); });
          if (flushing != null) await cleanup('original flush', () async { await flushing!.value('cleanup flush'); });
          if (baselinePush != null) await cleanup('baseline push', () async { await baselinePush!.value('cleanup baseline'); });
          for (final load in loads) { await cleanup('original hydration', () async { await load.value('cleanup hydration'); }); }
          await cleanup('account write drain', AccountPreferenceWrites.drain);
          HomeWidgetService.publicationWriter = null;
          nativePeer?.dispose();
          for (final dispose in disposers.reversed) { try { dispose(); } catch (error) { cleanupErrors.add(error); } }
          if (ownedPomodoro != null) await cleanup('pomodoro snapshot drain', () async { await ownedPomodoro!.waitForSnapshotWrites(); });
          await cleanup('post-disposal account write drain', AccountPreferenceWrites.drain);
          if (cleanupErrors.isNotEmpty) debugPrint('NEW2775 cleanup diagnostics: $cleanupErrors');
        }
        if (bodyError != null) Error.throwWithStackTrace(bodyError, bodyStack!);
        if (cleanupErrors.isNotEmpty) throw StateError('NEW2775 incomplete cleanup: $cleanupErrors');
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          // Collect deferred typed feedback against the deliberately absent shell.
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      }, timeout: const Timeout(Duration(seconds: 90)));
    }
  }
}

class _CaptureWindow {
  _CaptureWindow(this.before);
  final DateTime before;
  DateTime? writerAt;
  DateTime? capturedAt;
  Map<String, Object>? values;
}
String _day(DateTime at) => '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
void _assertCapture(_CaptureWindow capture, DateTime modelDay) {
  final at = capture.capturedAt!, writer = capture.writerAt!;
  expect(at.isBefore(capture.before), isFalse); expect(at.isAfter(writer), isFalse);
  expect(_day(at), _day(modelDay)); expect(_day(writer), _day(modelDay));
  expect(at.timeZoneOffset, writer.timeZoneOffset);
}

// Observe the original future immediately; no unhandled delayed error or replacement action.
class _Observed<T> {
  _Observed(Future<T> original) {
    done = original.then<_Terminal<T>>((value) => _Terminal<T>(value),
      onError: (Object error, StackTrace stack) => _Terminal<T>.error(error, stack));
  }
  late final Future<_Terminal<T>> done;
  Future<T> value(String label) async {
    final terminal = await done.timeout(_deadline, onTimeout: () => throw TimeoutException(label, _deadline));
    if (terminal.error != null) Error.throwWithStackTrace(terminal.error!, terminal.stack!);
    return terminal.value as T;
  }
}
class _Terminal<T> {
  _Terminal(this.value) : error = null, stack = null;
  _Terminal.error(this.error, this.stack) : value = null;
  final T? value;
  final Object? error;
  final StackTrace? stack;
}
Future<void> _gate<T>(Future<void> reached, _Observed<T> original, String label) async {
  await Future.any<void>([
    reached,
    original.done.then<void>((terminal) {
      if (terminal.error != null) Error.throwWithStackTrace(terminal.error!, terminal.stack!);
      throw StateError('$label not reached before original future completed');
    }),
  ]).timeout(_deadline, onTimeout: () => throw TimeoutException(label, _deadline));
}

class _HeldTodoStore extends InMemorySharedPreferencesStore {
  _HeldTodoStore(super.data) : super.withData();
  bool holdNext = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.todos' && holdNext) {
      holdNext = false;
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

// Scripted storage delivery only, not native CAS/SQLite or a launcher.
// Published documents are decoded from the ORIGINAL production request.
class _PublicationPeer {
  _PublicationPeer() {
    _messenger.setMockMethodCallHandler(channel, _respond);
  }
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channel = const MethodChannel('duoyi/todo-joined-action-2775');
  final events = <String>[];
  final publications = <Map<String, Object?>>[];
  final readReplies = <Map<String, Object?>>[];
  Map<String, Object?>? lastAcknowledgement;
  final confirmationEntered = Completer<void>();
  final confirmationRelease = Completer<void>();
  WidgetPublication? document;
  Map? binding;
  int revision = 0, desired = 0;
  String epoch = '', operation = '';
  bool holdPublicationConfirmation = false, mismatchConfirmation = false;

  Future<Object?> _respond(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'readWidgetStore':
        if (document == null) return {'status': 'absent'};
        if (holdPublicationConfirmation &&
            document!.state == WidgetPublicationState.published) {
          holdPublicationConfirmation = false;
          events.add('confirmation-read');
          confirmationEntered.complete();
          await confirmationRelease.future;
        }
        final raw = document!.toJson();
        // Negative delivery oracle: valid receipt, inconsistent fresh content.
        if (mismatchConfirmation && confirmationEntered.isCompleted) {
          raw['values'] = {
            ...document!.values,
            'todo_count': (document!.values['todo_count'] as int) + 1,
            'todo_top3_count': (document!.values['todo_top3_count'] as int) + 1,
          };
        }
        final reply = <String, Object?>{
          'status': 'ready', 'storeRevision': revision,
          'ownerEpoch': epoch, 'binding': binding, 'leaseState': 'active',
          'desiredPresentation': {'revision': desired, 'locale': 'en'},
          'document': raw, 'lastOperationId': operation,
          'lastRequestDigest': List.filled(64, 'a').join(),
        };
        readReplies.add(Map<String, Object?>.from(jsonDecode(jsonEncode(reply)) as Map));
        return reply;
      case 'openWidgetWorkspace':
        revision++;
        operation = args!['operationId'];
        epoch = 'epoch-$revision';
        binding = args['binding'] as Map;
        final p = args['presentation'] as Map;
        desired = p['revision'];
        document = WidgetPublication(
          ownerEpoch: epoch, publicationRevision: 0, localeRevision: desired,
          state: WidgetPublicationState.cleared, locale: AppLocale.en,
          snapshotDay: '', snapshotUtcOffsetMinutes: 0, capturedAtMillis: 0,
          values: Map<String, Object>.from(p['values'] as Map),
        );
        return _ack(open: true);
      case 'publishWidgetPublication':
        revision++;
        operation = args!['operationId'];
        publications.add(Map<String, Object?>.from(jsonDecode(jsonEncode(args)) as Map));
        document = WidgetPublication.tryFromJson(args['document'])!;
        events.add('publication-ack');
        lastAcknowledgement = _ack();
        return lastAcknowledgement;
      default:
        throw StateError('Unexpected native call ${call.method}');
    }
  }

  Map<String, Object?> _ack({bool open = false}) => {
    'status': 'applied', 'operationId': operation,
    'committedStoreRevision': revision, 'ownerEpoch': epoch,
    'publicationRevision': document!.publicationRevision,
    'desiredPresentationRevision': desired,
    'appliedPresentationRevision': document!.localeRevision,
    'documentState': document!.state.name, 'refreshRequested': false,
    if (open) 'writerLeaseId': 'lease-$revision',
  };
  void dispose() => _messenger.setMockMethodCallHandler(channel, null);
}
