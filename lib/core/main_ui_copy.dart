import 'i18n.dart';

/// 用户主页面统一文案（中英双语）。
///
/// 遵循全局文案设计原则：
/// - 基于 [I18n.current] 动态区分中英文
/// - 明确区分「无数据 / 筛选无结果 / 全部完成 / 未安排」，避免 0/0 或 0% 误导
/// - 专注计时准确描述「运行 / 暂停 / 休息 / 尚未开始」
/// - 异常统一收敛为用户可读提示，避免直接输出 raw exception / stack trace
class MainUiCopy {
  MainUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  // ---------------------------------------------------------------------------
  // 日历 (Calendar)
  // ---------------------------------------------------------------------------
  static String get calendarTitle => isEn ? 'Calendar' : '日历';
  static String get calendarMenu => isEn ? 'Calendar options' : '日历菜单';
  static String get calendarBackToToday => isEn ? 'Today' : '回到今天';
  static String get calendarPickDate => isEn ? 'Select date' : '选择日期';
  static String get calendarViewMonth => isEn ? 'Month view' : '月视图';
  static String get calendarViewWeek => isEn ? 'Week view' : '周视图';
  static String get calendarViewDay => isEn ? 'Day view' : '日视图';
  static String get calendarViewThreeDay => isEn ? '3-Day view' : '三日视图';
  static String get calendarViewYear => isEn ? 'Year view' : '年视图';

  static String get calendarPrevMonth => isEn ? 'Previous month' : '上一月';
  static String get calendarNextMonth => isEn ? 'Next month' : '下一月';
  static String get calendarPrevWeek => isEn ? 'Previous week' : '上一周';
  static String get calendarNextWeek => isEn ? 'Next week' : '下一周';
  static String get calendarPrevDay => isEn ? 'Previous day' : '上一天';
  static String get calendarNextDay => isEn ? 'Next day' : '下一天';
  static String get calendarPrevThreeDays => isEn ? 'Previous 3 days' : '前三天';
  static String get calendarNextThreeDays => isEn ? 'Next 3 days' : '后三天';
  static String get calendarPrevYear => isEn ? 'Previous year' : '上一年';
  static String get calendarNextYear => isEn ? 'Next year' : '下一年';

  static String get calendarNoEventsDay =>
      isEn ? 'No events scheduled for this day' : '当天暂无日程安排';
  static String get calendarNoEventsDayFilter =>
      isEn ? 'No events matching filter' : '当前筛选下无日程';
  static String get calendarEmptyFilterHint =>
      isEn ? 'Try adjusting or clearing your filters' : '可尝试调整筛选或查看其他日期';
  static String get calendarEmptyDayHint =>
      isEn ? 'Tap + to quickly add an event or todo' : '点击 + 可快速添加日程或待办';

  static String get calendarNoEventsWeek =>
      isEn ? 'No events scheduled this week' : '本周暂无日程安排';
  static String get calendarNoEventsWeekFilter =>
      isEn ? 'No events matching filter this week' : '当前筛选下本周暂无日程';

  static String get calendarStatusCompleted => isEn ? 'Completed' : '已完成';
  static String get calendarStatusOverdue => isEn ? 'Overdue' : '逾期';

  // ---------------------------------------------------------------------------
  // 习惯 (Habit)
  // ---------------------------------------------------------------------------
  static String get habitNoHabits => isEn ? 'No habits yet' : '暂无习惯';
  static String get habitNoScheduleToday =>
      isEn ? 'No habits scheduled today' : '今日未安排打卡';
  static String get habitAllCompletedToday =>
      isEn ? 'All habits completed today' : '今日全部完成';
  static String get habitNotScheduled => isEn ? 'Not scheduled' : '未安排';
  static String get habitUpcoming => isEn ? 'Upcoming' : '未开始';
  static String get habitCompleted => isEn ? 'Completed' : '全部完成';
  static String get habitDone => isEn ? 'Done' : '已达标';
  static String get habitNotDone => isEn ? 'Incomplete' : '未达标';
  static String get habitEmptyDayDetail =>
      isEn ? 'No active habits on this day' : '当天暂无活跃习惯';

  // ---------------------------------------------------------------------------
  // 专注 (Pomodoro)
  // ---------------------------------------------------------------------------
  static String get pomodoroStatusNotStarted => isEn ? 'Ready' : '尚未开始';
  static String get pomodoroStatusFocusing => isEn ? 'Focusing' : '专注中';
  static String get pomodoroStatusPaused => isEn ? 'Paused' : '已暂停';
  static String get pomodoroStatusResting => isEn ? 'On Break' : '休息中';
  static String get pomodoroStatusBreakPaused =>
      isEn ? 'Break Paused' : '休息已暂停';

  static String get pomodoroActionStartFocus => isEn ? 'Start focus' : '开始专注';
  static String get pomodoroActionPauseFocus => isEn ? 'Pause focus' : '暂停专注';
  static String get pomodoroActionResumeFocus => isEn ? 'Resume focus' : '继续专注';
  static String get pomodoroActionStartBreak => isEn ? 'Start break' : '开始休息';
  static String get pomodoroActionPauseBreak => isEn ? 'Pause break' : '暂停休息';
  static String get pomodoroActionResumeBreak => isEn ? 'Resume break' : '继续休息';
  static String get pomodoroActionReset => isEn ? 'Reset timer' : '重置计时';
  static String get pomodoroActionSkip => isEn ? 'Skip session' : '跳过本轮';
  static String get pomodoroActionFinishCountUp =>
      isEn ? 'Finish session' : '结束计时';

  static String get pomodoroFreeTimer => isEn ? 'Free Timer' : '自由计时';
  static String get pomodoroCountdownMode => isEn ? 'Focus timer' : '倒计时专注';
  static String pomodoroRemainingPercent(int percent) =>
      isEn ? '$percent% left' : '剩余 $percent%';
  static String get pomodoroSelectTask => isEn ? 'Select content' : '选择本轮内容';
  static String get pomodoroEditRecord => isEn ? 'Edit record' : '编辑记录';
  static String get pomodoroDeleteRecord => isEn ? 'Delete record' : '删除记录';

  // ---------------------------------------------------------------------------
  // 待办 (Todo)
  // ---------------------------------------------------------------------------
  static String get todoNoMatchingTasks =>
      isEn ? 'No matching tasks' : '没有匹配任务';
  static String get todoAdjustFiltersPrompt =>
      isEn ? 'Adjust your filters or clear them' : '调整自定义视图条件或清空筛选';
  static String get todoClearFilters => isEn ? 'Clear filters' : '清空筛选';
  static String get todoAllCompleted => isEn ? 'All completed' : '全部完成';
  static String get todoNotificationNotReady =>
      isEn ? 'System notification not ready' : '系统通知未就绪';
}
