import 'i18n.dart';
import 'i18n_date_format.dart';

/// Localized UI copy and presentation formatters for reminder and recurrence editors.
///
/// Follows project architectural constraints:
/// 1. Dynamic locale response based on [I18n.current] and [I18n.localeListenable].
/// 2. Zero dependency cycles with domain models: does not import `recurrence.dart` or `goal.dart`.
/// 3. Uncached getters that always reflect the active locale.
/// 4. Compact phrasing aligned with iOS typography and resilient at 320-width.
class ReminderEditorUiCopy {
  ReminderEditorUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  // ---------------------------------------------------------------------------
  // Shared picker semantic keys
  // ---------------------------------------------------------------------------
  static const String timePickerTitleKey = 'preferences.daily_reminder.time';
  static const String timePickerSubtitleKey =
      'preferences.daily_reminder.time_picker.subtitle';
  static const String datePickerTitleKey = 'time_audit.picker.end_date';

  // ---------------------------------------------------------------------------
  // Common sheet actions
  // ---------------------------------------------------------------------------
  static String get cancel => isEn ? 'Cancel' : '取消';
  static String get save => isEn ? 'Save' : '保存';
  static String get delete => isEn ? 'Delete' : '删除';
  static String get clear => isEn ? 'Clear' : '清除';

  // ---------------------------------------------------------------------------
  // ReminderPlanEditor
  // ---------------------------------------------------------------------------
  static String get defaultPlanTitle => isEn ? 'Reminder' : '提醒';
  static String get enableReminders => isEn ? 'Enable Reminders' : '开启提醒';
  static String get noReminders => isEn ? 'No reminders added' : '未添加提醒';
  static String get addReminder => isEn ? 'Add Reminder' : '添加提醒';
  static String get editReminder => isEn ? 'Edit Reminder' : '编辑提醒';

  // Summaries
  static String get planSummaryDisabled => isEn ? 'Off' : '已关闭';
  static String get planSummaryNoRules => isEn ? 'No active rules' : '无启用规则';

  static String planSummaryCount(int count) {
    if (isEn) {
      return count == 1 ? '1 reminder' : '$count reminders';
    }
    return '$count 条提醒';
  }

  static String get timeNotSet => isEn ? 'Time not set' : '未设置时间';

  static String advanceDurationSummary(String duration) =>
      isEn ? '$duration before' : '提前 $duration';

  static String snoozeSummary(int minutes) =>
      isEn ? 'Snooze $minutes min' : '稍后 $minutes 分钟';

  static String repeatCountSummary(int count) {
    if (isEn) {
      return count == 1 ? 'Repeat 1 time' : 'Repeat $count times';
    }
    return '重复 $count 次';
  }

  static String get disabledSummary => isEn ? 'Disabled' : '已停用';

  static String ruleTitle(String typeLabel, String kindLabel) =>
      '$typeLabel · $kindLabel';

  // ---------------------------------------------------------------------------
  // ReminderRuleSheet
  // ---------------------------------------------------------------------------
  static String get enabled => isEn ? 'Enabled' : '启用';
  static String get reminderType => isEn ? 'Reminder Type' : '提醒类型';
  static String get reminderTime => isEn ? 'Reminder Time' : '提醒时间';

  static String reminderTimeCompactSemantics(String timeStr) =>
      isEn ? 'Reminder time $timeStr' : '提醒时间 $timeStr';

  static String get advanceTime => isEn ? 'Advance Time' : '提前时间';
  static String get weekly => isEn ? 'Weekly' : '每周';
  static String get reminderMethod => isEn ? 'Reminder Method' : '提醒方式';
  static String get vibrate => isEn ? 'Vibrate' : '震动';
  static String get fullScreenReminder =>
      isEn ? 'Full-screen Reminder' : '全屏提醒';
  static String get fullScreenReminderSubtitle =>
      isEn ? 'Only applies to alarms' : '仅闹钟方式生效';

  static String get snooze => isEn ? 'Snooze' : '稍后提醒';

  static String snoozePresetLabel(int minutes) {
    if (minutes == 0) return isEn ? 'Off' : '关闭';
    return isEn ? '$minutes min' : '$minutes 分钟';
  }

  static String get repeatCount => isEn ? 'Repeat Count' : '重复次数';

  static String repeatCountPresetLabel(int count) {
    if (count == 0) return isEn ? 'No repeat' : '不重复';
    if (isEn) return count == 1 ? '1 time' : '$count times';
    return '$count 次';
  }

  // Kind & Type labels by semantic enum name
  static String ruleKindLabelByName(String kindName) {
    return switch (kindName) {
      'alarm' => isEn ? 'Alarm' : '闹钟',
      'popup' => isEn ? 'Pop-up' : '弹出框',
      'off' => isEn ? 'Off' : '关闭',
      'push' || 'email' => isEn ? 'Notification' : '通知',
      _ => isEn ? 'Notification' : '通知',
    };
  }

  static String ruleTypeLabelByName(String typeName) {
    return switch (typeName) {
      'absolute' => isEn ? 'Due reminder' : '到期提醒',
      'relativeToDue' => isEn ? 'Advance reminder' : '提前提醒',
      'dailyTime' => isEn ? 'Daily reminder' : '每日提醒',
      'weeklyTime' => isEn ? 'Weekly reminder' : '每周提醒',
      _ => isEn ? 'Reminder' : '提醒',
    };
  }

  // Weekdays (1=Mon .. 7=Sun for reminder rules, 0..6 for recurrence rules)
  static String weekdayLabel(int day) {
    if (day < 1 || day > 7) return isEn ? '?' : '周?';
    if (isEn) {
      const enNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return enNames[day - 1];
    }
    const zhNames = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${zhNames[day - 1]}';
  }

  static List<String> get weekdayNamesShort {
    if (isEn) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return const ['一', '二', '三', '四', '五', '六', '日'];
  }

  // Relative offset / Duration
  static String durationLabel(int minutes) {
    if (minutes >= 1440 && minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return isEn ? (days == 1 ? '1 day' : '$days days') : '$days 天';
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return isEn ? (hours == 1 ? '1 hour' : '$hours hours') : '$hours 小时';
    }
    return isEn ? '$minutes min' : '$minutes 分钟';
  }

  // ---------------------------------------------------------------------------
  // RecurrencePicker
  // ---------------------------------------------------------------------------
  static String get recurrenceTitle => isEn ? 'Repeat' : '重复';
  static String get recurrenceSubtitleWithMax => isEn
      ? 'Set frequency, interval, end date, and max occurrences'
      : '设置循环频率、间隔、结束日期和重复次数';
  static String get recurrenceSubtitleWithoutMax =>
      isEn ? 'Set frequency, interval, and end date' : '设置循环频率、间隔和结束日期';

  static String recurrenceFrequencyLabel(int frequencyIndex) {
    return switch (frequencyIndex) {
      0 => isEn ? 'Do not repeat' : '不重复',
      1 => isEn ? 'Daily' : '每天',
      2 => isEn ? 'Weekly' : '每周',
      3 => isEn ? 'Monthly' : '每月',
      4 => isEn ? 'Yearly' : '每年',
      _ => isEn ? 'Do not repeat' : '不重复',
    };
  }

  static String get intervalPrefix => isEn ? 'Every ' : '每';

  static String intervalUnitLabel(int frequencyIndex, int interval) {
    if (isEn) {
      return switch (frequencyIndex) {
        1 => interval == 1 ? 'day' : 'days',
        2 => interval == 1 ? 'week' : 'weeks',
        3 => interval == 1 ? 'month' : 'months',
        4 => interval == 1 ? 'year' : 'years',
        _ => '',
      };
    }
    return switch (frequencyIndex) {
      1 => '天',
      2 => '周',
      3 => '月',
      4 => '年',
      _ => '',
    };
  }

  static String get weeklyDaysLabel => isEn ? 'On days of week' : '每周哪几天';
  static String get monthlyDayPrefix => isEn ? 'Day of month ' : '每月第几天 ';
  static String get monthlyDayHint => isEn ? 'Same day' : '留空=同日';
  static String get monthlyDaySuffix => isEn ? '' : ' 日';

  static String get endDateTileTitle =>
      isEn ? 'End Date (Optional)' : '结束日期 (可选)';
  static String get endDateNever => isEn ? 'Never' : '永不结束';
  static String get clearEndDateTooltip => isEn ? 'Clear end date' : '清除结束日期';

  static String get maxOccurrencesLabel =>
      isEn ? 'Occurrences (Optional)' : '重复次数 (可选)';
  static String get maxOccurrencesHelper => isEn
      ? 'Leave empty for unlimited; e.g. 10 for 10 times'
      : '留空表示不限次数；例如 10 表示共 10 次';
  static String get clearMaxOccurrencesTooltip =>
      isEn ? 'Clear occurrences' : '清除重复次数';

  // ---------------------------------------------------------------------------
  // RecurrenceRule.label
  // ---------------------------------------------------------------------------
  static String recurrenceRuleLabel({
    required int frequencyIndex,
    required int interval,
    List<int>? byWeekdays,
    int? byMonthDay,
    DateTime? endDate,
    int? maxOccurrences,
  }) {
    if (frequencyIndex == 0) {
      return isEn ? 'Do not repeat' : '不重复';
    }
    final String base;
    if (isEn) {
      base = switch (frequencyIndex) {
        1 => interval == 1 ? 'Daily' : 'Every $interval days',
        2 => interval == 1 ? 'Weekly' : 'Every $interval weeks',
        3 => interval == 1 ? 'Monthly' : 'Every $interval months',
        4 => interval == 1 ? 'Yearly' : 'Every $interval years',
        _ => 'Do not repeat',
      };
    } else {
      base = switch (frequencyIndex) {
        1 => interval == 1 ? '每天' : '每 $interval 天',
        2 => interval == 1 ? '每周' : '每 $interval 周',
        3 => interval == 1 ? '每月' : '每 $interval 月',
        4 => interval == 1 ? '每年' : '每 $interval 年',
        _ => '不重复',
      };
    }

    final pieces = <String>[base];
    if (frequencyIndex == 2 && byWeekdays != null && byWeekdays.isNotEmpty) {
      final sorted = [...byWeekdays]..sort();
      if (isEn) {
        const enWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        pieces.add(sorted.map((d) => enWeekdays[d.clamp(0, 6)]).join('/'));
      } else {
        const zhWeekdays = ['一', '二', '三', '四', '五', '六', '日'];
        pieces.add(sorted.map((d) => zhWeekdays[d.clamp(0, 6)]).join('/'));
      }
    }
    if (endDate != null) {
      pieces.add(
        isEn ? 'Until ${formatDate(endDate)}' : '至 ${formatDate(endDate)}',
      );
    }
    if (maxOccurrences != null && maxOccurrences > 0) {
      pieces.add(
        isEn
            ? (maxOccurrences == 1
                  ? '1 time total'
                  : '$maxOccurrences times total')
            : '共 $maxOccurrences 次',
      );
    }
    return pieces.join(' · ');
  }

  static String formatDate(DateTime value) => I18nDateFormat.date(value);
}
