# Todo batch-copy bounded source review — 2026-10-11

## Decision and scope

**Accept the actual partial Todo batch-copy change for a bounded commit. No blocking account, selection, or current-state regression was introduced by the reviewed diff.** This decision accepts the copy dependency and the small existing AGY-generated integration; it does not accept full Todo localization.

Reviewed files:

- `lib/screens/todo_screen.dart`: the current tracked diff is 25 added and 18 removed lines, limited to the copy import, locale-derived-cache invalidation, five batch-feedback calls, and the batch-delete dialog's live locale builder.
- `lib/core/todo_board_ui_copy.dart`: the untracked copy helper, including root's required `todo_filters.dart` import and formatting repair. Its broader strings are mostly not yet wired into TodoScreen.

This was a read-only source review. No production/test edits, tests, builds, browser/device checks, AGY calls, or Git delivery were performed. Only this evidence report and the prior widget audit's supplied-result update were written.

## Findings supporting the bounded acceptance

### Selection and action boundary

The batch completion, reopen, quadrant move, priority, and delete changes replace only the success-message function (`todo_screen.dart:290–357`). Their provider method calls and arguments are unchanged. The existing `_runBatchAction` still checks the submitting flag, snapshots selected IDs into a new Set, ignores an empty set, awaits the selected provider action, checks `mounted`, exits batch mode, and displays feedback (`361–378`). The copy helper contains no provider access, selected-ID mutation, account lookup, asynchronous work, or storage writes.

Feedback is evaluated after the awaited action through `message(count)`, and every relevant helper method reads `I18n.current` at that call (`todo_board_ui_copy.dart:15–45`). A locale change while the action waits therefore affects the success text without redirecting the provider action or changing its ID snapshot. This diff does not introduce a new authority check or alter provider lookup timing; this acceptance is not an independent certification of all pre-existing account-switch behavior.

### Live delete confirmation

The new `ValueListenableBuilder<AppLocale>` listens to `I18n.localeListenable` and rebuilds the title, content, and button copy in the existing dialog route (`todo_screen.dart:327–352`). The displayed count remains the value captured when that dialog opened. Cancel and Delete still pop the same `dialogCtx` with `false` and `true`; the existing `confirmed != true || !mounted` guard and batch action remain after the await (`353–357`). The listener builder does not read a new TodoProvider, refresh selected IDs, or mutate account state. Changing locale while the dialog is visible therefore updates its copy without reopening or confirming the route.

### Locale-derived cache

`_onLocaleChanged` now sets `_derived = null` before its existing mounted rebuild (`todo_screen.dart:182–184`). `_derivedDataFor` treats that null as a cache miss and recomputes from the current provider/filter/config (`150–170`). The change does not modify `_filter`, `_kanbanConfig`, `_selectedTodoIds`, `_batchMode`, or `_batchSubmitting`. The existing listener removal in `dispose` is preserved (`262–268`). Source supports cache refresh while retaining the current selection and filter.

### Copy dependency

The direct `todo_filters.dart` import (`todo_board_ui_copy.dart:3`) supplies the `TodoDueFilter` and `TodoCompletionFilter` types used by the helper's exhaustive switches (`193–208`). The imported filter file defines those enums directly (`todo_filters.dart:4–6`). The helper's getters/functions remain pure copy operations that read the current locale and preserve interpolated caller values. The import repair introduces no lifecycle, data, or action dependency.

## Explicit localization limits

The current screen calls the helper only for the reviewed batch feedback and delete confirmation. Its remaining sheets, filters, board labels, and quadrant detail wiring are still frontend work. Adding a complete copy helper does not make those consumers localized.

One limit affects a reviewed call: `_moveSelected` uses `TodoBoardUiCopy.batchMoved(count, _quadrantLabel(quadrant))` (`todo_screen.dart:307`), and the existing `_quadrantLabel` still returns Chinese text for all four quadrants (`3343–3353`). Thus English currently produces a translated move prefix with a Chinese destination label, for example `Moved 2 tasks to 重要且紧急`. This is accepted only as partial feedback copy; it must not be described as complete English batch-move wording. The pending frontend quadrant wiring can supply `TodoBoardUiCopy.quadrantLabel` later.

No mounted test of locale switching inside this batch-delete dialog or during these batch actions was executed for this review. Source correctness and broad integration checks do not establish that specific live-dialog interaction or every existing account-switch case.

## Existing integration evidence

The two audited source hashes match the existing integration evidence exactly:

| File | SHA-256 |
| --- | --- |
| `lib/core/todo_board_ui_copy.dart` | `68f97bad9ef01cdf3b63cc1a3e0262804cf4142f54cb7c23fb40f4134cd9136a` |
| `lib/screens/todo_screen.dart` | `22508abd9c1cf00a8c1af0a6529294296b7f90fce07e881ca7ebe69ac208495d` |

`main-calendar-search-focus-integration-20261011.md` records the accepted main-tree run, now **16 serial suites / 80 passing tests**, including the original 15 suites / 74 tests and six subsequent Android widget frame static checks. These are overlapping totals, not 154 distinct tests. The four Todo suites are filters (5), kanban core (8), filter static checks (6), and mounted kanban view behavior (8). The 24-item scoped analyzer includes both reviewed Todo sources and those four tests, reports no issues, and exits 0. Pre/post source hashes match.

These results establish integration/dependency health and the named existing behavior checks; they do not claim exhaustive Todo copy coverage or a new targeted batch/account/locale test. The accepted source and evidence are suitable for a partial batch-copy commit while the remaining frontend work stays pending.
