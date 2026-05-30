import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('课程表页面固定文案迁移到 I18n', () {
    final source = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();

    for (final key in [
      'course.week.prefix',
      'course.week.suffix',
      'course.week.count_suffix',
      'course.week.current_tooltip',
      'course.empty.message',
      'course.add',
      'course.week_picker.title',
      'course.week_picker.subtitle',
      'course.weeks.all',
      'course.weeks.odd',
      'course.weeks.even',
      'course.weeks.select_all',
      'course.settings.title',
      'course.settings.subtitle',
      'course.settings.preview_prefix',
      'course.editor.add_title',
      'course.editor.edit_title',
      'course.editor.subtitle',
      'course.field.term_start',
      'course.field.term_start_picker',
      'course.field.total_weeks',
      'course.field.sessions_per_day',
      'course.field.session_minutes',
      'course.field.first_session_time',
      'course.field.first_session_time_subtitle',
      'course.field.break_minutes',
      'course.field.name',
      'course.field.teacher',
      'course.field.location',
      'course.field.weekday',
      'course.field.start_section',
      'course.field.section_count',
      'course.field.class_weeks',
      'course.field.color',
      'weekday.mon',
      'weekday.sun',
      'action.add',
      'action.save',
      'action.clear',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    expect(
      source,
      contains(
        'final selectedBackground = Color.alphaBlend(\n'
        '              cs.primary.withValues(alpha: 0.09),',
      ),
    );
    expect(source, contains('foregroundColor: selected ? cs.onSurface : null'));
    expect(
      source,
      isNot(
        contains(
          'backgroundColor: selected\n                    ? cs.primary\n',
        ),
      ),
    );
    expect(source, isNot(contains('foregroundColor: selected ? cs.onPrimary')));
    expect(source, isNot(contains('foregroundColor: selected ? cs.primary')));

    for (final hardcoded in [
      "'回到本周'",
      "'添加课表后就能看到你的一周啦'",
      "'添加课程'",
      "'选择周次'",
      "'切换当前查看的课表周'",
      "'全周'",
      "'单周'",
      "'双周'",
      "'课表设置'",
      "'调整学期起点和显示密度'",
      "'开学日期 (第 1 周的周一)'",
      "'开学日期'",
      "'总周数'",
      "'每天节数'",
      "'每节分钟数'",
      "'第一节开始时间'",
      "'课程表将按这个时间推算后续节次'",
      "'课间分钟数'",
      "'新增课程'",
      "'编辑课程'",
      "'按周次、节次和颜色整理课表'",
      "'课程名'",
      "'教师'",
      "'教室'",
      "'星期'",
      "'第几节开始'",
      "'连上几节'",
      "'上课周'",
      "'全选'",
      "'清空'",
      "'颜色'",
      "'一'",
      "'二'",
      "'三'",
      "'四'",
      "'五'",
      "'六'",
      "'日'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }
  });
}
