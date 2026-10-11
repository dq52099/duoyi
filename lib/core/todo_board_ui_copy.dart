import '../models/todo.dart';
import 'i18n.dart';
import 'todo_filters.dart';
import 'todo_kanban.dart';

/// 待办看板、列表与筛选统一文案（中英双语）。
///
/// 遵循全局文案设计原则：
/// - 每次 getter / function 调用动态读取 [I18n.current]，禁止在 static / init 中缓存翻译。
/// - 用户自定义内容（如待办标题、标签名、清单名）保留原始字符，仅翻译 app-owned 文案。
/// - 零依赖循环：保持纯文案层。
class TodoBoardUiCopy {
  TodoBoardUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // 批量操作反馈与对话框 (Batch Actions Feedback & Dialogs)
  // ---------------------------------------------------------------------------
  static String batchCompleted(int count) =>
      isEn ? 'Completed $count tasks' : '已完成 $count 个任务';

  static String batchReopened(int count) =>
      isEn ? 'Restored $count tasks to incomplete' : '已恢复 $count 个任务为未完成';

  static String batchMoved(int count, String targetLabel) => isEn
      ? 'Moved $count tasks to $targetLabel'
      : '已移动 $count 个任务到$targetLabel';

  static String batchPriorityUpdated(int count) =>
      isEn ? 'Updated priority for $count tasks' : '已更新 $count 个任务优先级';

  static String batchDeleted(int count) =>
      isEn ? 'Deleted $count tasks' : '已删除 $count 个任务';

  static String get deleteSelectedTasksTitle =>
      isEn ? 'Delete selected tasks' : '删除所选任务';

  static String deleteSelectedTasksContent(int count) => isEn
      ? 'Are you sure you want to delete $count tasks? Related time logs will also be removed.'
      : '确认删除 $count 个任务吗？相关时间足迹也会同步移除。';

  static String get cancel => isEn ? 'Cancel' : '取消';
  static String get delete => isEn ? 'Delete' : '删除';

  static String batchModeSelected(int count) =>
      isEn ? 'Selected $count items' : '已选择 $count 项';

  static String batchSelected(int count) =>
      isEn ? 'Selected $count' : '已选 $count';

  static String get batchProcessing => isEn ? 'Processing...' : '处理中...';
  static String get batchComplete => isEn ? 'Complete' : '完成';
  static String get batchRestore => isEn ? 'Restore' : '恢复';
  static String get batchMoveTo => isEn ? 'Move to' : '移动到';
  static String get batchPriority => isEn ? 'Priority' : '优先级';

  static String get exitBatchModeTooltip => isEn ? 'Exit batch mode' : '退出批量操作';

  static String selectAllTooltip(bool allSelected) => allSelected
      ? (isEn ? 'Deselect all' : '取消全选')
      : (isEn ? 'Select all in view' : '全选当前视图');

  static String get batchActionsTooltip => isEn ? 'Batch actions' : '批量操作';
  static String get batchManageTooltip => isEn ? 'Batch manage' : '批量管理';

  // ---------------------------------------------------------------------------
  // 顺延逾期任务 (Postpone Overdue)
  // ---------------------------------------------------------------------------
  static String postponeOverdueFeedback(int count) =>
      isEn ? 'Postponed $count overdue tasks' : '已顺延 $count 个逾期任务';

  static String get postponeAction => isEn ? 'Postpone' : '顺延';

  // ---------------------------------------------------------------------------
  // 添加待办面板 (Add Task Sheet)
  // ---------------------------------------------------------------------------
  static String get taskHint => isEn
      ? 'What needs to be done? e.g. Meeting tomorrow at 3 PM'
      : '准备做什么？例如：明天下午3点开会';

  static String get aiBreakdown => isEn ? 'AI breakdown' : 'AI 智能拆解';
  static String get aiBreakdownFailed =>
      isEn ? 'AI breakdown failed' : 'AI 拆解失败';

  static String get listType => isEn ? 'List type' : '清单类型';
  static String get priority => isEn ? 'Priority' : '优先级';
  static String get priorityFlag => isEn ? 'Priority flag' : '优先级标记';

  static String get quadrantQ1WithEmoji =>
      isEn ? '🔴 Urgent & Important (Q1)' : '🔴 重要且紧急 (Q1)';
  static String get quadrantQ2WithEmoji =>
      isEn ? '🟠 Important, Not Urgent (Q2)' : '🟠 重要不紧急 (Q2)';
  static String get quadrantQ3WithEmoji =>
      isEn ? '🔵 Urgent, Not Important (Q3)' : '🔵 紧急不重要 (Q3)';
  static String get quadrantQ4WithEmoji =>
      isEn ? '⚪ Not Urgent, Not Important (Q4)' : '⚪ 不重要不紧急 (Q4)';

  static String get reminder => isEn ? 'Reminder' : '提醒';
  static String reminderAt(String time) =>
      isEn ? 'Reminder at · $time' : '到点提醒 · $time';
  static String get noReminder => isEn ? 'No reminder' : '不提醒';
  static String get selectTime => isEn ? 'Select time' : '选择时间';
  static String get selectReminderTime =>
      isEn ? 'Select reminder time' : '选择提醒时间';
  static String get addTask => isEn ? 'Add task' : '添加任务';

  static String get sharedSpaceReadOnly => isEn
      ? 'You only have view permission in this shared space'
      : '你在这个共享空间中只有查看权限';

  static String get reminderRegisterFailed =>
      isEn ? 'Failed to schedule todo reminder' : '待办提醒注册失败';

  static String get localSavedText =>
      isEn ? 'Todo saved to this device' : '待办已保存到本机';

  static String localSavedWithoutReminder(String issue) => isEn
      ? 'Todo saved to this device, but reminder not scheduled: $issue'
      : '待办已保存到本机，但提醒未注册：$issue';

  static String get createFailed =>
      isEn ? 'Failed to create, please try again later' : '创建失败，请稍后重试';

  // ---------------------------------------------------------------------------
  // 智能识别预览 (Smart Date Preview)
  // ---------------------------------------------------------------------------
  static String detectedDate(String date) =>
      isEn ? 'Detected: $date' : '识别到：$date';

  // ---------------------------------------------------------------------------
  // 视图切换 (View Switcher)
  // ---------------------------------------------------------------------------
  static String get viewMatrix => isEn ? 'Matrix' : '四象限';
  static String get viewList => isEn ? 'List' : '列表';
  static String get viewKanban => isEn ? 'Kanban' : '看板';

  // ---------------------------------------------------------------------------
  // 今日摘要卡 (Today Summary Card)
  // ---------------------------------------------------------------------------
  static String get todaySummaryChipToday => isEn ? 'Today' : '今日';
  static String get todaySummaryChipFilterTodayTooltip =>
      isEn ? 'Filter today tasks' : '筛选今日待办';
  static String get todaySummaryChipKey => isEn ? 'Key' : '重点';
  static String get todaySummaryChipOverdue => isEn ? 'Overdue' : '逾期';
  static String get todaySummaryChipFilterOverdueTooltip =>
      isEn ? 'Filter overdue tasks' : '筛选逾期待办';

  static String todayRemainingTasks(int remaining) =>
      isEn ? '$remaining tasks remaining today' : '今日还要完成 $remaining 项';

  static String todaySummaryBreakdown(int daily, int todo, int goal) => isEn
      ? 'Habits $daily / Todos $todo / Goals $goal'
      : '日常 $daily / 待办 $todo / 目标 $goal';

  static String chipSemantics(String label, String value) =>
      isEn ? '$label todos $value' : '$label待办 $value';

  // ---------------------------------------------------------------------------
  // 云同步横幅 (Cloud Sync Notice Banner)
  // ---------------------------------------------------------------------------
  static String syncNoticeError(String message) => isEn
      ? 'Todo saved locally, but server sync failed: $message. It will retry automatically once connected or re-logged in.'
      : '本机待办已保存，但服务器同步失败：$message。恢复网络或重新登录后会自动重试。';

  static String syncNoticeWarning(String message) => isEn
      ? 'Todo saved locally, server sync is pending: $message. It will retry automatically once connected or re-logged in.'
      : '本机待办已保存，服务器同步暂未完成：$message。恢复网络或重新登录后会自动重试。';

  static String syncNoticeInfo(String message) => isEn
      ? 'Todo saved locally, cloud sync is queued: $message'
      : '本机待办已保存，云同步正在排队：$message';

  // ---------------------------------------------------------------------------
  // 筛选条与空结果 (Filter Bar & Empty State)
  // ---------------------------------------------------------------------------
  static String customViewTitle(int filtered, int total) =>
      isEn ? 'Custom view · $filtered/$total' : '自定义视图 · $filtered/$total';

  static String get clear => isEn ? 'Clear' : '清空';
  static String get filterTodayOverview => isEn ? 'Today overview' : '今日概览';
  static String get filterToday => isEn ? 'Today' : '今日';
  static String get filterOverdue => isEn ? 'Overdue' : '逾期';
  static String get filterNext7Days => isEn ? 'Within 7 days' : '7天内';
  static String get filterCompleted => isEn ? 'Completed' : '已完成';
  static String get filterQuadrant => isEn ? 'Quadrant' : '象限';
  static String get filterAllQuadrants => isEn ? 'All quadrants' : '全部象限';
  static String get filterPriority => isEn ? 'Priority' : '优先级';
  static String get filterAllPriorities => isEn ? 'All priorities' : '全部优先级';
  static String get filterDate => isEn ? 'Date' : '日期';

  static String filterDueLabel(TodoDueFilter filter) => switch (filter) {
    TodoDueFilter.all => isEn ? 'All dates' : '全部日期',
    TodoDueFilter.overdue => isEn ? 'Overdue' : '逾期',
    TodoDueFilter.dueToday => isEn ? 'Today' : '今日',
    TodoDueFilter.next7Days => isEn ? 'Next 7 days' : '未来7天',
    TodoDueFilter.noDue => isEn ? 'No date' : '无日期',
  };

  static String get filterCompletionStatus => isEn ? 'Status' : '完成状态';

  static String filterCompletionLabel(TodoCompletionFilter filter) =>
      switch (filter) {
        TodoCompletionFilter.all => isEn ? 'All tasks' : '全部任务',
        TodoCompletionFilter.active => isEn ? 'Incomplete' : '未完成',
        TodoCompletionFilter.completed => isEn ? 'Completed' : '已完成',
      };

  static String get filterTag => isEn ? 'Tag' : '标签';
  static String get filterAllTags => isEn ? 'All tags' : '全部标签';
  static String get filterList => isEn ? 'List' : '清单';
  static String get filterAllLists => isEn ? 'All lists' : '全部清单';

  static String get noMatchingTasks => isEn ? 'No matching tasks' : '没有匹配任务';
  static String get adjustFiltersHint =>
      isEn ? 'Adjust custom view filters or clear all' : '调整自定义视图条件或清空筛选';
  static String get clearFilters => isEn ? 'Clear filters' : '清空筛选';

  // ---------------------------------------------------------------------------
  // 看板控制与卡片 (Kanban Board Controls & Cards)
  // ---------------------------------------------------------------------------
  static String kanbanGrouping(String groupLabel) =>
      isEn ? 'Grouping: $groupLabel' : '看板分组：$groupLabel';

  static String get kanbanReleaseToMoveHere =>
      isEn ? 'Release to move here' : '松手移动到这里';

  static String get kanbanNoTasks => isEn ? 'No tasks' : '暂无任务';

  static String get kanbanColumnSettingsTooltip =>
      isEn ? 'Column settings' : '看板列设置';

  static String get deleteTaskDialogTitle => isEn ? 'Delete task?' : '删除任务？';

  static String deleteTaskDialogContent(String title) => isEn
      ? 'Delete "$title"? Related time logs will also be removed.'
      : '将删除“$title”，相关时间足迹也会同步移除。';

  static String get moveToTooltip => isEn ? 'Move to' : '移动到';

  static String get cardCompletedBadge => isEn ? 'Completed' : '已完成';
  static String get cardOverdueBadge => isEn ? 'Overdue' : '过期';
  static String get cardDueSoonBadge => isEn ? 'Due soon' : '临期';

  static String cardSubtasksBadge(int completed, int total) =>
      isEn ? '$completed/$total subtasks' : '$completed/$total 子任务';

  static String columnTitle(TodoKanbanColumn column) {
    if (column.builtIn) {
      if (column.id == defaultKanbanPendingColumnId) {
        return isEn ? 'To Do' : '待处理';
      }
      if (column.id == defaultKanbanInProgressColumnId) {
        return isEn ? 'In Progress' : '进行中';
      }
      if (column.id == defaultKanbanDoneColumnId) {
        return isEn ? 'Completed' : '已完成';
      }
    }
    return column.title;
  }

  // ---------------------------------------------------------------------------
  // 看板列设置 (Kanban Column Settings Sheet)
  // ---------------------------------------------------------------------------
  static String get kanbanSettingsTitle =>
      isEn ? 'Kanban Column Settings' : '看板列设置';

  static String get kanbanSettingsSubtitle => isEn
      ? 'Adjust column order, colors and default grouping'
      : '调整列顺序、颜色和默认分组';

  static String get save => isEn ? 'Save' : '保存';

  static String get defaultGroupingLabel => isEn ? 'Default grouping' : '默认分组';

  static String get defaultGroupingHelper => isEn
      ? 'Tasks within columns can be grouped by priority, due date, tag or list'
      : '列内可按优先级、截止日、标签或清单分组';

  static String get columnNameLabel => isEn ? 'Column name' : '列名称';
  static String get moveUpTooltip => isEn ? 'Move up' : '上移';
  static String get moveDownTooltip => isEn ? 'Move down' : '下移';

  static String get builtInColumnCannotDelete =>
      isEn ? 'Built-in columns cannot be deleted' : '内置列不可删除';

  static String get deleteColumnTooltip => isEn ? 'Delete column' : '删除列';
  static String get addColumn => isEn ? 'Add column' : '新增列';
  static String get newColumnDefaultTitle => isEn ? 'New column' : '新列';
  static String get untitledColumn => isEn ? 'Untitled column' : '未命名列';

  static String get deleteColumnDialogTitle =>
      isEn ? 'Delete kanban column' : '删除看板列';

  static String deleteColumnDialogContent(String title) => isEn
      ? 'Are you sure you want to delete "$title"? Tasks in this column will be moved back to "To Do".'
      : '确认删除「$title」吗？该列上的任务会移回「待处理」。';

  // ---------------------------------------------------------------------------
  // 四象限 (Eisenhower Quadrants)
  // ---------------------------------------------------------------------------
  static String quadrantLabel(EisenhowerQuadrant q) => switch (q) {
    EisenhowerQuadrant.urgentImportant => isEn ? 'Urgent & Important' : '重要且紧急',
    EisenhowerQuadrant.notUrgentImportant =>
      isEn ? 'Important, Not Urgent' : '重要不紧急',
    EisenhowerQuadrant.urgentNotImportant =>
      isEn ? 'Urgent, Not Important' : '紧急不重要',
    EisenhowerQuadrant.notUrgentNotImportant =>
      isEn ? 'Not Urgent, Not Important' : '不重要不紧急',
  };

  static String get quadrantDetailEmpty =>
      isEn ? 'No tasks in this quadrant' : '这个象限没有任务';

  // ---------------------------------------------------------------------------
  // 共享清单与清单分组 (Shared Lists & List Groups)
  // ---------------------------------------------------------------------------
  static String sharedWorkspacePrefix(String workspaceName) =>
      isEn ? 'Shared: $workspaceName' : '共享：$workspaceName';

  static String get shareListTooltip => isEn ? 'Share list' : '共享清单';
  static String get shareListDialogTitle => isEn ? 'Share List' : '共享清单';

  static String shareListDialogSubtitle(String groupName) =>
      isEn ? 'Assign "$groupName" to a shared space' : '把「$groupName」标记到共享空间';

  static String get onlyMyselfVisible =>
      isEn ? 'Visible only to myself' : '仅自己可见';

  static String workspaceMemberInfo(int count, String roleLabel) =>
      isEn ? '$count members · $roleLabel' : '$count 位成员 · $roleLabel';

  static String get shareStatusUpdated =>
      isEn ? 'Sharing status updated' : '共享状态已更新';

  static String get dragToReorderTooltip => isEn ? 'Drag to reorder' : '拖拽排序';

  // ---------------------------------------------------------------------------
  // 任务行划卡操作与徽章 (Tile Swipe & Metadata Badges)
  // ---------------------------------------------------------------------------
  static String get swipeRestore => isEn ? 'Restore' : '恢复';
  static String get swipeComplete => isEn ? 'Complete' : '完成';
  static String get swipeDelete => isEn ? 'Delete' : '删除';

  static String restoredFeedback(String title) =>
      isEn ? 'Restored: $title' : '已恢复：$title';

  static String get badgeCompleted => isEn ? 'Completed' : '已完成';
  static String get badgeDueSoon => isEn ? 'Due soon' : '临期';
  static String get badgeOverdue => isEn ? 'Overdue' : '过期';

  static String badgeTargetMinutes(int minutes) =>
      isEn ? 'Target ${minutes}m' : '目标 ${minutes}m';

  static String badgeNextReminder(String time) =>
      isEn ? 'Next $time' : '下次 $time';

  static String get badgeShared => isEn ? 'Shared' : '共享';
}
