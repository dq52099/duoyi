import 'package:duoyi/core/daily_digest_presentation.dart';
import 'package:test/test.dart';

void main() {
  test(
    'renders Chinese and English counts with zero, singular, and plural values',
    () {
      final chinese = DailyDigestPresentation(isEnglish: false);
      final english = DailyDigestPresentation(isEnglish: true);

      String body(DailyDigestPresentation presentation) => presentation.body(
        todayCount: 0,
        tomorrowCount: 1,
        overdueCount: 2,
        includeTodayTasks: true,
        includeTomorrowPlan: true,
        includeOverdue: true,
      );

      expect(body(chinese), '今日 0 项 · 明日 1 项 · 逾期 2 项');
      expect(
        body(english),
        'Today 0 tasks · Tomorrow 1 task · Overdue 2 tasks',
      );
    },
  );

  test(
    'all eight include flag combinations select only their requested counts',
    () {
      for (final isEnglish in [false, true]) {
        final presentation = DailyDigestPresentation(isEnglish: isEnglish);
        for (var mask = 0; mask < 8; mask++) {
          final includeToday = (mask & 1) != 0;
          final includeTomorrow = (mask & 2) != 0;
          final includeOverdue = (mask & 4) != 0;
          final expectedPieces = <String>[
            if (includeToday) (isEnglish ? 'Today 4 tasks' : '今日 4 项'),
            if (includeTomorrow) (isEnglish ? 'Tomorrow 1 task' : '明日 1 项'),
            if (includeOverdue) (isEnglish ? 'Overdue 0 tasks' : '逾期 0 项'),
          ];
          final expected = expectedPieces.isNotEmpty
              ? expectedPieces.join(' · ')
              : isEnglish
              ? 'Open Duoyi to organize tasks and plans'
              : '打开多仪整理任务与计划';

          expect(
            presentation.body(
              todayCount: 4,
              tomorrowCount: 1,
              overdueCount: 0,
              includeTodayTasks: includeToday,
              includeTomorrowPlan: includeTomorrow,
              includeOverdue: includeOverdue,
            ),
            expected,
            reason: 'locale=$isEnglish, include mask=$mask',
          );
        }
      }
    },
  );

  test('empty include flags use the locale-specific fallback copy', () {
    final chinese = DailyDigestPresentation(isEnglish: false);
    final english = DailyDigestPresentation(isEnglish: true);

    String body(DailyDigestPresentation presentation) => presentation.body(
      todayCount: 1,
      tomorrowCount: 2,
      overdueCount: 3,
      includeTodayTasks: false,
      includeTomorrowPlan: false,
      includeOverdue: false,
    );

    expect(body(chinese), '打开多仪整理任务与计划');
    expect(body(english), 'Open Duoyi to organize tasks and plans');
  });

  test('slot titles cover indices zero through three in both languages', () {
    final chinese = DailyDigestPresentation(isEnglish: false);
    final english = DailyDigestPresentation(isEnglish: true);

    expect(
      [for (var index = 0; index < 4; index++) chinese.slotTitle(index)],
      ['每日提醒一', '每日提醒二', '每日提醒三', '每日提醒4'],
    );
    expect(
      [for (var index = 0; index < 4; index++) english.slotTitle(index)],
      [
        'Daily reminder 1',
        'Daily reminder 2',
        'Daily reminder 3',
        'Daily reminder 4',
      ],
    );
  });

  test('each presentation keeps the language captured at construction', () {
    var globalIsEnglish = false;
    final chinese = DailyDigestPresentation(isEnglish: globalIsEnglish);
    globalIsEnglish = true;
    final english = DailyDigestPresentation(isEnglish: globalIsEnglish);
    globalIsEnglish = false;

    expect(chinese.slotTitle(0), '每日提醒一');
    expect(english.slotTitle(0), 'Daily reminder 1');
  });
}
