# Heatmap final data repair — bounded source review, 2026-10-09

## Scope and verdict

Reviewed only the repaired output-key portions in `/home/ubuntu/duoyi-worktrees/heatmaps-20261009/lib/models/habit.dart` and `lib/screens/statistics_screen.dart`. Root reported production formatted/frozen and a root-only focused SDK run active. No tests, SDK tools/results/logs, other production portions or fixture files were read. Only this private report was written.

**The sole remaining data finding from `heatmap-implementation-data-audit-oct9.md` is corrected. No data source blocker remains in that bounded review.**

- `Habit.heatmapData` now emits the shared padded key with `HeatmapCalendarWindow.dateKey(date)` (`habit.dart:641`). Its count lookup separately calls the original `countForDate(date)` (`642`), preserving legacy stored completion-key semantics. Canonical chart output no longer depends on the persisted key's year padding.
- Statistics' private activity `_dateKey` now delegates to the same shared formatter (`statistics_screen.dart:671`). Accepted years0001..0999 therefore no longer produce unpadded output keys that the chart/summary cannot read.

The previously accepted window/summary, direct flex civil-day traversal, progress bands, activity weights and timestamp/calendar distinctions stand as recorded in the prior implementation report; they were not re-audited here. This confirms the source correction, not executed low-year assertions or the active SDK run's outcome. Root owns all runtime/SDK acceptance and production delivery.

**Production reads are frozen/stopped at this report completion.** No production/fixture edits, SDK/checks/builds/tests or commits occurred.
