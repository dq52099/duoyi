import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/weekly_review_summary.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  test(
    'weekly review preserves complete English and Chinese model output',
    () async {
      final cases = [
        (
          locale: AppLocale.en,
          period: WeeklyReviewPeriod.thisWeek,
          label: 'this week',
          response: _englishReview('this week'),
        ),
        (
          locale: AppLocale.zh,
          period: WeeklyReviewPeriod.lastWeek,
          label: '上周',
          response: _chineseReview('上周'),
        ),
      ];

      for (final testCase in cases) {
        I18n.setLocale(testCase.locale);
        Map<String, dynamic>? requestBody;
        final harness = _Harness(
          MockClient((request) async {
            requestBody = _requestBody(request);
            return _response(testCase.response);
          }),
        );
        try {
          final review = await harness.service.weeklyReview(
            completedTodos: 2,
            totalTodos: 3,
            weeklyFocusMinutes: 45,
            habitStreak: 4,
            period: testCase.period,
            periodLabel: 'stale caller label',
            now: DateTime(2026, 10, 15, 9),
          );

          expect(review, testCase.response);
          _expectStructuredReview(
            review,
            isEnglish: testCase.locale == AppLocale.en,
            periodLabel: testCase.label,
          );
          expect(requestBody?['user'], contains(testCase.label));
          expect(
            harness.service.reviewHistory.single.weeklyStats?.period,
            testCase.period,
          );
        } finally {
          harness.dispose();
        }
      }
    },
  );

  test(
    'weekly review defaults to this week in the current English locale',
    () async {
      I18n.setLocale(AppLocale.en);
      Map<String, dynamic>? requestBody;
      final harness = _Harness(
        MockClient((request) async {
          requestBody = _requestBody(request);
          return _response(_englishReview('this week'));
        }),
      );
      try {
        final review = await harness.service.weeklyReview(
          completedTodos: 2,
          totalTodos: 3,
          weeklyFocusMinutes: 45,
          habitStreak: 4,
          now: DateTime(2026, 10, 15, 9),
        );

        expect(review, _englishReview('this week'));
        expect(requestBody?['system'], contains('this week review\nOverview:'));
        expect(requestBody?['user'], contains('Period: this week'));
        expect(
          harness.service.reviewHistory.single.weeklyStats?.period,
          WeeklyReviewPeriod.thisWeek,
        );
      } finally {
        harness.dispose();
      }
    },
  );

  test(
    'custom weekly label flattens protocol separators but persists literally',
    () async {
      I18n.setLocale(AppLocale.en);
      const customLabel = 'Sprint\r\nPlan\u2028Review';
      const protocolLabel = 'Sprint Plan Review';
      expect(customLabel, contains('\r'));
      expect(customLabel, contains('\n'));
      expect(customLabel, contains('\u2028'));
      Map<String, dynamic>? requestBody;
      final harness = _Harness(
        MockClient((request) async {
          requestBody = _requestBody(request);
          return _response(_englishReview(protocolLabel));
        }),
      );
      try {
        final review = await harness.service.weeklyReview(
          completedTodos: 2,
          totalTodos: 3,
          weeklyFocusMinutes: 45,
          habitStreak: 4,
          periodLabel: customLabel,
          now: DateTime(2026, 10, 15, 9),
        );

        expect(review, _englishReview(protocolLabel));
        expect(
          requestBody?['system'],
          contains('$protocolLabel review\nOverview:'),
        );
        expect(requestBody?['system'], isNot(contains('\r')));
        expect(requestBody?['system'], isNot(contains('\u2028')));
        expect(requestBody?['user'], contains('Period: $protocolLabel\n'));

        final stats = harness.service.reviewHistory.single.weeklyStats!;
        expect(stats.period, WeeklyReviewPeriod.custom);
        expect(stats.customPeriodLabel, customLabel);
        final statsRoundTrip = WeeklyReviewStats.fromJson(
          jsonDecode(jsonEncode(stats.toJson())),
        );
        expect(statsRoundTrip?.customPeriodLabel, customLabel);

        final preferences = await SharedPreferences.getInstance();
        final stored = preferences.getStringList('ai_review_history')!;
        final persistedEntry = AiReviewEntry.fromJson(
          jsonDecode(stored.single),
        );
        expect(persistedEntry.weeklyStats?.customPeriodLabel, customLabel);
      } finally {
        harness.dispose();
      }
    },
  );

  test(
    'weekly review falls back in the captured language for bad model output',
    () async {
      final cases = [
        (
          locale: AppLocale.en,
          period: WeeklyReviewPeriod.thisWeek,
          label: 'this week',
          response: _chineseReview('本周'),
        ),
        (
          locale: AppLocale.zh,
          period: WeeklyReviewPeriod.lastWeek,
          label: '上周',
          response: _englishReview('last week'),
        ),
        (
          locale: AppLocale.en,
          period: WeeklyReviewPeriod.lastWeek,
          label: 'last week',
          response: '| metric | value |\n| --- | --- |\n| tasks | 2 |',
        ),
        (
          locale: AppLocale.zh,
          period: WeeklyReviewPeriod.thisWeek,
          label: '本周',
          response: 'The review is not a valid ten line report.',
        ),
      ];

      for (final testCase in cases) {
        I18n.setLocale(testCase.locale);
        final requestStarted = Completer<void>();
        final responseGate = Completer<void>();
        final harness = _Harness(
          MockClient((request) async {
            if (!requestStarted.isCompleted) requestStarted.complete();
            await responseGate.future;
            return _response(testCase.response);
          }),
        );
        Future<String>? pending;
        try {
          pending = harness.service.weeklyReview(
            completedTodos: 2,
            totalTodos: 3,
            weeklyFocusMinutes: 45,
            habitStreak: 4,
            period: testCase.period,
            periodLabel: 'stale caller label',
            now: DateTime(2026, 10, 15, 9),
          );
          await requestStarted.future;
          I18n.setLocale(
            testCase.locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
          );
          responseGate.complete();
          final review = await pending;

          _expectStructuredReview(
            review,
            isEnglish: testCase.locale == AppLocale.en,
            periodLabel: testCase.label,
          );
          expect(review, isNot(testCase.response));
        } finally {
          if (!responseGate.isCompleted) responseGate.complete();
          await _ignoreFailure(pending);
          harness.dispose();
        }
      }
    },
  );

  test(
    'weekly period enums resolve by locale and custom labels stay literal',
    () async {
      final cases = [
        (
          appLocale: AppLocale.en,
          requestedPeriod: WeeklyReviewPeriod.thisWeek,
          suppliedLabel: 'caller label',
          resolvedLabel: 'this week',
        ),
        (
          appLocale: AppLocale.en,
          requestedPeriod: WeeklyReviewPeriod.lastWeek,
          suppliedLabel: 'caller label',
          resolvedLabel: 'last week',
        ),
        (
          appLocale: AppLocale.zh,
          requestedPeriod: WeeklyReviewPeriod.thisWeek,
          suppliedLabel: 'caller label',
          resolvedLabel: '本周',
        ),
        (
          appLocale: AppLocale.zh,
          requestedPeriod: WeeklyReviewPeriod.lastWeek,
          suppliedLabel: 'caller label',
          resolvedLabel: '上周',
        ),
        (
          appLocale: AppLocale.en,
          requestedPeriod: WeeklyReviewPeriod.custom,
          suppliedLabel: 'Sprint Q4 Ω',
          resolvedLabel: 'Sprint Q4 Ω',
        ),
      ];

      for (final testCase in cases) {
        I18n.setLocale(testCase.appLocale);
        final isEnglish = testCase.appLocale == AppLocale.en;
        final raw = isEnglish
            ? _englishReview(testCase.resolvedLabel)
            : _chineseReview(testCase.resolvedLabel);
        Map<String, dynamic>? requestBody;
        final harness = _Harness(
          MockClient((request) async {
            requestBody = _requestBody(request);
            return _response(raw);
          }),
        );
        try {
          final review = await harness.service.weeklyReview(
            completedTodos: 2,
            totalTodos: 3,
            weeklyFocusMinutes: 45,
            habitStreak: 4,
            period: testCase.requestedPeriod,
            periodLabel: testCase.suppliedLabel,
            now: DateTime(2026, 10, 15, 9),
          );

          expect(review, raw);
          _expectStructuredReview(
            review,
            isEnglish: isEnglish,
            periodLabel: testCase.resolvedLabel,
          );
          expect(requestBody?['user'], contains(testCase.resolvedLabel));
          expect(requestBody?['user'], isNot(contains('caller label')));
        } finally {
          harness.dispose();
        }
      }
    },
  );

  test(
    'weekly review keeps its call-start locale while the response is held',
    () async {
      final cases = [
        (
          callLocale: AppLocale.en,
          changedLocale: AppLocale.zh,
          label: 'this week',
          response: _englishReview('this week'),
        ),
        (
          callLocale: AppLocale.zh,
          changedLocale: AppLocale.en,
          label: '本周',
          response: _chineseReview('本周'),
        ),
      ];

      for (final testCase in cases) {
        I18n.setLocale(testCase.callLocale);
        final requestStarted = Completer<void>();
        final responseGate = Completer<void>();
        Map<String, dynamic>? requestBody;
        final harness = _Harness(
          MockClient((request) async {
            requestBody = _requestBody(request);
            if (!requestStarted.isCompleted) requestStarted.complete();
            await responseGate.future;
            return _response(testCase.response);
          }),
        );
        Future<String>? pending;
        try {
          pending = harness.service.weeklyReview(
            completedTodos: 2,
            totalTodos: 3,
            weeklyFocusMinutes: 45,
            habitStreak: 4,
            period: WeeklyReviewPeriod.thisWeek,
            now: DateTime(2026, 10, 15, 9),
          );
          await requestStarted.future;
          I18n.setLocale(testCase.changedLocale);
          responseGate.complete();

          expect(await pending, testCase.response);
          _expectStructuredReview(
            harness.service.reviewHistory.single.content,
            isEnglish: testCase.callLocale == AppLocale.en,
            periodLabel: testCase.label,
          );
          expect(requestBody?['system'], contains(testCase.label));
          expect(
            harness.service.reviewHistory.single.displaySummary,
            contains(
              testCase.changedLocale == AppLocale.en
                  ? 'this week summary'
                  : '本周数据',
            ),
          );
        } finally {
          if (!responseGate.isCompleted) responseGate.complete();
          await _ignoreFailure(pending);
          harness.dispose();
        }
      }
    },
  );

  test(
    'weekly review honors an explicit locale and reuses another-language cache verbatim',
    () async {
      I18n.setLocale(AppLocale.zh);
      final rawEnglish = _englishReview('last week');
      Map<String, dynamic>? requestBody;
      final explicitHarness = _Harness(
        MockClient((request) async {
          requestBody = _requestBody(request);
          return _response(rawEnglish);
        }),
      );
      try {
        final result = await explicitHarness.service.weeklyReview(
          completedTodos: 2,
          totalTodos: 3,
          weeklyFocusMinutes: 45,
          habitStreak: 4,
          period: WeeklyReviewPeriod.lastWeek,
          periodLabel: 'caller label',
          locale: AppLocale.en,
          now: DateTime(2026, 10, 15, 9),
        );
        expect(result, rawEnglish);
        expect(requestBody?['system'], contains('last week'));
        expect(
          explicitHarness.service.reviewHistory.single.weeklyStats?.period,
          WeeklyReviewPeriod.lastWeek,
        );
      } finally {
        explicitHarness.dispose();
      }

      final cachedAt = DateTime(2026, 10, 15, 9);
      const cachedBody = '本周回顾\n这个旧缓存必须逐字保留。';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_review_history': [
          jsonEncode({
            'id': 'cached-weekly-other-language',
            'createdAt': cachedAt.toIso8601String(),
            'content': cachedBody,
            'summary': '本周数据：完成 1 / 2 项待办，专注 30 分钟，习惯连续打卡 2 天。',
            'model': 'gpt-test',
            'kind': AiService.weeklyReviewKind,
          }),
        ],
      });
      I18n.setLocale(AppLocale.en);
      var requestCount = 0;
      final cacheHarness = _Harness(
        MockClient((request) async {
          requestCount++;
          return _response('unexpected request');
        }),
      );
      try {
        await cacheHarness.service.loadFromStorage();
        final cached = await cacheHarness.service.weeklyReview(
          completedTodos: 9,
          totalTodos: 9,
          weeklyFocusMinutes: 9,
          habitStreak: 9,
          period: WeeklyReviewPeriod.thisWeek,
          locale: AppLocale.en,
          now: cachedAt,
        );
        expect(cached, cachedBody);
        expect(cacheHarness.service.reviewHistory.single.content, cachedBody);
        expect(requestCount, 0);
      } finally {
        cacheHarness.dispose();
      }
    },
  );

  test(
    'report review captures default or explicit locale before awaiting AI',
    () async {
      final cases = [
        (
          appLocale: AppLocale.en,
          override: null,
          changedLocale: AppLocale.zh,
          expectedSummaryPrefix: 'Window 42 summary:',
          expectedPromptMarker: 'tasks done',
        ),
        (
          appLocale: AppLocale.zh,
          override: null,
          changedLocale: AppLocale.en,
          expectedSummaryPrefix: 'Window 42数据：',
          expectedPromptMarker: '待办',
        ),
        (
          appLocale: AppLocale.en,
          override: AppLocale.zh,
          changedLocale: AppLocale.en,
          expectedSummaryPrefix: 'Window 42数据：',
          expectedPromptMarker: '待办',
        ),
      ];

      for (final testCase in cases) {
        I18n.setLocale(testCase.appLocale);
        final requestStarted = Completer<void>();
        final responseGate = Completer<void>();
        Map<String, dynamic>? requestBody;
        final harness = _Harness(
          MockClient((request) async {
            requestBody = _requestBody(request);
            if (!requestStarted.isCompleted) requestStarted.complete();
            await responseGate.future;
            return _response('Generated report review');
          }),
        );
        Future<String>? pending;
        try {
          pending = harness.service.reviewFromReport(
            completedTodos: 2,
            totalTodos: 3,
            focusMinutes: 45,
            habitStreak: 4,
            habitCheckIns: 5,
            timeEntryMinutes: 90,
            periodLabel: 'Window 42',
            locale: testCase.override,
          );
          await requestStarted.future;
          I18n.setLocale(testCase.changedLocale);
          responseGate.complete();

          expect(await pending, 'Generated report review');
          expect(requestBody?['user'], contains(testCase.expectedPromptMarker));
          expect(requestBody?['user'], contains('Window 42'));
          expect(
            harness.service.reviewHistory.single.summary,
            startsWith(testCase.expectedSummaryPrefix),
          );
        } finally {
          if (!responseGate.isCompleted) responseGate.complete();
          await _ignoreFailure(pending);
          harness.dispose();
        }
      }
    },
  );

  test(
    'diary review localizes metadata from captured locale and keeps authored text and tags',
    () async {
      final cases = [
        (
          appLocale: AppLocale.en,
          override: null,
          changedLocale: AppLocale.zh,
          moodLabel: 'Good',
          weatherLabel: 'Sunny',
          otherMoodLabel: '开心',
          otherWeatherLabel: '晴',
        ),
        (
          appLocale: AppLocale.zh,
          override: null,
          changedLocale: AppLocale.en,
          moodLabel: '开心',
          weatherLabel: '晴',
          otherMoodLabel: 'Good',
          otherWeatherLabel: 'Sunny',
        ),
        (
          appLocale: AppLocale.en,
          override: AppLocale.zh,
          changedLocale: AppLocale.en,
          moodLabel: '开心',
          weatherLabel: '晴',
          otherMoodLabel: 'Good',
          otherWeatherLabel: 'Sunny',
        ),
      ];

      for (final testCase in cases) {
        I18n.setLocale(testCase.appLocale);
        final requestStarted = Completer<void>();
        final responseGate = Completer<void>();
        Map<String, dynamic>? requestBody;
        final harness = _Harness(
          MockClient((request) async {
            requestBody = _requestBody(request);
            if (!requestStarted.isCompleted) requestStarted.complete();
            await responseGate.future;
            return _response('Generated diary review');
          }),
        );
        Future<String>? pending;
        try {
          pending = harness.service.deepDiaryReview(
            entries: [
              DiaryEntry(
                id: 'locale-diary',
                date: DateTime(2026, 10, 15),
                content: 'Authored body remains: 中文原文.',
                mood: Mood.good,
                weather: Weather.sunny,
                tags: ['Raw-Tag-42'],
                createdAt: DateTime(2026, 10, 15, 20),
                updatedAt: DateTime(2026, 10, 15, 20),
              ),
            ],
            today: DateTime(2026, 10, 15),
            locale: testCase.override,
          );
          await requestStarted.future;
          I18n.setLocale(testCase.changedLocale);
          responseGate.complete();

          expect(await pending, 'Generated diary review');
          final userPrompt = requestBody?['user'] as String;
          expect(userPrompt, contains(testCase.moodLabel));
          expect(userPrompt, contains(testCase.weatherLabel));
          expect(userPrompt, isNot(contains(testCase.otherMoodLabel)));
          expect(userPrompt, isNot(contains(testCase.otherWeatherLabel)));
          expect(userPrompt, contains('Authored body remains: 中文原文.'));
          expect(userPrompt, contains('Raw-Tag-42'));
          final storedSummary = harness.service.reviewHistory.single.summary;
          expect(storedSummary, contains(testCase.moodLabel));
          expect(storedSummary, isNot(contains(testCase.otherMoodLabel)));
          expect(storedSummary, contains('Raw-Tag-42'));
        } finally {
          if (!responseGate.isCompleted) responseGate.complete();
          await _ignoreFailure(pending);
          harness.dispose();
        }
      }
    },
  );
}

class _Harness {
  _Harness(this.transport) : service = AiService() {
    service.attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'fixture-token',
        httpClient: transport,
      ),
    );
    service.updateFromServerConfig({
      'ai_enabled': true,
      'ai_model': 'gpt-test',
    });
  }

  final MockClient transport;
  final AiService service;

  void dispose() {
    service.dispose();
    transport.close();
  }
}

http.Response _response(String content) => http.Response(
  jsonEncode({'content': content}),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _requestBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

String _englishReview(String periodLabel) =>
    '$periodLabel review\n'
    'Overview: steady progress with useful reflection.\n'
    'Data\n'
    'Tasks: completed 2 of 3 planned tasks.\n'
    'Focus: 45 minutes with a consistent block.\n'
    'Habits: kept a four day streak.\n'
    'Observation: smaller goals helped sustain momentum.\n'
    'Next week\n'
    'Action 1: reserve one focus block each morning.\n'
    'Action 2: review the task list midweek.';

String _chineseReview(String periodLabel) =>
    '$periodLabel回顾\n'
    '总览：整体推进稳定，复盘也很及时。\n'
    '数据\n'
    '待办：完成 2 / 3 项，继续聚焦关键任务。\n'
    '专注：45 分钟，保持固定专注窗口。\n'
    '习惯：连续打卡 4 天，节奏不错。\n'
    '观察：拆小目标有助于持续推进。\n'
    '下周行动\n'
    '行动一：每天上午预留一段专注时间。\n'
    '行动二：周中检查一次待办清单。';

void _expectStructuredReview(
  String review, {
  required bool isEnglish,
  required String periodLabel,
}) {
  final lines = review.split('\n');
  expect(lines, hasLength(10));
  if (isEnglish) {
    expect(lines.first, '$periodLabel review');
    expect(review, contains('\nOverview:'));
    expect(review, contains('\nData\n'));
    expect(review, contains('\nTasks:'));
    expect(review, contains('\nFocus:'));
    expect(review, contains('\nHabits:'));
    expect(review, contains('\nObservation:'));
    expect(review, contains('\nNext week\n'));
    expect(review, contains('\nAction 1:'));
    expect(review, contains('\nAction 2:'));
  } else {
    expect(lines.first, '$periodLabel回顾');
    expect(review, contains('\n总览：'));
    expect(review, contains('\n数据\n'));
    expect(review, contains('\n待办：'));
    expect(review, contains('\n专注：'));
    expect(review, contains('\n习惯：'));
    expect(review, contains('\n观察：'));
    expect(review, contains('\n下周行动\n'));
    expect(review, contains('\n行动一：'));
    expect(review, contains('\n行动二：'));
  }
}

Future<void> _ignoreFailure(Future<dynamic>? future) async {
  if (future == null) return;
  try {
    await future;
  } catch (_) {}
}
