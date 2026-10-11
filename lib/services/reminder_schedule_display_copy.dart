import '../core/i18n.dart';
import '../models/goal.dart' show ReminderKind;

enum ReminderScheduleSubject { todo, goal, habit, anniversary, countdown }

enum _DisplayShape { registered, rules, habit, dated }

/// Captured diagnostic facts, separate from delivery and cancellation identity.
/// Only explicitly owned fragments are translated; authored titles stay literal.
class ReminderScheduleDisplayCopy {
  const ReminderScheduleDisplayCopy._(
    this.subject,
    this._shape, {
    required bool defaultTitle,
    this.repeating,
    this.ruleCount,
    this.primaryKind,
    this.weekdays = const <int>[],
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
  }) : _defaultTitle = defaultTitle;

  const ReminderScheduleDisplayCopy.registered(ReminderScheduleSubject subject)
    : this._(subject, _DisplayShape.registered, defaultTitle: true);

  factory ReminderScheduleDisplayCopy.rules(
    ReminderScheduleSubject subject, {
    required bool defaultTitle,
    required bool repeating,
    required int ruleCount,
  }) {
    if ((subject != ReminderScheduleSubject.todo &&
            subject != ReminderScheduleSubject.goal) ||
        ruleCount < 1 ||
        ruleCount > _maxExactJsonInteger) {
      throw ArgumentError('Invalid reminder rule display facts');
    }
    return ReminderScheduleDisplayCopy._(
      subject,
      _DisplayShape.rules,
      defaultTitle: defaultTitle,
      repeating: repeating,
      ruleCount: ruleCount,
    );
  }

  factory ReminderScheduleDisplayCopy.habit({
    bool defaultTitle = false,
    required ReminderKind primaryKind,
    required Iterable<int> weekdays,
    int? hour,
    int? minute,
  }) {
    final days = List<int>.unmodifiable(weekdays);
    if (primaryKind == ReminderKind.off ||
        !_validWeekdays(days) ||
        !_validOptionalTime(hour, minute)) {
      throw ArgumentError('Invalid habit display facts');
    }
    return ReminderScheduleDisplayCopy._(
      ReminderScheduleSubject.habit,
      _DisplayShape.habit,
      defaultTitle: defaultTitle,
      primaryKind: primaryKind,
      weekdays: days,
      hour: hour,
      minute: minute,
    );
  }

  factory ReminderScheduleDisplayCopy.dated(
    ReminderScheduleSubject subject, {
    bool defaultTitle = false,
    required ReminderKind primaryKind,
    required DateTime at,
  }) {
    if ((subject != ReminderScheduleSubject.anniversary &&
            subject != ReminderScheduleSubject.countdown) ||
        primaryKind == ReminderKind.off ||
        !_validDate(at.year, at.month, at.day)) {
      throw ArgumentError('Invalid dated reminder display facts');
    }
    return ReminderScheduleDisplayCopy._(
      subject,
      _DisplayShape.dated,
      defaultTitle: defaultTitle,
      primaryKind: primaryKind,
      year: at.year,
      month: at.month,
      day: at.day,
      hour: at.hour,
      minute: at.minute,
    );
  }

  final ReminderScheduleSubject subject;
  final _DisplayShape _shape;
  final bool _defaultTitle;
  final bool? repeating;
  final int? ruleCount;
  final ReminderKind? primaryKind;
  final List<int> weekdays;
  final int? year;
  final int? month;
  final int? day;
  final int? hour;
  final int? minute;

  static const _maxExactJsonInteger = 9007199254740991;
  static const _baseKeys = {'schemaVersion', 'shape', 'subject', 'titleMode'};

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'shape': _shape.name,
    'subject': subject.name,
    'titleMode': _defaultTitle ? 'default' : 'literal',
    if (_shape == _DisplayShape.rules) ...{
      'repeating': repeating,
      'ruleCount': ruleCount,
    },
    if (_shape == _DisplayShape.habit) ...{
      'primaryKind': primaryKind!.name,
      'weekdays': weekdays,
      'hour': hour,
      'minute': minute,
    },
    if (_shape == _DisplayShape.dated) ...{
      'primaryKind': primaryKind!.name,
      'year': year,
      'month': month,
      'day': day,
      'hour': hour,
      'minute': minute,
    },
  };

  /// A bad optional descriptor invalidates only the descriptor, never its IDs.
  static ReminderScheduleDisplayCopy? tryFromJson(
    Object? value, {
    required String objectType,
  }) {
    if (value is! Map ||
        value['schemaVersion'] is! int ||
        value['schemaVersion'] != 1 ||
        value['subject'] is! String ||
        value['subject'] != objectType ||
        value['titleMode'] is! String ||
        (value['titleMode'] != 'default' && value['titleMode'] != 'literal')) {
      return null;
    }
    final subject = _subjectFor(objectType);
    if (subject == null) return null;
    final defaultTitle = value['titleMode'] == 'default';
    switch (value['shape']) {
      case 'registered':
        if (!_hasKeys(value, _baseKeys) || !defaultTitle) return null;
        return ReminderScheduleDisplayCopy.registered(subject);
      case 'rules':
        if (!_hasKeys(value, {..._baseKeys, 'repeating', 'ruleCount'}) ||
            (subject != ReminderScheduleSubject.todo &&
                subject != ReminderScheduleSubject.goal)) {
          return null;
        }
        final repeating = value['repeating'];
        final count = value['ruleCount'];
        if (repeating is! bool ||
            count is! int ||
            count < 1 ||
            count > _maxExactJsonInteger) {
          return null;
        }
        return ReminderScheduleDisplayCopy.rules(
          subject,
          defaultTitle: defaultTitle,
          repeating: repeating,
          ruleCount: count,
        );
      case 'habit':
        if (!_hasKeys(value, {
              ..._baseKeys,
              'primaryKind',
              'weekdays',
              'hour',
              'minute',
            }) ||
            subject != ReminderScheduleSubject.habit) {
          return null;
        }
        final kind = _activeKind(value['primaryKind']);
        final days = value['weekdays'];
        final hour = value['hour'];
        final minute = value['minute'];
        if (kind == null ||
            days is! List ||
            days.any((day) => day is! int) ||
            (hour != null && hour is! int) ||
            (minute != null && minute is! int)) {
          return null;
        }
        final weekdays = days.cast<int>();
        if (!_validWeekdays(weekdays) ||
            !_validOptionalTime(hour as int?, minute as int?)) {
          return null;
        }
        return ReminderScheduleDisplayCopy.habit(
          defaultTitle: defaultTitle,
          primaryKind: kind,
          weekdays: weekdays,
          hour: hour,
          minute: minute,
        );
      case 'dated':
        if (!_hasKeys(value, {
              ..._baseKeys,
              'primaryKind',
              'year',
              'month',
              'day',
              'hour',
              'minute',
            }) ||
            (subject != ReminderScheduleSubject.anniversary &&
                subject != ReminderScheduleSubject.countdown)) {
          return null;
        }
        final kind = _activeKind(value['primaryKind']);
        final year = value['year'];
        final month = value['month'];
        final day = value['day'];
        final hour = value['hour'];
        final minute = value['minute'];
        if (kind == null ||
            year is! int ||
            month is! int ||
            day is! int ||
            hour is! int ||
            minute is! int ||
            !_validDate(year, month, day) ||
            !_validTime(hour, minute)) {
          return null;
        }
        return ReminderScheduleDisplayCopy._(
          subject,
          _DisplayShape.dated,
          defaultTitle: defaultTitle,
          primaryKind: kind,
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
        );
      default:
        return null;
    }
  }

  ({String title, String subtitle}) render({
    required String title,
    required String subtitle,
    required Set<ReminderKind> kinds,
    required AppLocale locale,
  }) {
    final zh = locale == AppLocale.zh;
    final subjectLabel = switch (subject) {
      ReminderScheduleSubject.todo => zh ? '待办' : 'Todo',
      ReminderScheduleSubject.goal => zh ? '目标' : 'Goal',
      ReminderScheduleSubject.habit => zh ? '日常' : 'Habit',
      ReminderScheduleSubject.anniversary => zh ? '纪念日' : 'Anniversary',
      ReminderScheduleSubject.countdown => zh ? '倒数日' : 'Countdown',
    };
    final displayTitle = _defaultTitle
        ? '$subjectLabel${zh ? '提醒' : ' reminder'}'
        : title;
    final String displaySubtitle;
    switch (_shape) {
      case _DisplayShape.registered:
        displaySubtitle =
            '$subjectLabel · ${zh ? '已登记到系统提醒队列' : 'Registered with the system reminder queue'}';
      case _DisplayShape.rules:
        final channels = kinds
            .where((kind) => kind != ReminderKind.off)
            .map((kind) => _kindLabel(kind, zh))
            .toSet()
            .join(zh ? '、' : ', ');
        final cadence = repeating!
            ? (zh ? '重复提醒' : 'Repeating reminder')
            : (zh ? '一次提醒' : 'One-time reminder');
        final count = zh
            ? '$ruleCount 条规则'
            : '$ruleCount ${ruleCount == 1 ? 'rule' : 'rules'}';
        displaySubtitle =
            '$subjectLabel · $cadence · ${channels.isEmpty ? (zh ? '系统提醒' : 'System reminder') : channels} · $count';
      case _DisplayShape.habit:
        const zhDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        const enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final days = weekdays.isEmpty || weekdays.length == 7
            ? (zh ? '每天' : 'Every day')
            : weekdays
                  .map((day) => (zh ? zhDays : enDays)[day - 1])
                  .join(zh ? '、' : ', ');
        final time = hour == null
            ? (zh ? '时间未设置' : 'Time not set')
            : '${_pad(hour!)}:${_pad(minute!)}';
        displaySubtitle =
            '$subjectLabel · ${_kindLabel(primaryKind!, zh)} · $days $time';
      case _DisplayShape.dated:
        displaySubtitle =
            '$subjectLabel · ${_kindLabel(primaryKind!, zh)} · ${_pad(month!)}-${_pad(day!)} ${_pad(hour!)}:${_pad(minute!)}';
    }
    return (title: displayTitle, subtitle: displaySubtitle);
  }

  static ReminderScheduleSubject? _subjectFor(String type) => switch (type) {
    'todo' => ReminderScheduleSubject.todo,
    'goal' => ReminderScheduleSubject.goal,
    'habit' => ReminderScheduleSubject.habit,
    'anniversary' => ReminderScheduleSubject.anniversary,
    'countdown' => ReminderScheduleSubject.countdown,
    _ => null,
  };

  static ReminderKind? _activeKind(Object? kind) => switch (kind) {
    'push' => ReminderKind.push,
    'popup' => ReminderKind.popup,
    'alarm' => ReminderKind.alarm,
    'email' => ReminderKind.email,
    _ => null,
  };

  static bool _hasKeys(Map value, Set<String> keys) =>
      value.length == keys.length &&
      value.keys.every((key) => key is String && keys.contains(key));

  static bool _validWeekdays(List<int> days) =>
      days.length <= 7 &&
      days.toSet().length == days.length &&
      days.every((day) => day >= 1 && day <= 7);

  static bool _validTime(int hour, int minute) =>
      hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;

  static bool _validOptionalTime(int? hour, int? minute) =>
      (hour == null && minute == null) ||
      (hour != null && minute != null && _validTime(hour, minute));

  static bool _validDate(int year, int month, int day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return false;
    }
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static String _kindLabel(ReminderKind kind, bool zh) => switch (kind) {
    ReminderKind.push => zh ? '普通通知' : 'Notification',
    ReminderKind.popup => zh ? '弹出提醒' : 'Popup',
    ReminderKind.alarm => zh ? '闹钟提醒' : 'Alarm',
    ReminderKind.email => zh ? '邮件提醒' : 'Email',
    ReminderKind.off => zh ? '关闭' : 'Off',
  };

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
