import 'dart:convert';

import 'package:duoyi/core/focus_report.dart';
import 'package:duoyi/core/focus_report_presentation.dart';
import 'package:duoyi/core/focus_tag_stats.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

final _now = DateTime(2026, 5, 20, 12);
const _literalTag = '原始标签 / literal';
const _periodCases = [
  (
    period: FocusReportPeriod.week,
    title: 'Weekly Focus Report',
    start: '2026-05-18',
  ),
  (
    period: FocusReportPeriod.month,
    title: 'Monthly Focus Report',
    start: '2026-05-01',
  ),
  (
    period: FocusReportPeriod.all,
    title: 'All Focus Report',
    start: '1970-01-01',
  ),
];

void main() {
  for (final entry in _periodCases) {
    test(
      '${entry.period.name} Chinese output preserves exact legacy Markdown',
      () {
        final report = _report(entry.period);
        expect(FocusReportPresentation(report).title, report.title);
        expect(
          FocusReportPresentation(report).toMarkdown(),
          report.toMarkdown(),
        );
        expect(
          FocusReportPresentation.forLocale(
            report,
            locale: AppLocale.zh,
          ).toMarkdown(),
          report.toMarkdown(),
        );
        // Collision provenance must never change the Chinese export contract.
        expect(
          FocusReportPresentation(
            report,
            hasAuthoredUntaggedCollision: true,
          ).toMarkdown(),
          report.toMarkdown(),
        );
      },
    );

    test(
      '${entry.period.name} Chinese custom dates preserve exact legacy output',
      () {
        final report = _report(entry.period);
        final observed = <DateTime>[];
        final actual =
            FocusReportPresentation.forLocale(
              report,
              locale: AppLocale.zh,
            ).toMarkdown(
              formatDate: (date) {
                observed.add(date);
                return _customDate(date);
              },
            );
        expect(actual, report.toMarkdown(formatDate: _customDate));
        expect(observed, [report.start, report.end]);
      },
    );

    test(
      '${entry.period.name} English export binds every generated label and value',
      () {
        final report = _report(entry.period);
        final presentation = FocusReportPresentation.forLocale(
          report,
          locale: AppLocale.en,
        );
        final expected =
            '''# ${entry.title}

- Period: ${entry.start} - 2026-05-20
- Total focus duration: 85 min
- Focus sessions: 3
- Average session: 28 min
- Longest session: 50 min
- Active days: 2
- Strict-focus interruptions: 2, affecting 10 min

## Tag breakdown
- 原始标签 / literal: 75 min / 2 sessions, share 88%
- Untagged: 10 min / 1 session, share 12%
''';
        expect(presentation.title, entry.title);
        expect(presentation.toMarkdown(), expected);
        expect(
          FocusReportPresentation(report, isEnglish: true).toMarkdown(),
          expected,
        );
        expect(
          presentation.toMarkdown().replaceAll(_literalTag, 'literal'),
          isNot(matches(RegExp(r'[\u3400-\u9fff]'))),
        );
        // Exporting does not translate the raw generated bucket in the model.
        expect(report.topTags.last.tag, '未标记');
      },
    );

    test(
      '${entry.period.name} English respects caller dates and retained bounds',
      () {
        final report = _report(entry.period);
        final observed = <DateTime>[];
        final markdown =
            FocusReportPresentation.forLocale(
              report,
              locale: AppLocale.en,
            ).toMarkdown(
              formatDate: (date) {
                observed.add(date);
                return _customDate(date);
              },
            );
        expect(observed, [report.start, report.end]);
        expect(
          markdown,
          contains(
            '- Period: ${_customDate(report.start)} - ${_customDate(report.end)}\n',
          ),
        );
        expect(markdown, startsWith('# ${entry.title}\n'));
        expect(markdown, contains('- Total focus duration: 85 min\n'));
        expect(
          markdown,
          contains('- $_literalTag: 75 min / 2 sessions, share 88%\n'),
        );
      },
    );
  }

  for (final locale in [AppLocale.zh, AppLocale.en]) {
    test('${locale.name} empty report omits tag heading and tag rows', () {
      final report = FocusReportBuilder.build(
        sessions: const [],
        penalties: [
          PomodoroFocusPenalty(
            id: 'empty-report-penalty',
            occurredAt: DateTime(2026, 5, 19),
            reason: FocusPenaltyReason.pause,
            affectedSeconds: 149,
          ),
        ],
        period: FocusReportPeriod.month,
        now: _now,
      );
      final markdown = FocusReportPresentation.forLocale(
        report,
        locale: locale,
      ).toMarkdown();
      expect(report.topTags, isEmpty);
      expect(markdown, isNot(contains('##')));
      expect(markdown, isNot(contains('Untagged')));
      expect(markdown, isNot(contains('未标记')));
      if (locale == AppLocale.zh) {
        expect(markdown, report.toMarkdown());
      } else {
        expect(markdown, '''# Monthly Focus Report

- Period: 2026-05-01 - 2026-05-20
- Total focus duration: 0 min
- Focus sessions: 0
- Average session: 0 min
- Longest session: 0 min
- Active days: 0
- Strict-focus interruptions: 1, affecting 2 min
''');
      }
    });
  }

  for (final raw in ['未标记', '#未标记']) {
    for (final mixed in [false, true]) {
      test(
        'authored $raw ${mixed ? 'mixed with blank' : 'alone'} keeps literal merged bucket',
        () {
          final sessions = [
            _session('authored', tag: raw),
            if (mixed) _session('blank', tag: null, seconds: 300),
          ];
          final before = _sessionJson(sessions);
          final report = _build(sessions);
          final collision =
              FocusReportPresentation.detectAuthoredUntaggedCollision(
                report: report,
                sessions: sessions,
              );
          expect(collision, isTrue);
          final markdown = FocusReportPresentation.forLocale(
            report,
            locale: AppLocale.en,
            hasAuthoredUntaggedCollision: collision,
          ).toMarkdown();
          expect(report.topTags, hasLength(1));
          expect(report.topTags.single.tag, '未标记');
          expect(report.topTags.single.totalMinutes, mixed ? 15 : 10);
          expect(report.topTags.single.sessionCount, mixed ? 2 : 1);
          expect(
            markdown,
            contains(
              mixed
                  ? '- 未标记: 15 min / 2 sessions, share 100%\n'
                  : '- 未标记: 10 min / 1 session, share 100%\n',
            ),
          );
          expect(markdown, isNot(contains('- Untagged:')));
          expect(_sessionJson(sessions), before);
          expect(
            FocusReportPresentation(
              report,
              hasAuthoredUntaggedCollision: collision,
            ).toMarkdown(),
            report.toMarkdown(),
          );
        },
      );
    }
  }

  for (final raw in ['  未标记  ', '  #未标记  ']) {
    test(
      'authored collision applies existing outer-whitespace normalization to "$raw"',
      () {
        final sessions = [_session('trimmed-collision', tag: raw)];
        final report = _build(sessions);
        expect(
          FocusReportPresentation.detectAuthoredUntaggedCollision(
            report: report,
            sessions: sessions,
          ),
          isTrue,
        );
        expect(
          _english(sessions),
          contains('- 未标记: 10 min / 1 session, share 100%\n'),
        );
        expect(sessions.single.tag, raw);
      },
    );
  }

  for (final raw in <String?>[null, '', '   ', '#', '  #  ']) {
    test(
      'generated blank tag ${jsonEncode(raw)} becomes Untagged without changing source',
      () {
        final sessions = [_session('generated', tag: raw)];
        final report = _build(sessions);
        expect(
          FocusReportPresentation.detectAuthoredUntaggedCollision(
            report: report,
            sessions: sessions,
          ),
          isFalse,
        );
        expect(
          _english(sessions),
          contains('- Untagged: 10 min / 1 session, share 100%\n'),
        );
        expect(report.topTags.single.tag, '未标记');
        expect(sessions.single.tag, raw);
      },
    );
  }

  test(
    'all blank spellings share one generated bucket with plural session count',
    () {
      final sessions = [
        for (final entry in <String?>[null, '', '   ', '#', '  #  '].indexed)
          _session('blank-${entry.$1}', tag: entry.$2),
      ];
      expect(
        _english(sessions),
        contains('- Untagged: 50 min / 5 sessions, share 100%\n'),
      );
    },
  );

  for (final period in FocusReportPeriod.values) {
    for (final boundary in ['before start', 'at end-exclusive']) {
      test(
        '${period.name} authored collision $boundary does not affect included blank bucket',
        () {
          final seed = _build([_session('included-blank')], period: period);
          final excludedStart = boundary == 'before start'
              ? seed.start.subtract(const Duration(microseconds: 1))
              : DateTime(seed.end.year, seed.end.month, seed.end.day + 1);
          final sessions = [
            _session('included-blank'),
            _session('excluded-authored', tag: '#未标记', start: excludedStart),
          ];
          final report = _build(sessions, period: period);
          expect(report.sessionCount, 1);
          expect(
            FocusReportPresentation.detectAuthoredUntaggedCollision(
              report: report,
              sessions: sessions,
            ),
            isFalse,
          );
          expect(
            _english(sessions, period: period),
            contains('- Untagged: 10 min / 1 session, share 100%\n'),
          );
        },
      );
    }
  }

  final excludedCases = [
    (
      name: 'short break',
      session: _session('short', tag: '未标记', type: PomodoroType.shortBreak),
    ),
    (
      name: 'long break',
      session: _session('long', tag: '#未标记', type: PomodoroType.longBreak),
    ),
    (name: 'zero duration', session: _session('zero', tag: '未标记', seconds: 0)),
    (
      name: 'negative duration',
      session: _session('negative', tag: '#未标记', seconds: -60),
    ),
    (
      name: 'future civil day',
      session: _session('future', tag: '未标记', start: DateTime(2026, 5, 22)),
    ),
  ];
  for (final entry in excludedCases) {
    test('${entry.name} cannot force an authored collision', () {
      final sessions = [_session('included-blank'), entry.session];
      final report = _build(sessions);
      expect(report.sessionCount, 1);
      expect(
        FocusReportPresentation.detectAuthoredUntaggedCollision(
          report: report,
          sessions: sessions,
        ),
        isFalse,
      );
      expect(
        _english(sessions),
        contains('- Untagged: 10 min / 1 session, share 100%\n'),
      );
    });
  }

  test(
    'all ignored authored tags together cannot suppress generated Untagged',
    () {
      final sessions = [
        _session('included-blank'),
        for (final entry in excludedCases) entry.session,
        _session('before-week', tag: '#未标记', start: DateTime(2026, 5, 17)),
        _session('end-exclusive', tag: '未标记', start: DateTime(2026, 5, 21)),
      ];
      final report = _build(sessions);
      expect(report.sessionCount, 1);
      expect(
        FocusReportPresentation.detectAuthoredUntaggedCollision(
          report: report,
          sessions: sessions,
        ),
        isFalse,
      );
      expect(
        _english(sessions),
        contains('- Untagged: 10 min / 1 session, share 100%\n'),
      );
    },
  );

  for (final boundary in ['at start', 'later on end day']) {
    test(
      'contributing authored collision $boundary retains literal bucket',
      () {
        final start = boundary == 'at start'
            ? DateTime(2026, 5, 18)
            : DateTime(2026, 5, 20, 23, 59, 59);
        final sessions = [
          _session('boundary-collision', tag: '#未标记', start: start),
        ];
        final report = _build(sessions);
        expect(report.sessionCount, 1);
        expect(
          FocusReportPresentation.detectAuthoredUntaggedCollision(
            report: report,
            sessions: sessions,
          ),
          isTrue,
        );
        expect(
          _english(sessions),
          contains('- 未标记: 10 min / 1 session, share 100%\n'),
        );
      },
    );
  }

  for (final literal in [
    '专注总时长：周期：分钟 / 标签投入 # Untagged',
    '本周专注报告 | 原始内容',
    '未标记说明',
    '# 未标记',
    '##未标记',
  ]) {
    test(
      'authored framing-like tag "$literal" is never substring-translated',
      () {
        final sessions = [_session('literal', tag: literal)];
        final before = _sessionJson(sessions);
        final report = _build(sessions);
        expect(
          FocusReportPresentation.detectAuthoredUntaggedCollision(
            report: report,
            sessions: sessions,
          ),
          isFalse,
        );
        // The builder removes only one leading hash, without a second trim.
        // In particular '# 未标记' remains a literal leading-space tag.
        final expectedTag = switch (literal) {
          '# 未标记' => ' 未标记',
          '##未标记' => '#未标记',
          _ => literal,
        };
        expect(report.topTags.single.tag, expectedTag);
        final markdown = _english(sessions);
        expect(
          markdown,
          contains('- $expectedTag: 10 min / 1 session, share 100%\n'),
        );
        expect(markdown, contains('- Total focus duration: 10 min\n'));
        expect(_sessionJson(sessions), before);
      },
    );
  }

  test(
    'explicit presentation locales stay frozen when global locale changes',
    () {
      final previous = I18n.current;
      addTearDown(() => I18n.setLocale(previous));
      final report = _report(FocusReportPeriod.week);
      final english = FocusReportPresentation.forLocale(
        report,
        locale: AppLocale.en,
      );
      final chinese = FocusReportPresentation.forLocale(
        report,
        locale: AppLocale.zh,
      );
      final before = english.toMarkdown();
      I18n.setLocale(AppLocale.zh);
      expect(english.toMarkdown(), before);
      expect(english.title, 'Weekly Focus Report');
      I18n.setLocale(AppLocale.en);
      expect(chinese.toMarkdown(), report.toMarkdown());
      expect(chinese.title, '本周专注报告');
    },
  );
}

FocusReport _report(FocusReportPeriod period) => FocusReport(
  period: period,
  start: switch (period) {
    FocusReportPeriod.week => DateTime(2026, 5, 18),
    FocusReportPeriod.month => DateTime(2026, 5, 1),
    FocusReportPeriod.all => DateTime(1970, 1, 1),
  },
  end: _now,
  sessionCount: 3,
  totalSeconds: 5100,
  averageSeconds: 1700,
  longestSeconds: 3000,
  activeDays: 2,
  topTags: const [
    FocusTagStat(
      tag: _literalTag,
      sessionCount: 2,
      totalSeconds: 4500,
      share: 75 / 85,
    ),
    FocusTagStat(
      tag: '未标记',
      sessionCount: 1,
      totalSeconds: 600,
      share: 10 / 85,
    ),
  ],
  penaltyCount: 2,
  penaltyAffectedSeconds: 659,
);

String _customDate(DateTime date) =>
    '自定义 ${date.day}/${date.month}/${date.year}';

PomodoroSession _session(
  String id, {
  String? tag,
  DateTime? start,
  int seconds = 600,
  PomodoroType type = PomodoroType.focus,
}) {
  final begins = start ?? DateTime(2026, 5, 19, 9);
  return PomodoroSession(
    id: id,
    startTime: begins,
    endTime: begins.add(Duration(seconds: seconds)),
    durationSeconds: seconds,
    type: type,
    taskName: 'Authored task 原文',
    tag: tag,
  );
}

FocusReport _build(
  List<PomodoroSession> sessions, {
  FocusReportPeriod period = FocusReportPeriod.week,
}) => FocusReportBuilder.build(
  sessions: sessions,
  penalties: const [],
  period: period,
  now: _now,
);

String _english(
  List<PomodoroSession> sessions, {
  FocusReportPeriod period = FocusReportPeriod.week,
}) {
  final report = _build(sessions, period: period);
  return FocusReportPresentation.forLocale(
    report,
    locale: AppLocale.en,
    hasAuthoredUntaggedCollision:
        FocusReportPresentation.detectAuthoredUntaggedCollision(
          report: report,
          sessions: sessions,
        ),
  ).toMarkdown();
}

String _sessionJson(List<PomodoroSession> sessions) =>
    jsonEncode(sessions.map((session) => session.toJson()).toList());
