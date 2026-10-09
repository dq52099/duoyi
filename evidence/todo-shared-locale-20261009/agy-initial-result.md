## What I changed

- [lib/core/todo_ui_copy.dart](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/todo_ui_copy.dart): 新建 [`TodoUiCopy`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/todo_ui_copy.dart#L9) 纯文案类，仿 [`MainUiCopy`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/main_ui_copy.dart#L10) 模式通过动态 getter/function 响应 [`I18n.current`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/i18n.dart#L17) 提供四象限、看板分组模式、完成确认及耗时弹窗/反馈的双语字符串，不缓存任何静态翻译。
- [lib/core/todo_kanban.dart](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/todo_kanban.dart): 将 [`TodoKanbanGroupModeX.label`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/todo_kanban.dart#L22) 接线至 [`TodoUiCopy.kanbanGroupModeLabel`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/todo_ui_copy.dart#L32)，保持既有 `storageKey`、enum 顺序、内置/自定义列结构与持久化序列化不变。
- [lib/widgets/eisenhower_matrix.dart](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/widgets/eisenhower_matrix.dart): 在 [`EisenhowerMatrix.build`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/widgets/eisenhower_matrix.dart#L32) 外层接入局部的 `ValueListenableBuilder<AppLocale>` 监听 [`I18n.localeListenable`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/i18n.dart)，并将卡片内“暂无任务”、“已完成/逾期”、“+N 更多...”替换为 [`TodoUiCopy`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/core/todo_ui_copy.dart#L9) 动态文案，保持原有拖拽、权限、大字号缩放比例与视觉样式。
- [lib/widgets/todo_completion_flow.dart](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/widgets/todo_completion_flow.dart): 为活跃中的完成确认弹窗和耗时记录弹窗增加局部 `ValueListenableBuilder<AppLocale>`，支持语言切换时标题、正文、动作和输入框实时刷新且不丢失输入内容、光标、焦点与路由状态；新记录耗时说明使用当前语言，`SnackBar.content` 通过局部 builder 实时更新且不重播或延长计时。

## How I verified it

依照任务说明与主审分工，本工作树执行环境未运行任何测试、Flutter、Android、Gradle 或代码格式化 SDK 命令。

Host 环境在后续集成时可运行以下命令验证本批次改动：
```bash
flutter test test/widgets/todo_shared_locale_state_test.dart
flutter test test/core/todo_kanban_test.dart
flutter test test/widgets/todo_completion_flow_test.dart
flutter test test/widgets/eisenhower_matrix_test.dart
```

已通过 `git diff` 与 `git status` 核对改动范围与格式，确认仅变更了指定生产文件，未引入无意缩进或多余改动。

## Notes

- **状态与输入保留**：[`_showRecordPrompt`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/widgets/todo_completion_flow.dart#L124) 在弹窗外层维护 `TextEditingController` 与 `FocusNode`，并在 `try ... finally` 中可靠释放；弹窗内部仅对文本装饰层重绘，不会重新创建控制器或丢弃焦点。
- **用户内容字符保真**：用户任务标题（如带中英、全角半角标点的原始标题）在完成确认提示、耗时提示与 SnackBar 中均直接插值保留，未做任何文本截断或规范化重写。
- **剩余文案与状态边界说明**：
  - 看板的默认列标题（如“待处理”、“进行中”、“已完成”）及自定义看板列标题仍保留其存储时数据模型，按要求留待下一批 caller 接线批次处理。
  - [`TodoScreen`](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/screens/todo_screen.dart) 及其他业务页面、主页面路由级 listener 仍在主工作流顺序集成中，未在本次差异中编辑。
  - 本次未提交、未推送，不代表全局国际化全量覆盖或真实移动设备端到端验收已完成。

[unrestricted] agy modified the working tree. `git diff --stat`:
lib/core/todo_kanban.dart             |  10 +--
 lib/widgets/eisenhower_matrix.dart    |  26 +++++--
 lib/widgets/todo_completion_flow.dart | 133 +++++++++++++++++++---------------
 3 files changed, 97 insertions(+), 72 deletions(-)
New untracked files: lib/core/todo_ui_copy.dart, test/widgets/todo_shared_locale_state_test.dart
ACTION FOR THE CALLING AGENT: inspect the current workspace (`git status --short`, `git diff`) and distinguish pre-run dirty paths from this run's delta. Continue the same agy conversation for follow-up work. If committing or opening a PR, first verify the task explicitly authorized that delivery.
