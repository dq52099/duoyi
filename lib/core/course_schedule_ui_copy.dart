import 'i18n.dart';

class CourseScheduleUiCopy {
  CourseScheduleUiCopy._();

  static bool get _en => I18n.current == AppLocale.en;

  static String get importTooltip =>
      _en ? 'Import .ics / CSV timetable' : '导入 .ics / CSV 课表';

  static String get importButtonLabel =>
      _en ? 'Import (.ics / CSV)' : '导入课表 (.ics / CSV)';

  static String get importTitle =>
      _en ? 'Import Timetable (.ics / CSV)' : '导入课表 (.ics / CSV)';

  static String get importSubtitle => _en
      ? 'Pick a file or paste CSV / iCalendar (.ics) content to preview before importing.'
      : '选择文件或粘贴 CSV / iCalendar (.ics) 内容，确认预览后一键导入课表。';

  static String get pickFileLabel => _en ? 'Choose .ics / .csv File' : '选择文件';

  static String get inputHint => _en
      ? 'Paste CSV rows (Name,Weekday,StartSection,Count,Weeks,Location,Teacher)\n'
            'or BEGIN:VCALENDAR ... .ics content'
      : '粘贴 CSV（课程名,星期,起始节,节数,周次,教室,教师）\n或 BEGIN:VCALENDAR ... .ics 日历内容';

  static String get sampleCsv => _en
      ? 'Name,Weekday,StartSection,SectionCount,Weeks,Location,Teacher\n'
            'Algorithms,1,1,2,1-16,Room A201,Prof. Zhang\n'
            'English,3,3,2,1-16(odd),Room B305,Ms. Li'
      : '课程名,星期,起始节,节数,周次,教室,教师\n'
            '高等数学,一,1,2,1-16,A101,王老师\n'
            '大学英语,三,3,2,1-16(单),B203,李老师';

  static String get useSampleCsv => _en ? 'Load Sample CSV' : '填入示例 CSV';

  static String previewSummary(String format, int count) => _en
      ? 'Parsed $count course(s) ($format)'
      : '已识别 $count 门课程（${format.toUpperCase()}）';

  static String get noCoursesParsed =>
      _en ? 'No courses recognized yet.' : '暂未识别到有效课程数据。';

  static String importAction(int count) =>
      _en ? 'Import $count Course(s)' : '导入 $count 门课程';

  static String importedSuccess(int count) =>
      _en ? 'Imported $count course(s)' : '已成功导入 $count 门课程';

  static String get conflictBadge => _en ? 'Conflict' : '时间冲突';

  static String conflictWarningTitle(int count) => _en
      ? 'Time-slot conflict with $count existing course(s)'
      : '与 $count 门已有课程存在时间冲突';

  static String conflictLine(
    String name,
    String weekday,
    int startSection,
    int endSection,
    List<int> weeks,
  ) {
    final weekSummary = weeks.length > 4
        ? '${weeks.first}-${weeks.last}...'
        : weeks.join(',');
    return _en
        ? '$name · $weekday S$startSection-$endSection (weeks $weekSummary)'
        : '$name · $weekday 第$startSection-$endSection节（第$weekSummary周）';
  }

  static String importConflictNote(int count) => _en
      ? '$count imported item(s) overlap with existing schedule'
      : '其中 $count 门课程与当前课表存在时段重叠（导入后将保留冲突提示）';

  static String get reminderFieldLabel =>
      _en ? 'Pre-class Reminder' : '课前提醒';

  static String reminderOptionLabel(int minutes) {
    if (minutes <= 0) return _en ? 'Off' : '不提醒';
    return _en ? '${minutes}m before' : '提前 $minutes 分钟';
  }
}
