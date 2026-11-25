import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _boundaryKey = ValueKey('weekly_review_capture');

const _openMineKey = ValueKey<String>('weekly_review_test_open_mine');
const _reviewToggleKey = ValueKey<String>('mine_ai_review_toggle');
const _reviewContentKey = ValueKey<String>('mine_ai_review_content');
const _reviewBody = '本周回顾\n总览：这段缓存内容在切换语言后保持原样。';
const _legacySummary = '本周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'cached weekly review localizes its stats while retaining expanded content',
    (tester) async {
      _configureViewport(tester);
      final now = DateTime.now();
      final harness = await _buildHarness(
        now: now,
        cachedReview: true,
        client: MockClient((request) async {
          fail('Opening a cached review must not issue an AI request.');
        }),
      );
      I18n.setLocale(AppLocale.en);

      try {
        await _pumpHarness(tester, harness);
        await _openMineRoute(tester);

        _expectStatsSummary(
          tester,
          now,
          completed: 3,
          total: 5,
          focus: 60,
          streak: 4,
        );
        _expectGenerationDisabled(tester);
        expect(harness.ai.weeklyReviewForDay(now)?.content, _reviewBody);

        await tester.tap(find.byKey(_reviewToggleKey));
        await tester.pumpAndSettle();
        expect(_reviewBodyText(tester), _reviewBody);

        for (final locale in [
          AppLocale.zh,
          AppLocale.en,
          AppLocale.zh,
          AppLocale.en,
        ]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          _expectStatsSummary(
            tester,
            now,
            completed: 3,
            total: 5,
            focus: 60,
            streak: 4,
          );
          _expectGenerationDisabled(tester);
          expect(_reviewBodyText(tester), _reviewBody);
        }
      } finally {
        await _unmountHarness(tester, harness);
      }
    },
  );

  testWidgets(
    'reopened same-day cache keeps saved stats after providers change',
    (tester) async {
      _configureViewport(tester);
      final now = DateTime.now();
      final harness = await _buildHarness(
        now: now,
        cachedReview: true,
        client: MockClient((request) async {
          fail('Reopening a cached review must not issue an AI request.');
        }),
      );
      I18n.setLocale(AppLocale.en);

      try {
        await _pumpHarness(tester, harness);
        await _openMineRoute(tester);
        _expectStatsSummary(
          tester,
          now,
          completed: 3,
          total: 5,
          focus: 60,
          streak: 4,
        );
        _expectGenerationDisabled(tester);
        await tester.tap(find.byKey(_reviewToggleKey));
        await tester.pumpAndSettle();
        expect(_reviewBodyText(tester), _reviewBody);

        Navigator.of(tester.element(find.byType(MineScreen))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(MineScreen), findsNothing);

        await harness.todos.addTodo(
          TodoItem(
            id: 'after-cached-review',
            title: 'Added after the saved review',
            date: now,
            isCompleted: true,
            completedAt: now,
          ),
        );
        await harness.pomodoros.debugAddSessionsForTest([
          PomodoroSession(
            id: 'after-cached-review',
            startTime: now.subtract(const Duration(minutes: 90)),
            endTime: now,
            durationSeconds: 90 * 60,
            type: PomodoroType.focus,
          ),
        ]);
        await harness.habits.addHabit(
          Habit(
            id: 'after-cached-review',
            name: 'Added after the saved review',
            currentStreak: 9,
            bestStreak: 9,
            startDate: now.subtract(const Duration(days: 9)),
          ),
        );
        expect(harness.todos.completedTodos, hasLength(1));
        expect(harness.pomodoros.sessions, hasLength(1));
        expect(harness.habits.longestCurrentStreak, 9);

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        await _openMineRoute(tester);

        _expectStatsSummary(
          tester,
          now,
          completed: 3,
          total: 5,
          focus: 60,
          streak: 4,
        );
        _expectGenerationDisabled(tester);
        await tester.tap(find.byKey(_reviewToggleKey));
        await tester.pumpAndSettle();
        expect(_reviewBodyText(tester), _reviewBody);
      } finally {
        await _unmountHarness(tester, harness);
      }
    },
  );

  testWidgets(
    'fresh weekly review stats follow later locale changes without changing AI content',
    (tester) async {
      _configureViewport(tester);
      final now = DateTime.now();
      var requestCount = 0;
      final harness = await _buildHarness(
        now: now,
        cachedReview: false,
        client: MockClient((request) async {
          requestCount++;
          expect(request.url.path, '/api/ai/chat');
          final requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          final userPrompt = requestBody['user'] as String;
          final isEnglish = userPrompt.startsWith('Period: ');
          final period = userPrompt
              .split('\n')
              .first
              .replaceFirst(isEnglish ? 'Period: ' : '周期：', '');
          return http.Response(
            jsonEncode({
              'content': _mockStructuredReview(period, isEnglish: isEnglish),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      I18n.setLocale(AppLocale.en);

      try {
        await _pumpHarness(tester, harness);
        await _openMineRoute(tester);
        final generateButton = find.text(I18n.tr('mine.ai.generate'));
        await tester.ensureVisible(generateButton);
        await tester.tap(generateButton);
        await tester.pumpAndSettle();

        expect(requestCount, 1);
        _expectStatsSummary(
          tester,
          now,
          completed: 0,
          total: 0,
          focus: 0,
          streak: 0,
        );
        _expectGenerationDisabled(tester);
        final generatedContent = _reviewBodyText(tester);
        expect(generatedContent, contains('fixture review text'));

        for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          _expectStatsSummary(
            tester,
            now,
            completed: 0,
            total: 0,
            focus: 0,
            streak: 0,
          );
          _expectGenerationDisabled(tester);
          expect(_reviewBodyText(tester), generatedContent);
        }
        expect(requestCount, 1);
      } finally {
        await _unmountHarness(tester, harness);
      }
    },
  );

  testWidgets(
    'Mine rejects cached review across gated consecutive auth changes',
    (tester) async {
      _configureViewport(tester);
      final harness = await _buildHarness(
        now: DateTime.now(),
        cachedReview: true,
        client: MockClient((_) async => throw StateError('must not request')),
      );
      try {
        await _pumpHarness(tester, harness);
        await _openMineRoute(tester);
        await tester.tap(find.byKey(_reviewToggleKey));
        await tester.pumpAndSettle();
        expect(_reviewBodyText(tester), _reviewBody);
        var allowed = false;
        harness.ai.historyAccessAllowed = () => allowed;
        harness.auth.changeSession();
        await tester.pumpAndSettle();
        harness.auth.changeSession();
        await tester.pumpAndSettle();
        allowed = true;
        harness.ai.updateFromServerConfig({'ai_enabled': true});
        await tester.pumpAndSettle();
        expect(find.text(_legacySummary), findsNothing);
        expect(find.byKey(_reviewToggleKey), findsNothing);
        await tester.tap(find.text(I18n.tr('mine.ai.generate')));
        await tester.pumpAndSettle();
        expect(find.byKey(_reviewToggleKey), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmountHarness(tester, harness);
      }
    },
  );

  testWidgets('Mine resets presentation on equal-generation auth replacement', (
    tester,
  ) async {
    _configureViewport(tester);
    final harness = await _buildHarness(
      now: DateTime.now(),
      cachedReview: true,
      client: MockClient((_) async => throw StateError('must not request')),
    );
    try {
      await _pumpHarness(tester, harness);
      await _openMineRoute(tester);
      await tester.tap(find.byKey(_reviewToggleKey));
      await tester.pumpAndSettle();
      harness.replaceAuth();
      await tester.pumpAndSettle();
      expect(find.byKey(_reviewToggleKey), findsNothing);
      expect(find.text(_legacySummary), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountHarness(tester, harness);
    }
  });

  testWidgets(
    'Mine stale rendered Generate rejects same-service history reset',
    (tester) async {
      _configureViewport(tester);
      var requests = 0;
      final harness = await _buildHarness(
        now: DateTime.now(),
        cachedReview: false,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      try {
        await _pumpHarness(tester, harness);
        await _openMineRoute(tester);
        final oldGenerate = tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, I18n.tr('mine.ai.generate')),
            )
            .onPressed!;
        harness.ai.resetLocalState();
        oldGenerate();
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmountHarness(tester, harness);
      }
    },
  );

  testWidgets('Mine ignores held generation completed after auth replacement', (
    tester,
  ) async {
    _configureViewport(tester);
    final response = Completer<http.Response>();
    var requests = 0;
    final harness = await _buildHarness(
      now: DateTime.now(),
      cachedReview: false,
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    try {
      await _pumpHarness(tester, harness);
      await _openMineRoute(tester);
      await tester.tap(find.text(I18n.tr('mine.ai.generate')));
      await tester.pump();
      expect(requests, 1);
      harness.replaceAuth();
      await tester.pump();
      response.complete(
        http.Response(
          jsonEncode({'content': _mockStructuredReview('本周')}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('fixture review text'), findsNothing);
      expect(find.byKey(_reviewToggleKey), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountHarness(tester, harness);
    }
  });

  for (final locale in AppLocale.values) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'weekly review controls keep 44dp targets ${locale.name} ${scale}x',
        (tester) async {
          final capture =
              Platform.environment['DUOYI_CAPTURE_WEEKLY_REVIEW_CONTROLS'] ==
              '1';
          if (capture) await loadWeeklyReviewScreenshotFonts();
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          final harness = await _buildHarness(
            now: DateTime.now(),
            cachedReview: true,
            client: MockClient((_) async {
              fail('Expanding cached review must not issue an AI request.');
            }),
          );
          harness.textScale = scale;
          I18n.setLocale(locale);
          try {
            await _pumpHarness(tester, harness);
            await _openMineRoute(tester);
            final header = find.byKey(_reviewToggleKey);
            final expand = find.widgetWithText(
              TextButton,
              I18n.tr('mine.ai.expand_full'),
            );
            for (final control in [header, expand]) {
              await tester.ensureVisible(control);
              await tester.pumpAndSettle();
              final size = tester.getSize(control);
              expect(size.width, greaterThanOrEqualTo(44));
              expect(size.height, greaterThanOrEqualTo(44));
              final node = tester.getSemantics(control);
              expect(node.rect.width, greaterThanOrEqualTo(44));
              expect(node.rect.height, greaterThanOrEqualTo(44));
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue,
              );
            }
            if (capture) {
              await tester.ensureVisible(
                find.text(I18n.tr('mine.ai.review_title')),
              );
              await tester.pumpAndSettle();
              await _captureGeneratedBody(
                tester,
                'weekly-review-controls-${locale.name}-${scale}x',
                directory:
                    'evidence/screenshots/settings-nav-feedback-20261016',
              );
            }
            await tester.tap(expand);
            await tester.pumpAndSettle();
            expect(_reviewBodyText(tester), _reviewBody);
            expect(find.byTooltip(I18n.tr('mine.ai.collapse')), findsOneWidget);
            await tester.ensureVisible(header);
            await tester.pumpAndSettle();
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: find.byKey(_reviewContentKey),
                matching: find.byType(Text),
              ),
              findsNothing,
            );
            expect(expand, findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await _unmountHarness(tester, harness);
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final locale in [AppLocale.zh, AppLocale.en]) {
    for (final size in [const Size(320, 844), const Size(568, 320)]) {
      testWidgets(
        'Mine weekly review layout ${locale.name} ${size.width.toInt()} 1.6x',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          if (Platform.environment['DUOYI_CAPTURE_WEEKLY_REVIEW'] == '1') {
            await loadWeeklyReviewScreenshotFonts();
          }
          final harness = await _buildHarness(
            now: DateTime.now(),
            cachedReview: true,
            client: MockClient(
              (_) async => throw StateError('must not request'),
            ),
          );
          harness.textScale = 1.6;
          I18n.setLocale(locale);
          try {
            await _pumpHarness(tester, harness);
            await _openMineRoute(tester);
            await tester.ensureVisible(find.byKey(_reviewToggleKey));
            await tester.tap(find.byKey(_reviewToggleKey));
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.text(I18n.tr('mine.ai.review_title')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (Platform.environment['DUOYI_CAPTURE_WEEKLY_REVIEW'] == '1') {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(_boundaryKey),
                );
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'evidence/screenshots/weekly-review-20261015/mine-${locale.name}-${size.width.toInt()}x${size.height.toInt()}-1.6.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          } finally {
            await _unmountHarness(tester, harness);
          }
        },
      );
    }
  }
  for (final locale in [AppLocale.zh, AppLocale.en]) {
    for (final size in [const Size(320, 844), const Size(568, 320)]) {
      _registerGeneratedLayoutCase(locale, size, malformed: false);
    }
  }
  _registerGeneratedLayoutCase(
    AppLocale.en,
    const Size(320, 844),
    malformed: true,
  );
}

void _registerGeneratedLayoutCase(
  AppLocale locale,
  Size size, {
  required bool malformed,
}) {
  testWidgets(
    'generated weekly body ${locale.name} ${size.width.toInt()} fallback=$malformed at 1.6x',
    (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture =
          Platform.environment['DUOYI_CAPTURE_AI_GENERATION'] == '1';
      if (capture) await loadWeeklyReviewScreenshotFonts();
      I18n.setLocale(locale);
      String? raw;
      var requests = 0;
      final harness = await _buildHarness(
        now: DateTime.now(),
        cachedReview: false,
        client: MockClient((request) async {
          requests++;
          final prompt =
              (jsonDecode(request.body) as Map<String, dynamic>)['user']
                  as String;
          final period = prompt
              .split('\n')
              .first
              .replaceFirst(locale == AppLocale.en ? 'Period: ' : '周期：', '');
          raw = malformed
              ? 'Malformed response'
              : _longStructuredReview(period, locale);
          return http.Response(
            jsonEncode({'content': raw}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      harness.textScale = 1.6;
      try {
        await _pumpHarness(tester, harness);
        await _openMineRoute(tester);
        final generate = find.text(I18n.tr('mine.ai.generate'));
        await tester.ensureVisible(generate);
        await tester.tap(generate);
        await tester.pumpAndSettle();
        final content = _reviewBodyText(tester);
        expect(content.split('\n'), hasLength(10));
        expect(content, malformed ? isNot(raw) : raw);
        expect(
          content,
          matches(
            locale == AppLocale.en
                ? RegExp(r'^(this|last) week review\n')
                : RegExp(r'^(本周|上周)回顾\n'),
          ),
        );
        final body = find
            .descendant(
              of: find.byKey(_reviewContentKey),
              matching: find.byType(Text),
            )
            .first;
        await Scrollable.ensureVisible(tester.element(body), alignment: 0);
        await tester.pumpAndSettle();
        final stem =
            '${locale.name}-${size.width.toInt()}x${size.height.toInt()}-${malformed ? 'fallback' : 'valid'}';
        if (capture) await _captureGeneratedBody(tester, '$stem-top');
        await Scrollable.ensureVisible(tester.element(body), alignment: 1);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(body);
        final lastLine = content.lastIndexOf('\n') + 1;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: lastLine, extentOffset: content.length),
        );
        expect(boxes, isNotEmpty);
        final lastBox = boxes.last.toRect().shift(
          paragraph.localToGlobal(Offset.zero),
        );
        expect(lastBox.bottom, lessThanOrEqualTo(size.height + 1));
        expect(lastBox.top, greaterThanOrEqualTo(0));
        if (capture) await _captureGeneratedBody(tester, '$stem-tail');
        for (final changed in [
          locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
          locale,
        ]) {
          I18n.setLocale(changed);
          await tester.pumpAndSettle();
          expect(_reviewBodyText(tester), content);
          _expectGenerationDisabled(tester);
        }
        expect(requests, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmountHarness(tester, harness);
      }
    },
  );
}

Future<void> _captureGeneratedBody(
  WidgetTester tester,
  String name, {
  String directory = 'evidence/screenshots/ai-generation-locale-20261015',
}) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

String _longStructuredReview(String period, AppLocale locale) =>
    locale == AppLocale.en
    ? '$period review\n'
          'Overview: A manageable routine leaves enough room to finish priority tasks and review what needs attention next.\n'
          'Data\nTasks: no tasks recorded; choose one clear priority before adding more work to the list.\n'
          'Focus: no minutes recorded; reserve a short daily window with fewer interruptions and a clear stopping point.\n'
          'Habits: no streak recorded; choose one small activity that fits comfortably into an existing daily routine.\n'
          'Observation: Keep the first step small enough to repeat and use recorded activity to guide the next adjustment.\n'
          'Next week\nAction 1: Reserve a regular focus window and prepare everything needed before the session starts.\n'
          'Action 2: Break down one large task, finish its first step, and review the remaining work at the end of the week.'
    : '$period回顾\n'
          '总览：先安排容易完成的关键任务，为日常休息和每周复盘保留充足空间。\n'
          '数据\n待办：暂无计划项，先选择一个明确的重点任务，再逐步补充后续安排。\n'
          '专注：暂无专注记录，安排固定时段并减少打扰，结束后及时记录进展。\n'
          '习惯：暂无连续记录，把一个简单行动放进已有日常流程，降低启动难度。\n'
          '观察：先从能够重复的小行动开始，根据真实记录调整节奏，避免同时追求太多目标。\n'
          '下周行动\n行动一：保留固定专注时段，开始前准备好所需资料，并明确本次结束条件。\n'
          '行动二：拆解一个较大的任务，完成第一步，并在周末复盘剩余工作。';

void _configureViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_WeeklyReviewHarness> _buildHarness({
  required DateTime now,
  required bool cachedReview,
  required http.Client client,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (cachedReview)
      'ai_review_history': [
        jsonEncode({
          'id': 'same-day-weekly-review',
          'createdAt': now.toIso8601String(),
          'content': _reviewBody,
          'summary': _legacySummary,
          'model': 'fixture-model',
          'kind': AiService.weeklyReviewKind,
        }),
      ],
  });

  final ai = AiService();
  ai.attachClient(
    ApiClient(
      baseUrl: 'https://weekly-review.test',
      token: 'fixture-token',
      httpClient: client,
    ),
  );
  await ai.loadFromStorage();
  ai.updateFromServerConfig({'ai_enabled': true, 'ai_model': 'fixture-model'});
  return _WeeklyReviewHarness(
    ai: ai,
    todos: TodoProvider(),
    pomodoros: PomodoroProvider(),
    habits: HabitProvider(),
    client: client,
  );
}

Future<void> _pumpHarness(
  WidgetTester tester,
  _WeeklyReviewHarness harness,
) async {
  await tester.pumpWidget(
    AnimatedBuilder(
      animation: harness,
      builder: (_, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: harness.todos),
          ChangeNotifierProvider<HabitProvider>.value(value: harness.habits),
          ChangeNotifierProvider<PomodoroProvider>.value(
            value: harness.pomodoros,
          ),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => CountdownProvider()),
          ChangeNotifierProvider(create: (_) => NoteProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => AppLockProvider()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider<AuthProvider>.value(value: harness.auth),
          ChangeNotifierProvider<AiService>.value(value: harness.ai),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
          ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
          ChangeNotifierProvider(
            create: (_) => AppUpdateService(
              repo: 'dq52099/duoyi',
              currentVersion: AppVersion.name,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(harness.textScale)),
            child: RepaintBoundary(key: _boundaryKey, child: child!),
          ),
          home: const _MineRouteLauncher(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMineRoute(WidgetTester tester) async {
  await tester.tap(find.byKey(_openMineKey));
  await tester.pumpAndSettle();
  expect(find.byType(MineScreen), findsOneWidget);
  await tester.scrollUntilVisible(
    find.text(I18n.tr('mine.ai.review_title')),
    260,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _unmountHarness(
  WidgetTester tester,
  _WeeklyReviewHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  harness.dispose();
}

void _expectStatsSummary(
  WidgetTester tester,
  DateTime now, {
  required int completed,
  required int total,
  required int focus,
  required int streak,
}) {
  final lines = find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    return text.contains('$completed / $total');
  });
  expect(lines, findsOneWidget);
  final line = tester.widget<Text>(lines.first);
  final actual = line.data ?? line.textSpan?.toPlainText() ?? '';
  expect(
    actual,
    _localizedSummary(
      now,
      completed: completed,
      total: total,
      focus: focus,
      streak: streak,
    ),
  );
}

String _localizedSummary(
  DateTime now, {
  required int completed,
  required int total,
  required int focus,
  required int streak,
}) {
  final rangeKey = completed == 0 && now.weekday == DateTime.monday
      ? 'mine.ai.range.last_week'
      : 'mine.ai.range.this_week';
  return '${I18n.tr(rangeKey)}'
      '${I18n.tr('mine.ai.summary.header_suffix')}'
      '$completed / $total'
      '${I18n.tr('mine.ai.summary.todos_suffix')}'
      '$focus'
      '${I18n.tr('mine.ai.summary.focus_suffix')}'
      '$streak'
      '${I18n.tr('mine.ai.summary.streak_suffix')}';
}

void _expectGenerationDisabled(WidgetTester tester) {
  final generated = find.widgetWithText(
    TextButton,
    I18n.tr('mine.ai.generated_today'),
  );
  expect(generated, findsOneWidget);
  expect(tester.widget<TextButton>(generated).onPressed, isNull);
}

String _reviewBodyText(WidgetTester tester) {
  final text = tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(_reviewContentKey),
          matching: find.byType(Text),
        )
        .first,
  );
  return text.data ?? text.textSpan?.toPlainText() ?? '';
}

String _mockStructuredReview(String period, {bool isEnglish = false}) =>
    isEnglish
    ? '$period review\n'
          'Overview: fixture review text stays unchanged\n'
          'Data\nTasks: no tasks recorded\nFocus: no minutes recorded\n'
          'Habits: no streak recorded\nObservation: use a manageable routine\n'
          'Next week\nAction 1: reserve a regular focus window\n'
          'Action 2: break down one large task'
    : '$period回顾\n'
          '总览：模拟正文 fixture review text stays unchanged\n'
          '数据\n'
          '待办：完成情况\n'
          '专注：专注时长\n'
          '习惯：连续打卡\n'
          '观察：模拟响应内容用于界面回归\n'
          '下周行动\n'
          '行动一：保留固定专注时段\n'
          '行动二：拆解一个较大的任务';

class _MineRouteLauncher extends StatelessWidget {
  const _MineRouteLauncher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: _openMineKey,
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const MineScreen()),
        ),
        child: const Text('Open Mine route'),
      ),
    ),
  );
}

class _WeeklyReviewHarness extends ChangeNotifier {
  AiService ai;
  _TestAuth auth = _TestAuth();
  double textScale = 1;
  final List<ChangeNotifier> retired = [];
  void replaceAuth() {
    retired.add(auth);
    auth = _TestAuth();
    notifyListeners();
  }

  void replaceAi(AiService replacement) {
    retired.add(ai);
    ai = replacement;
    notifyListeners();
  }

  final TodoProvider todos;
  final PomodoroProvider pomodoros;
  final HabitProvider habits;
  final http.Client client;

  _WeeklyReviewHarness({
    required this.ai,
    required this.todos,
    required this.pomodoros,
    required this.habits,
    required this.client,
  });

  @override
  void dispose() {
    for (final owner in retired) {
      owner.dispose();
    }
    auth.dispose();
    ai.dispose();
    todos.dispose();
    pomodoros.dispose();
    habits.dispose();
    client.close();
    super.dispose();
  }
}

class _TestAuth extends AuthProvider {
  int generation = 0;
  @override
  int get sessionGeneration => generation;
  void changeSession() {
    generation++;
    notifyListeners();
  }
}
