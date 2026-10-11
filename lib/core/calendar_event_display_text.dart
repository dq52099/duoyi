import '../models/calendar_event.dart';
import '../models/time_entry.dart';
import 'i18n.dart';

/// Helper to resolve live localized title and subtitle for system-generated calendar events,
/// while strictly preserving user-authored data (e.g. course name/location/teacher,
/// custom pomodoro titles, notes, and imported ICS descriptions).
class CalendarEventDisplayText {
  CalendarEventDisplayText._();

  static bool get _isEn => I18n.current == AppLocale.en;

  /// Resolves the event title, localizing system-generated fallback titles live.
  static String resolveTitle(CalendarEvent event) {
    final meta = event.displayMetadata;
    if (meta is PomodoroDisplayMetadata && meta.isFallbackTitle) {
      return _isEn ? 'Focus ${meta.minutes} min' : '专注 ${meta.minutes} 分钟';
    }
    return event.title;
  }

  /// Resolves the event subtitle, localizing system-generated state/progress/unit descriptions live.
  static String? resolveSubtitle(CalendarEvent event) {
    final meta = event.displayMetadata;
    if (meta is TodoDisplayMetadata) {
      if (meta.dueDate == null) return null;
      final due = meta.dueDate!;
      final h = due.hour.toString().padLeft(2, '0');
      final m = due.minute.toString().padLeft(2, '0');
      final formatted = '${due.month}/${due.day} $h:$m';
      return _isEn ? 'Due $formatted' : '截止 $formatted';
    }
    if (meta is PomodoroDisplayMetadata) {
      return formatDuration(meta.durationSeconds);
    }
    if (meta is TimeEntryDisplayMetadata) {
      return '${meta.category.label} · ${formatDuration(meta.durationSeconds)}';
    }
    if (meta is AnniversaryDisplayMetadata) {
      if (meta.yearsPassed == null) {
        return _isEn
            ? 'In ${meta.daysRemaining} days'
            : '还有 ${meta.daysRemaining} 天';
      } else {
        final count = meta.yearsPassed! + 1;
        return _isEn ? 'Time #$count' : '第 $count 次';
      }
    }
    if (meta is CountdownDisplayMetadata) {
      if (meta.daysRemaining >= 0) {
        return _isEn
            ? 'In ${meta.daysRemaining} days'
            : '还有 ${meta.daysRemaining} 天';
      } else {
        final passed = -meta.daysRemaining;
        return _isEn ? '$passed days ago' : '已过 $passed 天';
      }
    }
    if (meta is GoalDisplayMetadata) {
      if (meta.isAchieved) {
        return _isEn ? 'Achieved' : '已达成';
      } else {
        return _isEn
            ? 'Progress ${meta.progressPercent}%'
            : '进度 ${meta.progressPercent}%';
      }
    }
    if (meta is CourseDisplayMetadata) {
      final parts = <String>[
        _isEn ? 'Week ${meta.week}' : '第 ${meta.week} 周',
        _isEn
            ? 'Section ${meta.startSection}-${meta.endSection}'
            : '第${meta.startSection}-${meta.endSection}节',
        meta.timeRangeLabel,
      ];
      if (meta.location.isNotEmpty) parts.add(meta.location);
      if (meta.teacher.isNotEmpty) parts.add(meta.teacher);
      return parts.join(' · ');
    }
    if (meta is DiaryDisplayMetadata) {
      return I18n.tr(meta.moodKey);
    }

    return event.subtitle;
  }

  /// Formats duration in seconds to localized string (e.g. "25 min" / "25分钟", "1 hr" / "1小时").
  static String formatDuration(int seconds) {
    if (seconds >= 3600) {
      final hours = seconds / 3600;
      final val = hours.toStringAsFixed(seconds % 3600 == 0 ? 0 : 1);
      return _isEn ? '$val ${_hourUnit(val)}' : '$val小时';
    }
    final minutes = seconds / 60;
    final val = minutes.toStringAsFixed(seconds % 60 == 0 ? 0 : 1);
    return _isEn ? '$val min' : '$val分钟';
  }

  static String _hourUnit(String val) => val == '1' ? 'hr' : 'hrs';
}
