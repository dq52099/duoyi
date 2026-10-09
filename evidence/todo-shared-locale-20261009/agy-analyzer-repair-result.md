# Job implement-mv0h1ofg-3295bfeb (implement, done)

在 [lib/widgets/todo_completion_flow.dart](file:///home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/widgets/todo_completion_flow.dart#L77) 的确认弹窗 await 后增加最小化的直接 `context.mounted` 防护：

```dart
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => AppDialog(
        icon: const Icon(Icons.task_alt_outlined),
        title: Text(TodoUiCopy.confirmCompleteTitle),
        content: Text(TodoUiCopy.confirmCompleteContent(currentTodo.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(TodoUiCopy.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(TodoUiCopy.actionContinue),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted || !isOriginValid()) return;

  final recordMinutes = await _showRecordPrompt(
    context,
    currentTodo.title,
    initialMinutes: _initialMinutes(currentTodo),
  );
```

- **修改点**：将第 77 行守卫扩展为 `if (confirmed != true || !context.mounted || !isOriginValid()) return;`，直接满足分析器的 `use_build_context_synchronously` 要求。
- **行为保留**：保留全部原始 `isOriginValid()` 账号/生命周期复核、StatefulWidget 弹窗资源管理、`(generation, todo.id)` 键去重与双语 SnackBar 逻辑，未改动任何其它文件。

[unrestricted] Working tree is dirty after implement. Existing pre-run changes may be part of the task context.
Status entries that appeared or changed during the run:
  (none detected by porcelain status)
`git diff --stat`:
lib/core/todo_kanban.dart                       |  10 +-
 lib/providers/time_audit_provider.dart          |  47 +++++-
 lib/widgets/eisenhower_matrix.dart              | 186 ++++++++++++----------
 lib/widgets/todo_completion_flow.dart           | 196 ++++++++++++++++--------
 test/widgets/eisenhower_matrix_static_test.dart |   6 +-
 5 files changed, 281 insertions(+), 164 deletions(-)
ACTION FOR THE CALLING AGENT: inspect the current workspace (`git status --short`, `git diff`) and distinguish pre-run dirty paths from this run's delta. Continue the same agy conversation for follow-up work. If committing or opening a PR, first verify the task explicitly authorized that delivery.
