// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:test/test.dart';

typedef _ReviewCall = Future<String> Function(AiService service);

class _ReviewProducer {
  const _ReviewProducer(this.name, this.invoke);

  final String name;
  final _ReviewCall invoke;
}

final _reviewProducers = <_ReviewProducer>[
  _ReviewProducer(
    'weeklyReview',
    (service) => service.weeklyReview(
      completedTodos: 2,
      totalTodos: 3,
      weeklyFocusMinutes: 45,
      habitStreak: 4,
      periodLabel: '本周',
      now: DateTime(2026, 5, 25, 9),
    ),
  ),
  _ReviewProducer(
    'personalizedReportReview',
    (service) => service.personalizedReportReview(
      periodLabel: '上周',
      reportMarkdown: '待办完成 2 / 3，专注 45 分钟。',
    ),
  ),
  _ReviewProducer(
    'deepDiaryReview',
    (service) => service.deepDiaryReview(
      entries: [
        DiaryEntry(
          id: 'diary-1',
          date: DateTime(2026, 5, 24),
          content: '今天完成了计划，也休息得不错。',
          createdAt: DateTime(2026, 5, 24, 21),
          updatedAt: DateTime(2026, 5, 24, 21),
        ),
      ],
      today: DateTime(2026, 5, 25),
    ),
  ),
  _ReviewProducer(
    'reviewFromReport',
    (service) => service.reviewFromReport(
      completedTodos: 2,
      totalTodos: 3,
      focusMinutes: 45,
      habitStreak: 4,
      habitCheckIns: 5,
      timeEntryMinutes: 90,
      periodLabel: '上周',
    ),
  ),
];

class _ServiceHarness {
  _ServiceHarness(this.transport, {bool Function()? historyAccessAllowed})
    : service = AiService(),
      client = ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'old-token',
        httpClient: transport,
      ) {
    service.historyAccessAllowed = historyAccessAllowed;
    service.attachClient(client);
    service.updateFromServerConfig({
      'ai_enabled': true,
      'ai_model': 'gpt-test',
    });
  }

  final MockClient transport;
  final AiService service;
  final ApiClient client;
  bool _serviceDisposed = false;
  bool _closed = false;

  void disposeService() {
    if (_serviceDisposed) return;
    _serviceDisposed = true;
    service.dispose();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    disposeService();
    transport.close();
  }
}

class _TestPreferencesStore extends InMemorySharedPreferencesStore {
  _TestPreferencesStore({Map<String, Object> initialData = const {}})
    : super.withData(initialData);

  final List<List<String>> historySnapshots = [];
  final List<String> historyOperations = [];
  Completer<void>? historyWriteGate;
  Completer<void>? historyWriteStarted;
  Completer<void>? getAllGate;
  Completer<void>? getAllStarted;
  final List<bool> historyWriteResults = [];
  bool returnFalseForHistoryWrite = false;
  bool captureReadsBeforeGate = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (valueType == 'StringList' && key == 'flutter.ai_review_history') {
      final snapshot = List<String>.from(value as List<String>);
      historySnapshots.add(snapshot);
      historyOperations.add('set:${snapshot.length}');
      final gate = historyWriteGate;
      if (gate != null) {
        final started = historyWriteStarted;
        if (started != null && !started.isCompleted) started.complete();
        await gate.future;
      }
      if (historyWriteResults.isNotEmpty && !historyWriteResults.removeAt(0)) {
        return false;
      }
      if (returnFalseForHistoryWrite) return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final captured = captureReadsBeforeGate
        ? await super.getAllWithParameters(parameters)
        : null;
    final gate = getAllGate;
    if (gate != null) {
      final started = getAllStarted;
      if (started != null && !started.isCompleted) started.complete();
      await gate.future;
    }
    return captured ?? await super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.ai_review_history') {
      historyOperations.add('remove');
    }
    return super.remove(key);
  }
}

http.Response _successResponse() => http.Response(
  jsonEncode({'content': '模型回顾内容'}),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object> _storedWeeklyReview(DateTime createdAt) => {
  'id': 'cached-weekly',
  'createdAt': createdAt.toIso8601String(),
  'content': '当天已有周回顾',
  'summary': '本周数据：完成 1 / 2 项待办，专注 30 分钟，习惯连续打卡 2 天。',
  'model': 'gpt-test',
  'kind': AiService.weeklyReviewKind,
};

Future<void> _ignoreFailure(Future<dynamic>? future) async {
  if (future == null) return;
  try {
    await future;
  } catch (_) {}
}

Future<Object?> _captureFailure(Future<dynamic> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final producer in _reviewProducers) {
    for (final staleResponse in [false, true]) {
      final resultKind = staleResponse ? 'success' : 'failure';
      test(
        '${producer.name} discards stale $resultKind after client replacement',
        () async {
          final requestStarted = Completer<void>();
          final responseGate = Completer<void>();
          final harness = _ServiceHarness(
            MockClient((request) async {
              if (!requestStarted.isCompleted) requestStarted.complete();
              await responseGate.future;
              return staleResponse
                  ? _successResponse()
                  : http.Response(
                      jsonEncode({'detail': 'upstream failed'}),
                      502,
                      headers: {'content-type': 'application/json'},
                    );
            }),
          );
          final replacementTransport = MockClient(
            (request) async => _successResponse(),
          );
          Future<String>? pending;
          try {
            pending = producer.invoke(harness.service);
            await requestStarted.future;
            harness.service.attachClient(
              ApiClient(
                baseUrl: 'https://next-account.test',
                token: 'new-token',
                httpClient: replacementTransport,
              ),
            );
            responseGate.complete();

            await expectLater(
              pending,
              throwsA(isA<AiReviewDiscardedException>()),
            );
            await harness.service.drainPendingHistoryWrites();
            expect(harness.service.reviewHistory, isEmpty);
            final prefs = await SharedPreferences.getInstance();
            expect(prefs.getStringList('ai_review_history'), isNull);
          } finally {
            if (!responseGate.isCompleted) responseGate.complete();
            await _ignoreFailure(pending);
            harness.dispose();
            replacementTransport.close();
          }
        },
      );
    }
  }

  test(
    'account epoch clears same-day cache before reset and fences its pending review',
    () async {
      final day = DateTime(2026, 5, 25, 9);
      SharedPreferences.setMockInitialValues({
        'ai_review_history': [jsonEncode(_storedWeeklyReview(day))],
      });
      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      var requestCount = 0;
      final harness = _ServiceHarness(
        MockClient((request) async {
          requestCount++;
          if (!requestStarted.isCompleted) requestStarted.complete();
          await responseGate.future;
          return _successResponse();
        }),
      );
      Future<String>? pending;
      try {
        await harness.service.loadFromStorage();
        expect(harness.service.weeklyReviewForDay(day)?.content, '当天已有周回顾');
        expect(await _reviewProducers.first.invoke(harness.service), '当天已有周回顾');
        expect(requestCount, 0);

        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(harness.service.reviewHistory, isEmpty);
        expect(harness.service.weeklyReviewForDay(day), isNull);

        // The asynchronous account reset has not run yet; the epoch listener
        // must already hide the cached result and force a fresh request.
        pending = _reviewProducers.first.invoke(harness.service);
        await requestStarted.future;
        expect(requestCount, 1);
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        responseGate.complete();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        expect(harness.service.reviewHistory, isEmpty);

        // This is the later synchronous local reset performed by account
        // cleanup. It remains safe after the listener already cleared state.
        harness.service.resetLocalState();
        expect(harness.service.reviewHistory, isEmpty);
      } finally {
        if (!responseGate.isCompleted) responseGate.complete();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test(
    'storage reset fences delayed history hydration and an in-flight review',
    () async {
      final stored = [
        jsonEncode(_storedWeeklyReview(DateTime(2026, 5, 25, 9))),
      ];
      final preferences =
          _TestPreferencesStore(
              initialData: {'flutter.ai_review_history': stored},
            )
            ..getAllGate = Completer<void>()
            ..getAllStarted = Completer<void>();
      SharedPreferencesStorePlatform.instance = preferences;

      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      final harness = _ServiceHarness(
        MockClient((request) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await responseGate.future;
          return _successResponse();
        }),
      );
      Future<void>? loading;
      Future<String>? pending;
      try {
        loading = harness.service.loadFromStorage();
        await preferences.getAllStarted!.future;
        harness.service.resetLocalState();
        preferences.getAllGate!.complete();
        await loading;
        expect(harness.service.reviewHistory, isEmpty);

        pending = _reviewProducers[1].invoke(harness.service);
        await requestStarted.future;
        harness.service.resetLocalState();
        responseGate.complete();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        expect(harness.service.reviewHistory, isEmpty);
        expect(preferences.historySnapshots, isEmpty);
      } finally {
        final pendingGetAllGate = preferences.getAllGate;
        if (pendingGetAllGate != null && !pendingGetAllGate.isCompleted) {
          pendingGetAllGate.complete();
        }
        if (!responseGate.isCompleted) responseGate.complete();
        await _ignoreFailure(loading);
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test(
    'disposed service discards a successful response without persisting it',
    () async {
      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      final harness = _ServiceHarness(
        MockClient((request) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await responseGate.future;
          return _successResponse();
        }),
      );
      Future<String>? pending;
      try {
        pending = _reviewProducers[2].invoke(harness.service);
        await requestStarted.future;
        harness.disposeService();
        responseGate.complete();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        expect(harness.service.reviewHistory, isEmpty);
        await harness.service.drainPendingHistoryWrites();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('ai_review_history'), isNull);
      } finally {
        if (!responseGate.isCompleted) responseGate.complete();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test('all review producers still return and store live results', () async {
    var requestCount = 0;
    final harness = _ServiceHarness(
      MockClient((request) async {
        requestCount++;
        return _successResponse();
      }),
    );
    try {
      for (final producer in _reviewProducers) {
        final result = await producer.invoke(harness.service);
        expect(result, isNotEmpty, reason: producer.name);
      }
      await harness.service.drainPendingHistoryWrites();
      expect(requestCount, 4);
      expect(harness.service.reviewHistory, hasLength(4));
      expect(
        harness.service.reviewHistory.any(
          (entry) => entry.summary.startsWith('日记深度复盘：'),
        ),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ai_review_history'), hasLength(4));
    } finally {
      harness.dispose();
    }
  });

  test(
    'weekly review keeps a failed save dirty through load and retry',
    () async {
      final preferences = _TestPreferencesStore()
        ..historyWriteResults.addAll([false, true]);
      SharedPreferencesStorePlatform.instance = preferences;
      var requestCount = 0;
      final harness = _ServiceHarness(
        MockClient((request) async {
          requestCount++;
          return _successResponse();
        }),
      );
      try {
        Object? firstFailure;
        try {
          await _reviewProducers.first.invoke(harness.service);
        } catch (error) {
          firstFailure = error;
        }
        expect(firstFailure, isA<AiReviewHistoryWriteException>());
        final unsaved = harness.service.reviewHistory.single;
        final day = DateTime(2026, 5, 25, 9);
        expect(harness.service.weeklyReviewForDay(day), isNull);
        expect(
          (await preferences.getAll()).containsKey('flutter.ai_review_history'),
          isFalse,
        );

        await harness.service.loadFromStorage();
        expect(harness.service.reviewHistory.single, same(unsaved));
        expect(harness.service.weeklyReviewForDay(day), isNull);

        final retryResult = await _reviewProducers.first.invoke(
          harness.service,
        );
        expect(retryResult, unsaved.content);
        expect(requestCount, 1);
        expect(harness.service.reviewHistory.single.id, unsaved.id);
        expect(harness.service.weeklyReviewForDay(day)?.id, unsaved.id);

        final stored = (await preferences
            .getAll())['flutter.ai_review_history'];
        expect(stored, isA<List<String>>());
        final storedEntry = AiReviewEntry.fromJson(
          jsonDecode((stored! as List<String>).single),
        );
        expect(storedEntry.id, unsaved.id);
        expect(
          preferences.historySnapshots.map((snapshot) => snapshot.length),
          [1, 1],
        );
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
      } finally {
        harness.dispose();
      }
    },
  );

  test(
    'weekly cached retry still fails when its second platform write is false',
    () async {
      final preferences = _TestPreferencesStore()
        ..historyWriteResults.addAll([false, false]);
      SharedPreferencesStorePlatform.instance = preferences;
      var requestCount = 0;
      final harness = _ServiceHarness(
        MockClient((request) async {
          requestCount++;
          return _successResponse();
        }),
      );
      try {
        Object? firstFailure;
        try {
          await _reviewProducers.first.invoke(harness.service);
        } catch (error) {
          firstFailure = error;
        }
        expect(firstFailure, isA<AiReviewHistoryWriteException>());
        final unsaved = harness.service.reviewHistory.single;
        final day = DateTime(2026, 5, 25, 9);
        expect(harness.service.weeklyReviewForDay(day), isNull);

        Object? retryError;
        String? retryResult;
        try {
          retryResult = await _reviewProducers.first.invoke(harness.service);
        } catch (error) {
          retryError = error;
        }
        expect(retryError, isA<AiReviewHistoryWriteException>());
        expect(retryResult, isNull);
        expect(requestCount, 1);
        expect(harness.service.reviewHistory.single.id, unsaved.id);
        expect(harness.service.weeklyReviewForDay(day), isNull);
        expect(preferences.historySnapshots, hasLength(2));
        expect(
          preferences.historySnapshots.every(
            (snapshot) => snapshot.length == 1,
          ),
          isTrue,
        );
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
      } finally {
        harness.dispose();
      }
    },
  );

  test(
    'clean hydration reloads the host after a false cached setter',
    () async {
      final preferences = _TestPreferencesStore()
        ..returnFalseForHistoryWrite = true;
      SharedPreferencesStorePlatform.instance = preferences;
      final harness = _ServiceHarness(
        MockClient((request) async => _successResponse()),
      );
      try {
        await expectLater(
          _reviewProducers.first.invoke(harness.service),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('ai_review_history'), hasLength(1));
        expect(
          (await preferences.getAll()).containsKey('flutter.ai_review_history'),
          isFalse,
        );

        harness.service.resetLocalState();
        await harness.service.loadFromStorage();
        expect(harness.service.reviewHistory, isEmpty);
        expect(
          harness.service.weeklyReviewForDay(DateTime(2026, 5, 25, 9)),
          isNull,
        );
        expect(prefs.getStringList('ai_review_history'), isNull);
        expect(preferences.historySnapshots, hasLength(1));
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
      } finally {
        harness.dispose();
      }
    },
  );

  test('cached weekly result waits for its pending platform write', () async {
    final preferences = _TestPreferencesStore()
      ..historyWriteGate = Completer<void>()
      ..historyWriteStarted = Completer<void>();
    SharedPreferencesStorePlatform.instance = preferences;
    var requestCount = 0;
    final harness = _ServiceHarness(
      MockClient((request) async {
        requestCount++;
        return _successResponse();
      }),
    );
    Future<String>? initialReview;
    Future<String>? cachedObserved;
    try {
      initialReview = _reviewProducers.first.invoke(harness.service);
      await preferences.historyWriteStarted!.future;
      final unsaved = harness.service.reviewHistory.single;
      final day = DateTime(2026, 5, 25, 9);
      expect(harness.service.weeklyReviewForDay(day), isNull);

      var cachedCompleted = false;
      final pendingCachedReview = _reviewProducers.first.invoke(
        harness.service,
      );
      cachedObserved = pendingCachedReview.then((value) {
        cachedCompleted = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cachedCompleted, isFalse);
      expect(harness.service.weeklyReviewForDay(day), isNull);

      preferences.historyWriteGate!.complete();
      final initialResult = await initialReview;
      final cachedResult = await cachedObserved;
      expect(cachedResult, initialResult);
      expect(unsaved.id, harness.service.reviewHistory.single.id);
      expect(harness.service.weeklyReviewForDay(day)?.id, unsaved.id);
      expect(requestCount, 1);
      await harness.service.drainPendingHistoryWrites();
    } finally {
      if (!preferences.historyWriteGate!.isCompleted) {
        preferences.historyWriteGate!.complete();
      }
      await _ignoreFailure(initialReview);
      await _ignoreFailure(cachedObserved);
      harness.dispose();
    }
  });

  test(
    'older successful snapshot cannot clear dirty append and delete revisions',
    () async {
      final preferences = _TestPreferencesStore()
        ..historyWriteGate = Completer<void>()
        ..historyWriteStarted = Completer<void>()
        ..historyWriteResults.addAll([true, false, false, true]);
      SharedPreferencesStorePlatform.instance = preferences;
      final secondRequestStarted = Completer<void>();
      var requestCount = 0;
      final harness = _ServiceHarness(
        MockClient((request) async {
          requestCount++;
          if (requestCount == 2 && !secondRequestStarted.isCompleted) {
            secondRequestStarted.complete();
          }
          return _successResponse();
        }),
      );
      Future<String>? firstReview;
      Future<String>? secondReview;
      Future<void>? deleteReview;
      Future<Object?>? secondFailure;
      Future<Object?>? deleteFailure;
      Future<String>? cachedRetry;
      try {
        firstReview = _reviewProducers.first.invoke(harness.service);
        await preferences.historyWriteStarted!.future;
        final weeklyEntry = harness.service.reviewHistory.single;
        final day = DateTime(2026, 5, 25, 9);

        secondReview = _reviewProducers[1].invoke(harness.service);
        secondFailure = _captureFailure(secondReview);
        await secondRequestStarted.future;
        for (
          var attempt = 0;
          attempt < 20 && harness.service.reviewHistory.length < 2;
          attempt++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(harness.service.reviewHistory, hasLength(2));
        final appendedEntry = harness.service.reviewHistory.first;
        expect(appendedEntry.id, isNot(weeklyEntry.id));

        deleteReview = harness.service.deleteReview(appendedEntry.id);
        deleteFailure = _captureFailure(deleteReview);
        expect(harness.service.reviewHistory, hasLength(1));
        expect(harness.service.reviewHistory.single.id, weeklyEntry.id);

        preferences.historyWriteGate!.complete();
        final firstResult = await firstReview;
        expect(await secondFailure, isA<AiReviewHistoryWriteException>());
        expect(await deleteFailure, isA<AiReviewHistoryWriteException>());
        expect(harness.service.weeklyReviewForDay(day), isNull);

        await harness.service.loadFromStorage();
        expect(harness.service.reviewHistory, hasLength(1));
        expect(harness.service.reviewHistory.single.id, weeklyEntry.id);

        cachedRetry = _reviewProducers.first.invoke(harness.service);
        expect(await cachedRetry, firstResult);
        expect(requestCount, 2);
        expect(preferences.historySnapshots, hasLength(4));
        expect(preferences.historySnapshots.first, hasLength(1));
        expect(preferences.historySnapshots[1], hasLength(2));
        expect(preferences.historySnapshots[2], hasLength(1));
        expect(preferences.historySnapshots[3], hasLength(1));
        expect(harness.service.weeklyReviewForDay(day)?.id, weeklyEntry.id);

        final stored = (await preferences
            .getAll())['flutter.ai_review_history'];
        expect(stored, isA<List<String>>());
        final storedEntries = (stored! as List<String>)
            .map((raw) => AiReviewEntry.fromJson(jsonDecode(raw)))
            .toList();
        expect(storedEntries, hasLength(1));
        expect(storedEntries.single.id, weeklyEntry.id);
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
      } finally {
        if (!preferences.historyWriteGate!.isCompleted) {
          preferences.historyWriteGate!.complete();
        }
        await _ignoreFailure(firstReview);
        await _ignoreFailure(secondReview);
        await _ignoreFailure(deleteReview);
        await _ignoreFailure(cachedRetry);
        await _ignoreFailure(secondFailure);
        await _ignoreFailure(deleteFailure);
        harness.dispose();
      }
    },
  );

  test(
    'history access guard skips AI and mutable client fields discard stale work',
    () async {
      var allowed = false;
      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      var requestCount = 0;
      final harness = _ServiceHarness(
        MockClient((request) async {
          requestCount++;
          if (!requestStarted.isCompleted) requestStarted.complete();
          await responseGate.future;
          return _successResponse();
        }),
        historyAccessAllowed: () => allowed,
      );
      Future<String>? pending;
      try {
        await expectLater(
          _reviewProducers.first.invoke(harness.service),
          throwsA(isA<AiReviewDiscardedException>()),
        );
        expect(requestCount, 0);

        allowed = true;
        pending = _reviewProducers.first.invoke(harness.service);
        await requestStarted.future;
        harness.client
          ..token = 'rotated-token'
          ..baseUrl = 'https://rotated-account.test';
        responseGate.complete();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        expect(requestCount, 1);
        expect(harness.service.reviewHistory, isEmpty);
        await harness.service.drainPendingHistoryWrites();
      } finally {
        if (!responseGate.isCompleted) responseGate.complete();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test(
    'closed history gate across an account epoch ignores retained client and prefs',
    () async {
      var allowed = true;
      final day = DateTime(2026, 5, 25, 9);
      final preferences = _TestPreferencesStore(
        initialData: {
          'flutter.ai_review_history': [jsonEncode(_storedWeeklyReview(day))],
        },
      );
      SharedPreferencesStorePlatform.instance = preferences;
      var requestCount = 0;
      final harness = _ServiceHarness(
        MockClient((request) async {
          requestCount++;
          return _successResponse();
        }),
        historyAccessAllowed: () => allowed,
      );
      try {
        await harness.service.loadFromStorage();
        expect(harness.service.reviewHistory, hasLength(1));
        expect(harness.service.weeklyReviewForDay(day), isNotNull);
        final retainedClient = harness.client;

        allowed = false;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(identical(harness.client, retainedClient), isTrue);
        expect(harness.service.reviewHistory, isEmpty);
        expect(harness.service.weeklyReviewForDay(day), isNull);

        await harness.service.loadFromStorage();
        await expectLater(
          _reviewProducers.first.invoke(harness.service),
          throwsA(isA<AiReviewDiscardedException>()),
        );
        await expectLater(
          harness.service.deleteReview('cached-weekly'),
          throwsA(isA<AiReviewDiscardedException>()),
        );
        await expectLater(
          harness.service.clearReviewHistory(),
          throwsA(isA<AiReviewDiscardedException>()),
        );

        expect(requestCount, 0);
        expect(harness.service.reviewHistory, isEmpty);
        expect(preferences.historySnapshots, isEmpty);
        final retained =
            (await preferences.getAll())['flutter.ai_review_history']
                as List<String>;
        expect(retained, hasLength(1));
        expect(
          AiReviewEntry.fromJson(jsonDecode(retained.single)).id,
          'cached-weekly',
        );
      } finally {
        harness.dispose();
      }
    },
  );

  for (final mutation in ['clear', 'append']) {
    test(
      'pending history load does not revive old rows after $mutation',
      () async {
        final day = DateTime(2026, 5, 25, 9);
        final preferences = _TestPreferencesStore(
          initialData: {
            'flutter.ai_review_history': [jsonEncode(_storedWeeklyReview(day))],
          },
        );
        SharedPreferencesStorePlatform.instance = preferences;
        var requestCount = 0;
        final harness = _ServiceHarness(
          MockClient((request) async {
            requestCount++;
            return _successResponse();
          }),
        );
        Future<void>? loading;
        Future<dynamic>? mutationFuture;
        try {
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getStringList('ai_review_history'), hasLength(1));
          preferences
            ..captureReadsBeforeGate = true
            ..getAllGate = Completer<void>()
            ..getAllStarted = Completer<void>();

          loading = harness.service.loadFromStorage();
          await preferences.getAllStarted!.future;
          if (mutation == 'clear') {
            mutationFuture = harness.service.clearReviewHistory();
            await mutationFuture;
            expect(harness.service.reviewHistory, isEmpty);
          } else {
            mutationFuture = _reviewProducers.first.invoke(harness.service);
            await mutationFuture;
            expect(requestCount, 1);
            expect(harness.service.reviewHistory, hasLength(1));
            expect(
              harness.service.reviewHistory.single.id,
              isNot('cached-weekly'),
            );
          }

          preferences.getAllGate!.complete();
          await loading;
          if (mutation == 'clear') {
            expect(harness.service.reviewHistory, isEmpty);
          } else {
            expect(harness.service.reviewHistory, hasLength(1));
            expect(
              harness.service.reviewHistory.single.id,
              isNot('cached-weekly'),
            );
          }
          final stored =
              (await preferences.getAll())['flutter.ai_review_history']
                  as List<String>?;
          if (mutation == 'clear') {
            expect(stored, isEmpty);
          } else {
            expect(stored, hasLength(1));
            expect(
              AiReviewEntry.fromJson(jsonDecode(stored!.single)).id,
              isNot('cached-weekly'),
            );
          }
        } finally {
          final gate = preferences.getAllGate;
          if (gate != null && !gate.isCompleted) gate.complete();
          await _ignoreFailure(loading);
          await _ignoreFailure(mutationFuture);
          harness.dispose();
        }
      },
    );
  }

  test(
    'history write drain orders immutable snapshots before account cleanup',
    () async {
      final preferences = _TestPreferencesStore()
        ..historyWriteGate = Completer<void>()
        ..historyWriteStarted = Completer<void>();
      SharedPreferencesStorePlatform.instance = preferences;
      final harness = _ServiceHarness(
        MockClient((request) async => _successResponse()),
      );
      Future<String>? appended;
      Future<void>? deleted;
      Future<void>? cleared;
      Future<void>? drained;
      try {
        appended = _reviewProducers.first.invoke(harness.service);
        await preferences.historyWriteStarted!.future;
        final id = harness.service.reviewHistory.single.id;
        deleted = harness.service.deleteReview(id);
        cleared = harness.service.clearReviewHistory();
        var drainFinished = false;
        drained = harness.service.drainPendingHistoryWrites().then((_) {
          drainFinished = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(drainFinished, isFalse);

        preferences.historyWriteGate!.complete();
        await appended;
        await deleted;
        await cleared;
        await drained;

        expect(preferences.historySnapshots, hasLength(3));
        expect(preferences.historySnapshots.first, hasLength(1));
        final first = AiReviewEntry.fromJson(
          jsonDecode(preferences.historySnapshots.first.single),
        );
        expect(first.id, id);
        expect(preferences.historySnapshots[1], isEmpty);
        expect(preferences.historySnapshots[2], isEmpty);
        expect(preferences.historyOperations, ['set:1', 'set:0', 'set:0']);

        await AccountLocalDataCleaner.clearSharedPreferences();
        final storedValues = await preferences.getAll();
        expect(storedValues.containsKey('flutter.ai_review_history'), isFalse);
        expect(preferences.historyOperations.last, 'remove');
      } finally {
        if (!preferences.historyWriteGate!.isCompleted) {
          preferences.historyWriteGate!.complete();
        }
        await _ignoreFailure(appended);
        await _ignoreFailure(deleted);
        await _ignoreFailure(cleared);
        await _ignoreFailure(drained);
        harness.dispose();
      }
    },
  );

  test(
    'account invalidation drains an active history write before physical cleanup',
    () async {
      final preferences = _TestPreferencesStore()
        ..historyWriteGate = Completer<void>()
        ..historyWriteStarted = Completer<void>();
      SharedPreferencesStorePlatform.instance = preferences;
      final harness = _ServiceHarness(
        MockClient((request) async => _successResponse()),
      );
      Future<String>? appended;
      Future<void>? callerObserved;
      Future<void>? drained;
      var serviceNotifications = 0;
      try {
        harness.service.addListener(() => serviceNotifications++);
        appended = _reviewProducers.first.invoke(harness.service);
        await preferences.historyWriteStarted!.future;
        callerObserved = expectLater(
          appended,
          throwsA(isA<AiReviewDiscardedException>()),
        );

        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        harness.service.resetLocalState();
        final notificationsBeforeStaleCompletion = serviceNotifications;
        var drainFinished = false;
        drained = harness.service.drainPendingHistoryWrites().then((_) {
          drainFinished = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(drainFinished, isFalse);

        preferences.historyWriteGate!.complete();
        await callerObserved;
        expect(harness.service.reviewHistory, isEmpty);
        expect(serviceNotifications, notificationsBeforeStaleCompletion);
        await drained;

        // The account cleanup removes the already-issued write only after the
        // service drain completes. No stale setter may run after this point.
        await AccountLocalDataCleaner.clearSharedPreferences();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('ai_review_history'), isNull);
        expect(
          (await preferences.getAll()).containsKey('flutter.ai_review_history'),
          isFalse,
        );
        expect(preferences.historyOperations, ['set:1', 'remove']);

        final mainSource = File('lib/main.dart').readAsStringSync();
        final serviceConstruction = mainSource.indexOf(
          'final aiService = AiService()',
        );
        final historyGate = mainSource.indexOf(
          '..historyAccessAllowed',
          serviceConstruction,
        );
        final followingService = mainSource.indexOf(
          'final appUpdate',
          serviceConstruction,
        );
        expect(serviceConstruction, greaterThanOrEqualTo(0));
        expect(historyGate, greaterThan(serviceConstruction));
        expect(historyGate, lessThan(followingService));

        final accountClear = mainSource.indexOf(
          'Future<void> clearAccountLocalData',
        );
        final accountInvalidation = mainSource.indexOf(
          'AccountLocalDataCleaner.invalidateInFlightAccountWrites();',
          accountClear,
        );
        final firstPreferencesPass = mainSource.indexOf(
          "'account prefs first pass'",
          accountClear,
        );
        final historyDrain = mainSource.indexOf(
          "'ai history writes'",
          accountClear,
        );
        final secondPreferencesPass = mainSource.indexOf(
          "'account prefs second pass'",
          accountClear,
        );
        expect(accountInvalidation, greaterThan(accountClear));
        expect(accountInvalidation, lessThan(firstPreferencesPass));
        expect(firstPreferencesPass, lessThan(historyDrain));
        expect(historyDrain, lessThan(secondPreferencesPass));
        expect(
          mainSource.substring(historyDrain, secondPreferencesPass),
          contains('aiService.drainPendingHistoryWrites'),
        );
      } finally {
        if (!preferences.historyWriteGate!.isCompleted) {
          preferences.historyWriteGate!.complete();
        }
        await _ignoreFailure(appended);
        await _ignoreFailure(callerObserved);
        await _ignoreFailure(drained);
        harness.dispose();
      }
    },
  );

  test(
    'failed active write is retained by drain after invalidation discards caller',
    () async {
      final preferences = _TestPreferencesStore()
        ..historyWriteGate = Completer<void>()
        ..historyWriteStarted = Completer<void>()
        ..historyWriteResults.add(false);
      SharedPreferencesStorePlatform.instance = preferences;
      final harness = _ServiceHarness(
        MockClient((request) async => _successResponse()),
      );
      Future<String>? appended;
      Future<void>? callerObserved;
      try {
        appended = _reviewProducers.first.invoke(harness.service);
        await preferences.historyWriteStarted!.future;
        callerObserved = expectLater(
          appended,
          throwsA(isA<AiReviewDiscardedException>()),
        );
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        preferences.historyWriteGate!.complete();

        await callerObserved;
        expect(harness.service.reviewHistory, isEmpty);
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          completes,
        );

        await AccountLocalDataCleaner.clearSharedPreferences();
        expect(
          (await preferences.getAll()).containsKey('flutter.ai_review_history'),
          isFalse,
        );
        expect(preferences.historyOperations, ['set:1', 'remove']);
      } finally {
        if (!preferences.historyWriteGate!.isCompleted) {
          preferences.historyWriteGate!.complete();
        }
        await _ignoreFailure(appended);
        await _ignoreFailure(callerObserved);
        harness.dispose();
      }
    },
  );

  test('false history writes fail the caller and drain exactly once', () async {
    final preferences = _TestPreferencesStore()
      ..returnFalseForHistoryWrite = true;
    SharedPreferencesStorePlatform.instance = preferences;
    final harness = _ServiceHarness(
      MockClient((request) async => _successResponse()),
    );
    try {
      Object? callerError;
      try {
        await _reviewProducers[1].invoke(harness.service);
      } catch (error) {
        callerError = error;
      }
      expect(callerError, isA<AiReviewHistoryWriteException>());
      await expectLater(
        harness.service.drainPendingHistoryWrites(),
        throwsA(same(callerError)),
      );
      await expectLater(harness.service.drainPendingHistoryWrites(), completes);
      expect(preferences.historySnapshots, hasLength(1));
      expect(
        (await preferences.getAll()).containsKey('flutter.ai_review_history'),
        isFalse,
      );
    } finally {
      harness.dispose();
    }
  });
}
