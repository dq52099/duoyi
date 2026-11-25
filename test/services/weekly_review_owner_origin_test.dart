// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:test/test.dart';

const _historyPlatformKey = 'flutter.ai_review_history';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'weekly review is discarded when its owner becomes stale before the response returns',
    () async {
      final store = _HistoryStore();
      SharedPreferencesStorePlatform.instance = store;
      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      var requestCount = 0;
      final harness = _Harness(
        MockClient((request) async {
          requestCount++;
          if (!requestStarted.isCompleted) requestStarted.complete();
          await responseGate.future;
          return _successResponse();
        }),
      );
      var ownerIsCurrent = true;
      Future<String>? pending;
      try {
        await harness.service.loadFromStorage();
        pending = _weeklyReview(
          harness.service,
          now: DateTime(2026, 10, 1, 9),
          ownerIsCurrent: () => ownerIsCurrent,
        );
        await requestStarted.future;

        ownerIsCurrent = false;
        responseGate.complete();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        await harness.service.drainPendingHistoryWrites();

        expect(requestCount, 1);
        expect(harness.service.reviewHistory, isEmpty);
        expect(store.historySnapshots, isEmpty);
        expect(await store.storedReviewIds(), isEmpty);
      } finally {
        if (!responseGate.isCompleted) responseGate.complete();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test(
    'owner invalidation during a held write removes only the provisional row and repairs storage',
    () async {
      final unrelated = _savedEntry(
        id: 'unrelated-current-entry',
        createdAt: DateTime(2026, 9, 20, 12),
      );
      final store = _HistoryStore([unrelated])..holdNextHistoryWrite();
      SharedPreferencesStorePlatform.instance = store;
      var requestCount = 0;
      final harness = _Harness(
        MockClient((request) async {
          requestCount++;
          return _successResponse();
        }),
      );
      var ownerIsCurrent = true;
      Future<String>? pending;
      try {
        await harness.service.loadFromStorage();
        pending = _weeklyReview(
          harness.service,
          now: DateTime(2026, 10, 1, 9),
          ownerIsCurrent: () => ownerIsCurrent,
        );
        await store.historyWriteStarted.future;

        final provisionalId = DateTime(
          2026,
          10,
          1,
          9,
        ).millisecondsSinceEpoch.toString();
        expect(harness.service.reviewHistory.map((entry) => entry.id), [
          provisionalId,
          unrelated.id,
        ]);
        expect(store.historySnapshotIds, [
          [provisionalId, unrelated.id],
        ]);

        ownerIsCurrent = false;
        store.releaseHistoryWrite();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        await harness.service.drainPendingHistoryWrites();

        expect(requestCount, 1);
        expect(harness.service.reviewHistory.map((entry) => entry.id), [
          unrelated.id,
        ]);
        expect(store.historySnapshotIds, [
          [provisionalId, unrelated.id],
          [unrelated.id],
        ]);
        expect(await store.storedReviewIds(), [unrelated.id]);
      } finally {
        store.releaseHistoryWrite();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test(
    'cancelled 51st owned review restores the full saved history in order',
    () async {
      final originals = List.generate(
        50,
        (index) => _savedEntry(
          id: 'saved-review-$index',
          createdAt: DateTime(2026, 1, 1).add(Duration(days: index)),
        ),
      );
      final originalIds = originals.map((entry) => entry.id).toList();
      final store = _HistoryStore(originals)..holdNextHistoryWrite();
      SharedPreferencesStorePlatform.instance = store;
      final harness = _Harness(
        MockClient((request) async => _successResponse()),
      );
      var ownerIsCurrent = true;
      Future<String>? pending;
      try {
        await harness.service.loadFromStorage();
        final reviewAt = DateTime(2026, 10, 1, 9);
        final provisionalId = reviewAt.millisecondsSinceEpoch.toString();
        pending = _weeklyReview(
          harness.service,
          now: reviewAt,
          ownerIsCurrent: () => ownerIsCurrent,
        );
        await store.historyWriteStarted.future;

        expect(harness.service.reviewHistory.map((entry) => entry.id), [
          provisionalId,
          ...originalIds,
        ]);
        expect(store.historySnapshotIds, [
          [provisionalId, ...originalIds.take(49)],
        ]);

        ownerIsCurrent = false;
        store.releaseHistoryWrite();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));
        await harness.service.drainPendingHistoryWrites();

        expect(
          harness.service.reviewHistory.map((entry) => entry.id),
          originalIds,
        );
        expect(store.historySnapshotIds, [
          [provisionalId, ...originalIds.take(49)],
          originalIds,
        ]);
        expect(await store.storedReviewIds(), originalIds);
      } finally {
        store.releaseHistoryWrite();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  test(
    'failed owner rollback write keeps current rows dirty and drain reports it',
    () async {
      final unrelatedWeekly = _savedEntry(
        id: 'current-weekly-review',
        createdAt: DateTime(2026, 9, 20, 12),
        kind: AiService.weeklyReviewKind,
      );
      final store = _HistoryStore([unrelatedWeekly])
        ..historyWriteResults.addAll([true, false])
        ..holdNextHistoryWrite();
      SharedPreferencesStorePlatform.instance = store;
      final harness = _Harness(
        MockClient((request) async => _successResponse()),
      );
      var ownerIsCurrent = true;
      Future<String>? pending;
      try {
        await harness.service.loadFromStorage();
        final reviewAt = DateTime(2026, 10, 1, 9);
        final provisionalId = reviewAt.millisecondsSinceEpoch.toString();
        pending = _weeklyReview(
          harness.service,
          now: reviewAt,
          ownerIsCurrent: () => ownerIsCurrent,
        );
        await store.historyWriteStarted.future;

        ownerIsCurrent = false;
        store.releaseHistoryWrite();
        await expectLater(pending, throwsA(isA<AiReviewDiscardedException>()));

        expect(harness.service.reviewHistory.map((entry) => entry.id), [
          unrelatedWeekly.id,
        ]);
        expect(
          harness.service.weeklyReviewForDay(unrelatedWeekly.createdAt),
          isNull,
          reason:
              'the retained row is dirty until its corrective write succeeds',
        );
        expect(store.historySnapshotIds, [
          [provisionalId, unrelatedWeekly.id],
          [unrelatedWeekly.id],
        ]);
        expect(await store.storedReviewIds(), [
          provisionalId,
          unrelatedWeekly.id,
        ]);
        await expectLater(
          harness.service.drainPendingHistoryWrites(),
          throwsA(isA<AiReviewHistoryWriteException>()),
        );
        expect(harness.service.reviewHistory.map((entry) => entry.id), [
          unrelatedWeekly.id,
        ]);
      } finally {
        store.releaseHistoryWrite();
        await _ignoreFailure(pending);
        harness.dispose();
      }
    },
  );

  for (final boundary in ['local reset', 'account invalidation']) {
    test(
      'held stale weekly write cannot repair over new history after $boundary',
      () async {
        final store = _HistoryStore()..holdNextHistoryWrite();
        SharedPreferencesStorePlatform.instance = store;
        var requestCount = 0;
        final secondRequestStarted = Completer<void>();
        final harness = _Harness(
          MockClient((request) async {
            requestCount++;
            if (requestCount == 2 && !secondRequestStarted.isCompleted) {
              secondRequestStarted.complete();
            }
            return _successResponse();
          }),
        );
        var oldOwnerIsCurrent = true;
        Future<String>? staleReview;
        Future<String>? currentReview;
        try {
          await harness.service.loadFromStorage();
          final staleAt = DateTime(2026, 10, 1, 9);
          final currentAt = DateTime(2026, 10, 2, 9);
          final staleId = staleAt.millisecondsSinceEpoch.toString();
          final currentId = currentAt.millisecondsSinceEpoch.toString();

          staleReview = _weeklyReview(
            harness.service,
            now: staleAt,
            ownerIsCurrent: () => oldOwnerIsCurrent,
          );
          await store.historyWriteStarted.future;
          expect(harness.service.reviewHistory.map((entry) => entry.id), [
            staleId,
          ]);

          oldOwnerIsCurrent = false;
          if (boundary == 'local reset') {
            harness.service.resetLocalState();
          } else {
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          }
          expect(harness.service.reviewHistory, isEmpty);

          currentReview = _weeklyReview(
            harness.service,
            now: currentAt,
            ownerIsCurrent: () => true,
          );
          await secondRequestStarted.future;
          for (
            var attempt = 0;
            attempt < 20 &&
                !harness.service.reviewHistory.any(
                  (entry) => entry.id == currentId,
                );
            attempt++
          ) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(harness.service.reviewHistory.map((entry) => entry.id), [
            currentId,
          ]);

          store.releaseHistoryWrite();
          await expectLater(
            staleReview,
            throwsA(isA<AiReviewDiscardedException>()),
          );
          expect(await currentReview, isNotEmpty);
          await harness.service.drainPendingHistoryWrites();

          expect(requestCount, 2);
          expect(harness.service.reviewHistory.map((entry) => entry.id), [
            currentId,
          ]);
          expect(store.historySnapshotIds, [
            [staleId],
            [currentId],
          ]);
          expect(await store.storedReviewIds(), [currentId]);
        } finally {
          store.releaseHistoryWrite();
          await _ignoreFailure(staleReview);
          await _ignoreFailure(currentReview);
          harness.dispose();
        }
      },
    );
  }
}

Future<String> _weeklyReview(
  AiService service, {
  required DateTime now,
  required bool Function() ownerIsCurrent,
}) => service.weeklyReview(
  completedTodos: 2,
  totalTodos: 3,
  weeklyFocusMinutes: 45,
  habitStreak: 4,
  periodLabel: '本周',
  ownerIsCurrent: ownerIsCurrent,
  now: now,
);

AiReviewEntry _savedEntry({
  required String id,
  required DateTime createdAt,
  String kind = 'statistics_report',
}) => AiReviewEntry(
  id: id,
  createdAt: createdAt,
  content: 'Existing unrelated local review',
  summary: 'Saved report summary',
  kind: kind,
);

Map<String, Object> _encodeEntry(AiReviewEntry entry) => {
  'id': entry.id,
  'createdAt': entry.createdAt.toIso8601String(),
  'content': entry.content,
  'summary': entry.summary,
  'model': entry.model,
  'kind': entry.kind,
};

http.Response _successResponse() => http.Response(
  jsonEncode({'content': '稳定的模型回顾内容。继续保持节奏。'}),
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> _ignoreFailure(Future<dynamic>? future) async {
  if (future == null) return;
  try {
    await future;
  } catch (_) {}
}

class _Harness {
  _Harness(this.transport)
    : service = AiService(),
      client = ApiClient(
        baseUrl: 'https://weekly-review-owner.test',
        token: 'owner-origin-test-token',
        httpClient: transport,
      ) {
    service.attachClient(client);
    service.updateFromServerConfig({
      'ai_enabled': true,
      'ai_model': 'owner-origin-test-model',
    });
  }

  final MockClient transport;
  final AiService service;
  final ApiClient client;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    service.dispose();
    transport.close();
  }
}

class _HistoryStore extends InMemorySharedPreferencesStore {
  _HistoryStore([List<AiReviewEntry> initialEntries = const []])
    : super.withData({
        if (initialEntries.isNotEmpty)
          _historyPlatformKey: initialEntries
              .map((entry) => jsonEncode(_encodeEntry(entry)))
              .toList(),
      });

  final List<List<String>> historySnapshots = [];
  final List<bool> historyWriteResults = [];
  Completer<void> historyWriteStarted = Completer<void>();
  Completer<void> _historyWriteGate = Completer<void>();
  bool _holdNextHistoryWrite = false;

  List<List<String>> get historySnapshotIds => historySnapshots
      .map(
        (snapshot) => snapshot
            .map((raw) => AiReviewEntry.fromJson(jsonDecode(raw)).id)
            .toList(),
      )
      .toList();

  void holdNextHistoryWrite() {
    historyWriteStarted = Completer<void>();
    _historyWriteGate = Completer<void>();
    _holdNextHistoryWrite = true;
  }

  void releaseHistoryWrite() {
    if (!_historyWriteGate.isCompleted) _historyWriteGate.complete();
  }

  Future<List<String>> storedReviewIds() async {
    final stored = (await getAll())[_historyPlatformKey];
    if (stored is! List<String>) return const [];
    return stored
        .map((raw) => AiReviewEntry.fromJson(jsonDecode(raw)).id)
        .toList();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (valueType == 'StringList' && key == _historyPlatformKey) {
      final snapshot = List<String>.from(value as List<String>);
      historySnapshots.add(snapshot);
      if (_holdNextHistoryWrite) {
        _holdNextHistoryWrite = false;
        if (!historyWriteStarted.isCompleted) historyWriteStarted.complete();
        await _historyWriteGate.future;
      }
      if (historyWriteResults.isNotEmpty && !historyWriteResults.removeAt(0)) {
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
