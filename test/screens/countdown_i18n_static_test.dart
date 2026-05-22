import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('倒数日页面固定文案迁移到 I18n', () {
    final source = File('lib/screens/countdown_screen.dart').readAsStringSync();

    for (final key in [
      'countdown.title',
      'countdown.empty',
      'countdown.add_record',
      'countdown.nearest.empty',
      'countdown.nearest.prefix',
      'countdown.nearest.days_prefix',
      'countdown.summary.total',
      'countdown.summary.within_7_days',
      'countdown.list.title',
      'countdown.list.subtitle',
      'countdown.category.default',
      'countdown.editor.add_title',
      'countdown.editor.edit_title',
      'countdown.editor.subtitle',
      'countdown.field.title',
      'countdown.field.category',
      'countdown.field.target_date',
      'countdown.field.due_reminder',
      'countdown.field.remind_days',
      'countdown.field.remind_time',
      'countdown.reminder.closed',
      'countdown.reminder.before_prefix',
      'countdown.reminder.before_suffix',
      'countdown.status.pinned',
      'countdown.status.expired',
      'countdown.status.soon',
      'countdown.status.running',
      'countdown.target.prefix',
      'countdown.days.elapsed',
      'countdown.days.remaining',
      'unit.day',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    for (final hardcoded in [
      "'倒数日'",
      "'暂无倒数日记录'",
      "'添加记录'",
      "'暂无即将到期的事件'",
      "'总数'",
      "'全部倒数日'",
      "'按优先级和剩余天数排序'",
      "'添加倒数日'",
      "'编辑倒数日'",
      "'事件名称'",
      "'目标日期'",
      "'到期提醒'",
      "'提醒时间'",
      "'置顶'",
      "'已过期'",
      "'倒数中'",
      "'已过'",
      "'天'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }
  });
}
