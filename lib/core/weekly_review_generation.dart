import 'weekly_review_summary.dart';

/// Text for one generation request. Never consults mutable global locale.
class WeeklyReviewGeneration {
  const WeeklyReviewGeneration({required this.stats, required this.isEnglish});

  final WeeklyReviewStats stats;
  final bool isEnglish;

  String get periodLabel {
    final label = switch (stats.period) {
      WeeklyReviewPeriod.thisWeek => isEnglish ? 'this week' : '本周',
      WeeklyReviewPeriod.lastWeek => isEnglish ? 'last week' : '上周',
      WeeklyReviewPeriod.custom => stats.customPeriodLabel,
    };
    // A generation header is one protocol line. Keep the authored label in
    // stats/storage unchanged, including any original line separators.
    return label.replaceAll(RegExp(r'[\r\n\u0085\u2028\u2029]+'), ' ');
  }

  String get title => isEnglish ? '$periodLabel review' : '$periodLabel回顾';

  String get systemPrompt => isEnglish
      ? 'You are Duoyi’s practical productivity review assistant. Write in English using only the supplied $periodLabel facts. '
            'Return exactly ten lines in the following order. Keep each line brief (about 20 words). '
            'Use plain text without Markdown, tables, emoji, bold, separators or a closing offer. '
            'Avoid generic encouragement and invented facts. Keep the period label exactly as supplied.\n'
            '$title\nOverview: one overall assessment\nData\nTasks: completion\nFocus: minutes\n'
            'Habits: current streak\nObservation: one useful observation\nNext week\n'
            'Action 1: one practical step\nAction 2: one practical step'
      : '你是多仪的效率回顾助手。基于$periodLabel完成情况输出中文周回顾。'
            '必须严格遵守：1. 输出分层纯文本，不要写成长段落；'
            '2. 不要 Markdown、表格、emoji、加粗、标题、分隔线或客套结尾；'
            '3. 不要出现“根据你提供的数据”“随时告诉我”“加油”等套话；'
            '4. 每行尽量不超过 32 个汉字；5. 严格输出以下十行，保留给定周期名称：\n'
            '$title\n总览：一句总判断\n数据\n待办：完成情况\n专注：专注时长\n'
            '习惯：连续打卡\n观察：一句关键原因或状态\n下周行动\n行动一：一个具体动作\n行动二：一个具体动作';

  String get userPrompt => isEnglish
      ? 'Period: $periodLabel\nTasks completed: ${stats.completedTodos} / ${stats.totalTodos}\n'
            'Focus time: ${stats.focusMinutes} minutes\nHabit streak: ${stats.habitStreak} days\n'
            'Generate this weekly review in English.'
      : '周期：$periodLabel\n待办完成：${stats.completedTodos} / ${stats.totalTodos}\n'
            '专注时长：${stats.focusMinutes} 分钟\n习惯连续打卡：${stats.habitStreak} 天\n请生成这次周回顾。';

  String normalize(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim() == title ? title : _cleanLine(line))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return _isStructured(lines) ? lines.join('\n') : fallback;
  }

  static String _cleanLine(String line) => line
      .trim()
      .replaceFirst(RegExp(r'^(?:#{1,6}\s*|>\s*|[-*]\s+|\d+[.)]\s*)+'), '')
      .replaceAll(RegExp(r'[`*_~]'), '')
      .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isStructured(List<String> lines) {
    if (lines.length != 10 || lines.first != title) return false;
    final headings = isEnglish
        ? [
            'Overview: ',
            'Data',
            'Tasks: ',
            'Focus: ',
            'Habits: ',
            'Observation: ',
            'Next week',
            'Action 1: ',
            'Action 2: ',
          ]
        : ['总览：', '数据', '待办：', '专注：', '习惯：', '观察：', '下周行动', '行动一：', '行动二：'];
    for (var i = 0; i < headings.length; i++) {
      final line = lines[i + 1];
      final heading = headings[i];
      if (i == 1 || i == 6) {
        if (line != heading) return false;
      } else if (!line.startsWith(heading) ||
          line.substring(heading.length).trim().isEmpty) {
        return false;
      }
    }
    final body = lines.skip(1).join('\n');
    if (RegExp(r'[*_#|]').hasMatch(body) ||
        RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true).hasMatch(body)) {
      return false;
    }
    // This script check catches common wrong-language responses. It is a
    // heuristic, not full language identification; authored titles are exempt.
    if (isEnglish && RegExp(r'[\u3400-\u9fff]').hasMatch(body)) return false;
    if (!isEnglish) {
      for (final index in [1, 6, 8, 9]) {
        final payload = lines[index].split('：').skip(1).join('：');
        if (!RegExp(r'[\u3400-\u9fff]').hasMatch(payload)) return false;
      }
    }
    return true;
  }

  String get fallback {
    final completed = stats.completedTodos;
    final total = stats.totalTodos;
    final focus = stats.focusMinutes;
    final streak = stats.habitStreak;
    final rate = total <= 0 ? 0 : (completed / total * 100).round();
    final sparse = total <= 0 && focus <= 0 && streak <= 0;
    final overview = sparse
        ? _text(
            '记录偏少，先恢复基础节奏。',
            'Few records yet; start by rebuilding a simple routine.',
          )
        : total > 0 && completed >= total
        ? _text(
            '待办推进稳定，继续保持。',
            'Planned tasks are complete; keep the routine manageable.',
          )
        : rate >= 70
        ? _text(
            '整体完成不错，可以继续加固。',
            'Most planned tasks are complete; keep a steady pace.',
          )
        : _text(
            '节奏还有提升空间。',
            'There is room to make the routine more consistent.',
          );
    final todoLine = total <= 0
        ? _text(
            '待办：暂无计划项，先安排关键任务。',
            'Tasks: no planned tasks; choose one priority first.',
          )
        : _text(
            '待办：完成 $completed / $total 项，完成率 $rate%。',
            'Tasks: $completed / $total completed ($rate%).',
          );
    final focusLine = focus <= 0
        ? _text(
            '专注：0 分钟，先从每天 10 分钟开始。',
            'Focus: 0 minutes; start with 10 minutes a day.',
          )
        : _text(
            '专注：$focus 分钟，保留固定专注窗口。',
            'Focus: $focus ${focus == 1 ? 'minute' : 'minutes'}; reserve a regular focus window.',
          );
    final habitLine = streak <= 0
        ? _text(
            '习惯：连续 0 天，先重启一个最小习惯。',
            'Habits: a 0-day streak; restart one small habit.',
          )
        : _text(
            '习惯：连续 $streak 天，继续守住当前节奏。',
            'Habits: a $streak-day streak; keep the routine manageable.',
          );
    return [
      title,
      _text('总览：', 'Overview: ') + overview,
      _text('数据', 'Data'),
      todoLine,
      focusLine,
      habitLine,
      _text('观察：', 'Observation: ') + _observation,
      _text('下周行动', 'Next week'),
      _text('行动一：', 'Action 1: ') + _firstAction,
      _text('行动二：', 'Action 2: ') + _secondAction,
    ].join('\n');
  }

  String _text(String zh, String en) => isEnglish ? en : zh;

  String get _observation {
    if (stats.totalTodos > 0 &&
        stats.completedTodos > 0 &&
        stats.focusMinutes <= 0) {
      return _text(
        '待办有推进，但专注时间没有形成记录。',
        'Tasks progressed, but no focus time was recorded.',
      );
    }
    if (stats.habitStreak <= 0 && stats.focusMinutes > 0) {
      return _text(
        '专注已经启动，习惯链还需要重新接上。',
        'Focus sessions have started; the habit routine still needs rebuilding.',
      );
    }
    if (stats.totalTodos <= 0 &&
        stats.focusMinutes <= 0 &&
        stats.habitStreak <= 0) {
      return _text(
        '本周更像恢复周，先把记录节奏找回来。',
        'Start by recording a few manageable activities consistently.',
      );
    }
    return _text(
      '当前节奏可延续，重点是减少目标切换。',
      'Keep the current routine and reduce switching between goals.',
    );
  }

  String get _firstAction {
    if (stats.focusMinutes <= 0) {
      return _text(
        '每天先排一个 10 分钟专注块。',
        'Schedule one 10-minute focus session each day.',
      );
    }
    if (stats.habitStreak <= 0) {
      return _text(
        '选择一个低门槛习惯连续打卡 3 天。',
        'Choose one easy habit and check in for three days.',
      );
    }
    if (stats.totalTodos <= 0) {
      return _text(
        '提前列出 3 件本周关键任务。',
        'List three priority tasks for the coming week.',
      );
    }
    return _text(
      '保留 2 件关键任务，完成后再加新任务。',
      'Keep two priority tasks; finish them before adding more.',
    );
  }

  String get _secondAction {
    if (stats.habitStreak <= 0) {
      return _text(
        '把喝水或早睡设为本周最小习惯。',
        'Pick a small habit, such as drinking water or going to bed earlier.',
      );
    }
    if (stats.focusMinutes <= 0) {
      return _text(
        '把专注提醒放到每天固定时段。',
        'Set a daily focus reminder at a regular time.',
      );
    }
    if (stats.totalTodos <= 0) {
      return _text('每天只确认一次任务清单。', 'Review the task list once each day.');
    }
    return _text(
      '周中复盘一次，及时删掉低优先级任务。',
      'Review progress midweek and remove low-priority tasks.',
    );
  }
}
