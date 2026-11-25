import 'i18n.dart';

/// 每日一言：按日期切换的简短格言/提醒。
class DailyQuotes {
  // 保持短句，便于卡片展示。
  static const List<String> quotes = [
    '一寸光阴一寸金，寸金难买寸光阴。',
    '今天所做的，是未来的礼物。',
    '少做一点点，做好每一点。',
    '把事情写下来，大脑就不用记事。',
    '今天的专注，是明天的从容。',
    '比昨天的自己好一点就够了。',
    '小的习惯，会慢慢改变一切。',
    '先完成，再完美。',
    '不必所有事都今天做完。',
    '睡前十分钟复盘，胜过一整天奔忙。',
    '计划总会出错，但规划本身就值得。',
    '慢下来，让灵感追上你。',
    '今天未必容易，但值得用心。',
    '记录你想忘的，它才会真的忘掉。',
    '开始比完美重要。',
    '清空大脑，留给创造。',
    '每一次深呼吸，都是对自己的交代。',
    '该休息就休息，这也算生产力。',
    '做真正重要的事，而不是最紧急的事。',
    '把大目标切成明天能完成的小步。',
    '认真吃饭，认真睡觉，认真工作。',
    '把今天当成彩排，也当成首演。',
    '等下一分钟，不如从这分钟开始。',
    '纸笔，是最可靠的队友。',
    '番茄钟的二十五分钟，不比两个小时短。',
    '告诉自己：做完这一个，就完事。',
    '偶尔走神，也是专注的一部分。',
    '做一个安静又坚定的人。',
    '复盘，是对自己最温柔的问候。',
    '愿你今天的烦恼，不过是今天的。',
  ];

  static const List<String> quotesEn = [
    'Every moment spent intentionally returns compound clarity.',
    'What you build today is a quiet gift to tomorrow.',
    'Do slightly less, and finish each piece with care.',
    'Write tasks down so your mind can stay clear.',
    'Today’s deep focus creates tomorrow’s calm.',
    'One small step better than yesterday is plenty.',
    'Tiny habits quietly reshape everything over time.',
    'Done beats perfect.',
    'Not everything has to be finished today.',
    'Ten minutes of evening reflection outweighs a rushed day.',
    'Plans will bend, yet planning itself brings clarity.',
    'Slow down enough for insight to catch up.',
    'Today may take effort, and still be worth your care.',
    'Capture what weighs on your mind so you can let it go.',
    'Starting matters more than getting it flawless.',
    'Empty your inbox, save your mind for creating.',
    'Every slow breath resets your attention.',
    'Rest well when needed; recovery is real productivity.',
    'Spend your best hours on what matters, not what shouts.',
    'Break big ambitions into steps you can finish tomorrow.',
    'Eat well, sleep deeply, and work with presence.',
    'Treat today as both practice and the real stage.',
    'Begin this minute instead of waiting for the next.',
    'A blank page is the steadiest teammate you have.',
    'Twenty-five focused minutes outlast two distracted hours.',
    'Tell yourself: just finish this one piece.',
    'Even a wandering mind is part of learning to focus.',
    'Stay calm, stay steady, keep moving forward.',
    'Reviewing your day is the kindest check-in with yourself.',
    'Let today’s worries stay neatly inside today.',
  ];

  /// 当日稳定索引。
  static int todayIndex() {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(2000, 1, 1)).inDays;
    return days.abs() % quotes.length;
  }

  /// 随机索引（不固定到日期）。
  static int randomIndex() {
    final seed = DateTime.now().millisecondsSinceEpoch;
    return seed.abs() % quotes.length;
  }

  /// 按索引与语言取对应语录。
  static String at(int index, {AppLocale? locale}) {
    final activeLocale = locale ?? I18n.current;
    final list = activeLocale == AppLocale.en ? quotesEn : quotes;
    return list[index.abs() % list.length];
  }

  /// 基于日期稳定选择同一条。
  static String today({AppLocale? locale}) => at(todayIndex(), locale: locale);

  /// 随机换一条(不固定到日期)。
  static String random({AppLocale? locale}) => at(randomIndex(), locale: locale);
}
