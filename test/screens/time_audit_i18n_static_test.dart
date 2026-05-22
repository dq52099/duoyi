import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('时间足迹页面固定文案迁移到 I18n', () {
    final source = File(
      'lib/screens/time_audit_screen.dart',
    ).readAsStringSync();

    for (final key in [
      'time_audit.title',
      'time_audit.add_manual',
      'time_audit.copy_report',
      'time_audit.report_copied',
      'time_audit.range.today',
      'time_audit.range.week',
      'time_audit.range.month',
      'time_audit.range.all',
      'time_audit.segment.today',
      'time_audit.view.timeline',
      'time_audit.view.category',
      'time_audit.view.calendar',
      'time_audit.view.trend',
      'time_audit.empty.suffix',
      'time_audit.category_view',
      'time_audit.source_breakdown',
      'time_audit.calendar_view',
      'time_audit.trend_view',
      'time_audit.investment_suffix',
      'time_audit.entry_count',
      'time_audit.entry_count_suffix',
      'time_audit.default_title',
      'time_audit.sheet.add_title',
      'time_audit.sheet.edit_title',
      'time_audit.field.title',
      'time_audit.field.category',
      'time_audit.field.start',
      'time_audit.field.end',
      'time_audit.field.minutes',
      'time_audit.field.note',
      'time_audit.picker.start_date',
      'time_audit.picker.start_time',
      'time_audit.picker.end_date',
      'time_audit.picker.end_time',
      'time_audit.report.title',
      'time_audit.report.range',
      'time_audit.report.total',
      'time_audit.report.category',
      'time_audit.report.details',
      'unit.hour',
      'unit.minute',
      'action.delete',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    for (final hardcoded in [
      "'时间足迹'",
      "'复制报告'",
      "'补记'",
      "'今天'",
      "'本周'",
      "'本月'",
      "'全部'",
      "'时间线'",
      "'分类'",
      "'日历'",
      "'趋势'",
      "'分类视图'",
      "'来源分布'",
      "'日历视图'",
      "'趋势视图'",
      "'记录数'",
      "'时间记录'",
      "'补记时间'",
      "'编辑时间'",
      "'标题'",
      "'开始'",
      "'结束'",
      "'分钟数'",
      "'备注'",
      "'开始日期'",
      "'开始时间'",
      "'结束日期'",
      "'结束时间'",
      "'小时'",
      "'分钟'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }

    expect(
      RegExp(r'''['"][一-龥][^'"]*['"]''').hasMatch(source),
      isFalse,
      reason:
          'time_audit_screen.dart should not contain hardcoded Chinese UI strings',
    );
  });
}
