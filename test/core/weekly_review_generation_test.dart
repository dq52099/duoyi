import 'package:duoyi/core/weekly_review_generation.dart';
import 'package:duoyi/core/weekly_review_summary.dart';
import 'package:test/test.dart';

WeeklyReviewGeneration _generation({
  bool english = true,
  int completed = 2,
  int total = 3,
  int focus = 45,
  int streak = 4,
  WeeklyReviewPeriod period = WeeklyReviewPeriod.thisWeek,
  String customLabel = '',
}) => WeeklyReviewGeneration(
  isEnglish: english,
  stats: WeeklyReviewStats(
    completedTodos: completed,
    totalTodos: total,
    focusMinutes: focus,
    habitStreak: streak,
    period: period,
    customPeriodLabel: customLabel,
  ),
);

const _english =
    'this week review\n'
    'Overview: keep this useful assessment\nData\n'
    'Tasks: 2 / 3 complete\nFocus: 45 minutes\nHabits: a four-day streak\n'
    'Observation: retain this specific observation\nNext week\n'
    'Action 1: protect one quiet work period\nAction 2: review the task list';
const _chinese =
    '本周回顾\n总览：保留这段有效判断\n数据\n'
    '待办：完成 2 / 3 项\n专注：45 分钟\n习惯：连续 4 天\n'
    '观察：保留这段具体观察\n下周行动\n行动一：固定一个安静时段\n行动二：复核任务清单';

void main() {
  test(
    'both request prompts use the chosen language and saved numeric facts',
    () {
      final en = _generation();
      expect(en.systemPrompt, contains('Write in English'));
      expect(en.systemPrompt, contains('exactly ten lines'));
      expect(en.userPrompt, contains('Tasks completed: 2 / 3'));
      expect(en.userPrompt, contains('Focus time: 45 minutes'));
      expect(en.userPrompt, isNot(contains('周期')));
      final zh = _generation(english: false);
      expect(zh.systemPrompt, contains('输出中文周回顾'));
      expect(zh.userPrompt, contains('待办完成：2 / 3'));
      expect(zh.userPrompt, contains('专注时长：45 分钟'));
    },
  );

  test('valid ten-line prose survives without fallback in both languages', () {
    expect(_generation().normalize(_english), _english);
    expect(_generation(english: false).normalize(_chinese), _chinese);
  });

  test('the period enum localizes but authored period labels stay exact', () {
    expect(
      _generation(period: WeeklyReviewPeriod.lastWeek).title,
      'last week review',
    );
    expect(
      _generation(english: false, period: WeeklyReviewPeriod.lastWeek).title,
      '上周回顾',
    );
    final custom = _generation(
      period: WeeklyReviewPeriod.custom,
      customLabel: '冲刺_A / 2026',
    );
    final prose = _english.replaceFirst(
      'this week review',
      '冲刺_A / 2026 review',
    );
    expect(custom.normalize(prose), prose);
    expect(custom.fallback, startsWith('冲刺_A / 2026 review\nOverview: '));
    expect(custom.userPrompt, startsWith('Period: 冲刺_A / 2026\n'));
  });

  test('extra, reordered, missing and empty fields use complete fallback', () {
    final generation = _generation();
    for (final raw in [
      '$_english\nAdditional invented text',
      _english.replaceFirst('Data\nTasks:', 'Tasks:\nData'),
      _english.replaceFirst('Action 2: review the task list', 'Action 2:'),
      _english.replaceFirst('Overview: keep this useful assessment\n', ''),
      _english.replaceFirst('Next week', 'Other heading'),
      'Overview: an incomplete answer',
    ]) {
      expect(generation.normalize(raw), generation.fallback, reason: raw);
    }
  });

  test(
    'multiline authored label stays stored while its header uses one line',
    () {
      final generation = _generation(
        period: WeeklyReviewPeriod.custom,
        customLabel: '冲刺\r\nA\u2028B',
      );
      expect(generation.periodLabel, '冲刺 A B');
      expect(generation.fallback.split('\n'), hasLength(10));
      expect(generation.stats.customPeriodLabel, '冲刺\r\nA\u2028B');
      expect(generation.stats.toJson()['customPeriodLabel'], '冲刺\r\nA\u2028B');
      expect(generation.normalize(generation.fallback), generation.fallback);
    },
  );

  test('wrong-language responses never donate prose to the fallback', () {
    final en = _generation();
    expect(en.normalize(_chinese), en.fallback);
    expect(
      en.normalize(
        _english.replaceFirst('keep this useful assessment', '保留中文判断'),
      ),
      en.fallback,
    );
    final zh = _generation(english: false);
    expect(zh.normalize(_english), zh.fallback);
    expect(
      zh.normalize(_chinese.replaceFirst('固定一个安静时段', 'Keep a quiet hour')),
      zh.fallback,
    );
    expect(en.fallback, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
  });

  test(
    'normalization removes presentation wrappers but preserves the full structure',
    () {
      final raw = _english
          .split('\n')
          .asMap()
          .entries
          .map((entry) => '${entry.key + 1}. **${entry.value}**')
          .join('\r\n');
      expect(_generation().normalize(raw), _english);
      expect(_generation().normalize('  $_english\n\n'), _english);
      expect(
        _generation().normalize('| Metric | Value |\n| --- | --- |'),
        _generation().fallback,
      );
    },
  );

  test(
    'all fallback branches satisfy their language structure and keep facts',
    () {
      for (final english in [true, false]) {
        for (final facts in [
          (0, 0, 0, 0),
          (3, 3, 45, 4),
          (7, 10, 45, 4),
          (1, 10, 0, 4),
          (0, 0, 45, 0),
          (0, 0, 45, 4),
          (1, 2, 1, 1),
          (5, 3, 45, 4),
        ]) {
          final generation = _generation(
            english: english,
            completed: facts.$1,
            total: facts.$2,
            focus: facts.$3,
            streak: facts.$4,
          );
          final fallback = generation.fallback;
          expect(fallback.split('\n'), hasLength(10));
          expect(generation.normalize(fallback), fallback);
          if (facts.$2 > 0) {
            expect(fallback, contains('${facts.$1} / ${facts.$2}'));
          }
          if (english) {
            expect(fallback, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
          }
        }
      }
    },
  );
}
