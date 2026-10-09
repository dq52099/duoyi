import 'dart:convert';

import '../core/brand_strings.dart';
import '../core/i18n.dart';
import '../models/goal.dart' show ReminderKind, ReminderRuleType;

enum _ReminderSubject { todo, goal, habit, anniversary, countdown }

/// Immutable reminder facts. Rendering changes owned copy, never user content.
class ReminderDeliveryCopy {
  const ReminderDeliveryCopy._(
    this._subject,
    this.userTitle, {
    this.type = ReminderRuleType.absolute,
    this.kind = ReminderKind.push,
    this.days = 0,
    this.semanticPush = false,
  });

  const ReminderDeliveryCopy.todo(String title, ReminderRuleType type)
    : this._(_ReminderSubject.todo, title, type: type);

  const ReminderDeliveryCopy.goal(
    String title,
    ReminderRuleType type,
    ReminderKind kind,
  ) : this._(_ReminderSubject.goal, title, type: type, kind: kind);

  const ReminderDeliveryCopy.habit(String name, {bool semanticPush = false})
    : this._(_ReminderSubject.habit, name, semanticPush: semanticPush);

  const ReminderDeliveryCopy.anniversary(
    String title,
    int daysBefore,
    ReminderKind kind,
  ) : this._(_ReminderSubject.anniversary, title, days: daysBefore, kind: kind);

  const ReminderDeliveryCopy.countdown(String title, int daysRemaining)
    : this._(_ReminderSubject.countdown, title, days: daysRemaining);

  final _ReminderSubject _subject;
  final String userTitle;
  final ReminderRuleType type;
  final ReminderKind kind;
  final int days;
  final bool semanticPush;

  static const _schemaVersion = 1;
  static const _maxExactJsonInteger = 9007199254740991;
  static const _descriptorKeys = {
    'schemaVersion',
    'subject',
    'userTitle',
    'type',
    'kind',
    'days',
    'semanticPush',
  };

  /// Persist semantic facts independently of rendered copy and its fingerprint.
  Map<String, Object?> toJson() {
    if (days < -_maxExactJsonInteger || days > _maxExactJsonInteger) {
      throw RangeError.range(
        days,
        -_maxExactJsonInteger,
        _maxExactJsonInteger,
        'days',
      );
    }
    return {
      'schemaVersion': _schemaVersion,
      'subject': _subject.name,
      'userTitle': userTitle,
      'type': type.name,
      'kind': kind.name,
      'days': days,
      'semanticPush': semanticPush,
    };
  }

  /// Unknown or incomplete descriptors cannot safely own a copy refresh.
  ///
  /// Callers must retain their original registration and cancellation identity
  /// when this returns null; do not infer facts from rendered text or reschedule.
  static ReminderDeliveryCopy? tryFromJson(Object? value) {
    if (value is! Map ||
        value.length != _descriptorKeys.length ||
        value.keys.any(
          (key) => key is! String || !_descriptorKeys.contains(key),
        )) {
      return null;
    }
    final version = value['schemaVersion'];
    final subject = value['subject'];
    final title = value['userTitle'];
    final rawType = value['type'];
    final rawKind = value['kind'];
    final days = value['days'];
    final semanticPush = value['semanticPush'];
    if (version is! int ||
        version != _schemaVersion ||
        subject is! String ||
        title is! String ||
        rawType is! String ||
        rawKind is! String ||
        days is! int ||
        days < -_maxExactJsonInteger ||
        days > _maxExactJsonInteger ||
        semanticPush is! bool) {
      return null;
    }
    final type = switch (rawType) {
      'absolute' => ReminderRuleType.absolute,
      'relativeToDue' => ReminderRuleType.relativeToDue,
      'dailyTime' => ReminderRuleType.dailyTime,
      'weeklyTime' => ReminderRuleType.weeklyTime,
      _ => null,
    };
    final kind = switch (rawKind) {
      'push' => ReminderKind.push,
      'alarm' => ReminderKind.alarm,
      'email' => ReminderKind.email,
      'popup' => ReminderKind.popup,
      'off' => ReminderKind.off,
      _ => null,
    };
    if (type == null || kind == null) return null;
    switch (subject) {
      case 'todo':
        if (kind != ReminderKind.push || days != 0 || semanticPush) return null;
        return ReminderDeliveryCopy.todo(title, type);
      case 'goal':
        if (days != 0 || semanticPush) return null;
        return ReminderDeliveryCopy.goal(title, type, kind);
      case 'habit':
        if (type != ReminderRuleType.absolute ||
            kind != ReminderKind.push ||
            days != 0) {
          return null;
        }
        return ReminderDeliveryCopy.habit(title, semanticPush: semanticPush);
      case 'anniversary':
        if (type != ReminderRuleType.absolute || semanticPush) return null;
        return ReminderDeliveryCopy.anniversary(title, days, kind);
      case 'countdown':
        if (type != ReminderRuleType.absolute ||
            kind != ReminderKind.push ||
            semanticPush) {
          return null;
        }
        return ReminderDeliveryCopy.countdown(title, days);
      default:
        return null;
    }
  }

  /// A locale-neutral identity; JSON avoids collisions in literal user strings.
  String get semanticFingerprint => jsonEncode([
    _subject.name,
    userTitle,
    type.name,
    kind.name,
    days,
    semanticPush,
  ]);

  ({String title, String body}) render({
    required AppLocale locale,
    required BrandStrings strings,
  }) {
    final zh = locale == AppLocale.zh;
    switch (_subject) {
      case _ReminderSubject.todo:
        final repeating =
            type == ReminderRuleType.dailyTime ||
            type == ReminderRuleType.weeklyTime;
        return (
          title: repeating
              ? strings.notifTodoDueTitle
              : '${zh ? '提醒：' : 'Reminder: '}$userTitle',
          body: userTitle,
        );
      case _ReminderSubject.goal:
        final prefix = switch (kind) {
          ReminderKind.alarm => '⏰',
          ReminderKind.email => '✉️',
          ReminderKind.off => '🔕',
          ReminderKind.popup || ReminderKind.push => '🔔',
        };
        final label = switch (type) {
          ReminderRuleType.absolute => zh ? '目标提醒' : 'Goal reminder',
          ReminderRuleType.relativeToDue =>
            zh ? '目标提前提醒' : 'Upcoming goal reminder',
          ReminderRuleType.dailyTime => zh ? '每日目标提醒' : 'Daily goal reminder',
          ReminderRuleType.weeklyTime => zh ? '每周目标提醒' : 'Weekly goal reminder',
        };
        return (title: '$prefix $label', body: userTitle);
      case _ReminderSubject.habit:
        return (
          title: strings.notifHabitRemindTitle,
          body: semanticPush
              ? '${zh ? '别忘了: ' : "Don't forget: "}$userTitle'
              : zh
              ? '$userTitle 到时间了，点开确认打卡'
              : 'Time for $userTitle. Open to check in.',
        );
      case _ReminderSubject.anniversary:
        final prefix = switch (kind) {
          ReminderKind.alarm => '⏰',
          ReminderKind.popup => '🔔',
          _ => '📅',
        };
        return (
          title: '$prefix ${zh ? '纪念日提醒' : 'Anniversary reminder'}',
          body: days == 0
              ? '${zh ? '今天是 ' : 'Today is '}$userTitle'
              : zh
              ? '$days 天后是 $userTitle'
              : '$userTitle is in $days ${days == 1 ? 'day' : 'days'}.',
        );
      case _ReminderSubject.countdown:
        final distance = zh
            ? days >= 0
                  ? '还有 $days 天'
                  : '已过 ${-days} 天'
            : days >= 0
            ? '$days ${days == 1 ? 'day' : 'days'} to go'
            : '${-days} ${days == -1 ? 'day' : 'days'} ago';
        return (
          title: zh ? '🔔 倒数日提醒' : '🔔 Countdown reminder',
          body: '$userTitle · $distance',
        );
    }
  }
}
