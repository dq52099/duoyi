import 'i18n.dart';
import 'todo_kanban.dart';

/// 待办模块统一文案（中英双语）。
///
/// 遵循全局文案设计原则（仿 [MainUiCopy]）：
/// - 每次 getter / function 调用动态读取 [I18n.current]，禁止在 static / init 中缓存翻译。
/// - 用户自定义内容（如待办标题、历史记录）保留原始字符，仅翻译 app-owned 文案。
class TodoUiCopy {
  TodoUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  // ---------------------------------------------------------------------------
  // 四象限 (Eisenhower Matrix)
  // ---------------------------------------------------------------------------
  static String get eisenhowerEmpty => isEn ? 'No tasks' : '暂无任务';
  static String get completed => isEn ? 'Completed' : '已完成';
  static String get overdue => isEn ? 'Overdue' : '逾期';
  static String eisenhowerMore(int count) =>
      isEn ? '+$count more...' : '+$count 更多...';

  // ---------------------------------------------------------------------------
  // 看板分组 (Kanban Group Modes)
  // ---------------------------------------------------------------------------
  static String get kanbanGroupNone => isEn ? 'No grouping' : '不分组';
  static String get kanbanGroupPriority => isEn ? 'By priority' : '按优先级';
  static String get kanbanGroupDueDate => isEn ? 'By due date' : '按截止日';
  static String get kanbanGroupTag => isEn ? 'By tag' : '按标签';
  static String get kanbanGroupList => isEn ? 'By list' : '按清单';

  static String kanbanGroupModeLabel(TodoKanbanGroupMode mode) =>
      switch (mode) {
        TodoKanbanGroupMode.none => kanbanGroupNone,
        TodoKanbanGroupMode.priority => kanbanGroupPriority,
        TodoKanbanGroupMode.dueDate => kanbanGroupDueDate,
        TodoKanbanGroupMode.tag => kanbanGroupTag,
        TodoKanbanGroupMode.list => kanbanGroupList,
      };

  // ---------------------------------------------------------------------------
  // 完成流与记录耗时 (Completion Flow & Duration Prompt)
  // ---------------------------------------------------------------------------
  static String get confirmCompleteTitle =>
      isEn ? 'Confirm completion' : '确认完成任务';
  static String confirmCompleteContent(String title) =>
      isEn ? 'Complete "$title" now?' : '现在完成“$title”吗？';
  static String get actionCancel => isEn ? 'Cancel' : '取消';
  static String get actionContinue => isEn ? 'Continue' : '继续';

  static String get recordDurationTitle => isEn ? 'Record duration' : '记录耗时';
  static String recordDurationContent(String title) => isEn
      ? 'Would you like to log how long you spent on "$title"?'
      : '要不要顺手记录一下“$title”这次花了多久？';
  static String get durationLabel => isEn ? 'Duration' : '耗时';
  static String get durationMinutesSuffix => isEn ? 'min' : '分钟';
  static String get durationHint => isEn ? 'Leave empty to skip' : '留空则跳过';
  static String get actionSkip => isEn ? 'Skip' : '跳过';
  static String get actionRecord => isEn ? 'Record' : '记录';

  static String manualDurationNote(int minutes) =>
      isEn ? 'Manual duration: $minutes min' : '手动记录耗时：$minutes 分钟';

  static String completedFeedback(String title) =>
      isEn ? 'Completed: $title' : '已完成：$title';
}
