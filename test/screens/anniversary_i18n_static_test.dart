import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('纪念日页面固定文案迁移到 I18n', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();

    for (final key in [
      'anniversary.title',
      'anniversary.birthday',
      'anniversary.countdown_short',
      'anniversary.custom',
      'anniversary.tab.all',
      'anniversary.upcoming_30_days',
      'anniversary.empty',
      'anniversary.upcoming_empty',
      'anniversary.delete.title',
      'anniversary.delete.content_suffix',
      'anniversary.occurrence.prefix',
      'anniversary.occurrence.suffix',
      'anniversary.years_elapsed.prefix',
      'anniversary.years_elapsed.suffix',
      'anniversary.next.prefix',
      'anniversary.today_short',
      'anniversary.editor.add_title',
      'anniversary.editor.edit_title',
      'anniversary.field.title',
      'anniversary.field.title_hint',
      'anniversary.field.description',
      'anniversary.field.type',
      'anniversary.field.date_type',
      'anniversary.field.date_picker_title',
      'anniversary.field.date_picker_subtitle',
      'anniversary.field.color',
      'anniversary.lunar.year_suffix',
      'countdown.field.due_reminder',
      'countdown.field.remind_days',
      'countdown.field.remind_time',
      'countdown.reminder.closed',
      'countdown.reminder.before_prefix',
      'countdown.reminder.before_suffix',
      'calendar.solar',
      'calendar.lunar',
      'calendar.chinese_lunar_calendar',
      'calendar.corresponding_lunar',
      'calendar.corresponding_solar',
      'unit.day',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    for (final hardcoded in [
      "'新增纪念'",
      "'编辑纪念'",
      "'添加'",
      "'保存'",
      "'标题'",
      "'如：妈妈生日 / 结婚纪念日'",
      "'备注 (可选)'",
      "'类型'",
      "'⏰ 倒数日'",
      "'🎂 生日'",
      "'💞 纪念日'",
      "'🔁 自定义'",
      "'日期类型'",
      "'选择日期'",
      "'公历和农历使用独立组件'",
      "'颜色标识'",
      "'到期提醒'",
      "'关闭'",
      "'提前天数:'",
      "'提醒时间'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }

    expect(
      RegExp(r'''['"][一-龥][^'"]*['"]''').hasMatch(source),
      isFalse,
      reason:
          'anniversary_screen.dart should not contain hardcoded Chinese UI strings',
    );
  });
}
