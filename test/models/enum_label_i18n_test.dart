import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
  });

  test(
    'Mood and Weather labels localize while emojis and enum indices stay fixed',
    () {
      final moodLabels = <Mood, List<String>>{
        Mood.awesome: ['超棒', 'Great', '😄'],
        Mood.good: ['开心', 'Good', '🙂'],
        Mood.okay: ['平静', 'Calm', '😐'],
        Mood.bad: ['郁闷', 'Low', '😔'],
        Mood.terrible: ['糟糕', 'Terrible', '😢'],
      };
      final weatherLabels = <Weather, List<String>>{
        Weather.sunny: ['晴', 'Sunny', '☀️'],
        Weather.cloudy: ['多云', 'Cloudy', '⛅'],
        Weather.overcast: ['阴', 'Overcast', '☁️'],
        Weather.rain: ['雨', 'Rain', '🌧️'],
        Weather.snow: ['雪', 'Snow', '❄️'],
        Weather.wind: ['风', 'Wind', '💨'],
        Weather.fog: ['雾', 'Fog', '🌫️'],
        Weather.thunder: ['雷', 'Thunder', '⚡'],
      };

      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        final labelIndex = locale == AppLocale.zh ? 0 : 1;
        for (final entry in moodLabels.entries) {
          expect(entry.key.labelFor(locale), entry.value[labelIndex]);
          expect(entry.key.label, entry.value[labelIndex]);
          expect(entry.key.emoji, entry.value[2]);
        }
        for (final entry in weatherLabels.entries) {
          expect(entry.key.labelFor(locale), entry.value[labelIndex]);
          expect(entry.key.label, entry.value[labelIndex]);
          expect(entry.key.emoji, entry.value[2]);
        }
      }

      I18n.setLocale(AppLocale.en);
      expect(Mood.good.labelFor(AppLocale.zh), '开心');
      expect(Weather.sunny.labelFor(AppLocale.zh), '晴');
      expect(I18n.current, AppLocale.en);
      expect(Mood.good.labelFor(AppLocale.en), 'Good');
      expect(Weather.sunny.labelFor(AppLocale.en), 'Sunny');
      expect(I18n.current, AppLocale.en);

      expect(Mood.values.map((mood) => mood.index).toList(), [0, 1, 2, 3, 4]);
      expect(Weather.values.map((weather) => weather.index).toList(), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
    },
  );

  test('CalendarEventType.label 跟随当前语言', () {
    expect(CalendarEventType.event.label, '日程');
    expect(CalendarEventType.todo.label, '待办');
    expect(CalendarEventType.timeEntry.label, '时间足迹');

    I18n.setLocale(AppLocale.en);
    expect(CalendarEventType.event.label, 'Event');
    expect(CalendarEventType.todo.label, 'Task');
    expect(CalendarEventType.timeEntry.label, 'Time log');
  });

  test('TimeEntrySource.label 跟随当前语言', () {
    expect(TimeEntrySource.manual.label, '手动');
    expect(TimeEntrySource.pomodoro.label, '番茄钟');

    I18n.setLocale(AppLocale.en);
    expect(TimeEntrySource.manual.label, 'Manual');
    expect(TimeEntrySource.pomodoro.label, 'Pomodoro');
  });

  test('TimeEntryCategory.label 跟随当前语言', () {
    expect(TimeEntryCategory.focus.label, '专注');
    expect(TimeEntryCategory.other.label, '其他');

    I18n.setLocale(AppLocale.en);
    expect(TimeEntryCategory.focus.label, 'Focus');
    expect(TimeEntryCategory.other.label, 'Other');
  });

  test('TodoPriority.label 跟随当前语言', () {
    expect(TodoPriority.none.label, '无');
    expect(TodoPriority.urgent.label, '紧急');

    I18n.setLocale(AppLocale.en);
    expect(TodoPriority.none.label, 'None');
    expect(TodoPriority.urgent.label, 'Urgent');
  });
}
