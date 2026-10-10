import '../models/diary_entry.dart';
import 'i18n.dart';
import 'i18n_date_format.dart';

enum HeatmapMetric { progress, activity }

class HeatmapUiCopy {
  final AppLocale locale;
  const HeatmapUiCopy(this.locale);

  bool get _en => locale == AppLocale.en;
  String get today => _en ? 'Today' : '今天';
  String get future => _en ? 'Upcoming day' : '尚未到来';
  String get noEntry => _en ? 'No diary entry' : '无日记';
  String get noMood => _en ? 'Mood not set' : '未记录心情';
  String get openDiary => _en ? 'Open diary' : '查看日记';
  String get writeDiary => _en ? 'Write diary' : '写日记';
  String get moodTitle => _en ? 'Mood calendar' : '心情日历';
  String get habitGroups => _en ? 'Habit groups' : '习惯分组';
  String get activityTitle => _en ? 'Activity · last 52 weeks' : '近 52 周活动';
  String get activitySubtitle => _en
      ? 'Daily activity from tasks, habits, focus, time logs and diary entries'
      : '汇总待办、习惯、专注、时间足迹和日记的每日活跃度';
  String get activityHint => _en
      ? 'More saturated cells show higher weighted activity, from 0 to 5.'
      : '颜色越鲜明，加权活跃等级越高（0–5 级）。';
  String get progressHint => _en
      ? 'Progress levels run from 0 to 5; flexible habits use their period’s progress.'
      : '按目标进度分为 0–5 级，弹性习惯按整周或整月计算。';
  String get inspectHint => _en
      ? 'Select a day to inspect it. Use arrow keys to move between days.'
      : '选择日期查看详情，方向键可切换日期。';
  String get moodHint => _en ? 'Each color represents a mood.' : '每种颜色代表一种心情。';
  String get emptyProgress => _en ? 'No check-ins in this period' : '此周期暂无打卡记录';
  String get emptyActivity =>
      _en ? 'No activity recorded in this period' : '此周期暂无活动记录';
  String get emptyMood => _en ? 'No diary entries in this period' : '此周期暂无日记记录';
  String get low => _en ? 'Low' : '低';
  String get high => _en ? 'High' : '高';
  String metricTitle(HeatmapMetric metric) => metric == HeatmapMetric.activity
      ? (_en ? 'Activity calendar' : '活动日历')
      : (_en ? 'Habit progress calendar' : '习惯进度日历');
  String levelLabel(HeatmapMetric metric, int level) {
    final name = metric == HeatmapMetric.activity
        ? (_en ? 'Activity level' : '活跃等级')
        : (_en ? 'Progress level' : '达成等级');
    return '$name $level/5';
  }

  String activeDays(int days) =>
      _en ? '$days active ${days == 1 ? 'day' : 'days'}' : '$days 天活跃';
  String maximum(int level) => _en ? 'Peak level $level/5' : '最高 $level/5 级';
  String loggedDays(int days) =>
      _en ? '$days diary ${days == 1 ? 'day' : 'days'}' : '$days 天有日记';

  String mood(Mood value) => I18n.tr('diary.mood.${value.name}');

  String weekday(int day) => (_en
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : const ['一', '二', '三', '四', '五', '六', '日'])[day - 1];

  String month(DateTime date) => _en
      ? const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ][date.month - 1]
      : '${date.month}月';

  String range(DateTime start, DateTime end) =>
      '${I18nDateFormat.date(start)} – ${I18nDateFormat.date(end)}';
}
