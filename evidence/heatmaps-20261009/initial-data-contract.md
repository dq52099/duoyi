# Three heatmaps — data contract source audit, 2026-10-09

## Scope and result

Read-only review in `/home/ubuntu/duoyi-worktrees/heatmaps-20261009`, root-provided HEAD `1f00a46`. Reviewed the two habit intensity producers, their direct progress/calendar callees, the habit/mood renderers and call sites, statistics activity producer/summary, and diary/session/time-entry date definitions. Repository AGENTS instructions were read. HEAD was not independently checked. No production/fixture edits, SDK/checks/builds/tests, commit or delegation occurred. Only this private report was written; root owns all heatmap production.

**Recommended contract:** share one Monday-aligned calendar window and date eligibility across all three heatmaps, while keeping habit progress, weighted activity and categorical mood as separate metrics. Current source requires interval/summary, calendar traversal and semantic-copy corrections; the underlying stored records and metric definitions can be preserved.

## 1. Existing findings that affect the implementation

### Visible interval and statistics summary disagree

- `HabitProvider.combinedHeatmap` (`lib/providers/habit_provider.dart:397–418`) and `Habit.heatmapData` (`lib/models/habit.dart:632–660`) produce a rolling N×7 days ending now.
- `HabitHeatmap` (`lib/widgets/habit_heatmap.dart:47–50`, `117–125`) and `MoodHeatmap` (`lib/widgets/mood_heatmap.dart:50–57`, `94–109`) display N Monday-starting columns, including a partial current week. Their eligible date interval therefore has only `7 × (N−1) + today.weekday` dates.
- Statistics `_ActivityHeatmapCard._visibleValues` (`lib/screens/statistics_screen.dart:4413–4423`) summarizes rolling N×7 dates instead of those rendered dates. Up to six older, off-grid days affect activeDays/maxIntensity. On a Friday with N=2, the chart's eligible dates are the previous Monday through today (12 dates), while the current summary also includes the preceding Saturday/Sunday (14 dates).
- The habit producer's extra older keys are currently ignored by the chart; the summary mismatch is observable even without DST. The statistics heatmap's fixed 52-week window is also independent of the screen's week/month/year report selector; preserve that explicit scope rather than suggesting its summary follows the selected report period.

### Elapsed days are used where civil calendar days are required

The producers, both renderers and statistics summary use `add/subtract(Duration(days: ...))`. These operations move by elapsed 24-hour units. Across local DST changes, midnight can become 23:00/01:00, repeated calendar keys or missing dates can appear, and `date == today` / `date.isAfter(today)` can misclassify a current-day cell.

The habit heatmap's flex path also reaches `Habit.periodBoundsForDate` (`521–532`) and `completionCountInRange` (`663–673`), both of which use elapsed-day traversal. Fixing only the outer grid will leave flex period ratios susceptible to DST errors. This direct heatmap call chain is the narrow additional model surface to correct; unrelated report/streak/trend traversal is not a prerequisite for the three-heatmap change.

### Numeric intensity is mislabeled as event count

`HabitHeatmap` tooltip (`133`) says `$intensity 次`. That value is a 0–5 quantized progress level for habits and a clipped weighted score for statistics. Neither is an event count. Statistics already labels its maximum as a level (`4457`), which is the appropriate unit.

### Mood states are collapsed and its legend implies quantity

`MoodHeatmap` uses `entry?.mood` for both color and tooltip (`109–119`), so absent diary and diary-with-null-mood both become “无记录”. Its “少/多” legend (`136–166`) implies numeric amount, although Mood is five named categories. The model explicitly allows `Mood?` and defines diary.date as a calendar affiliation whose year/month/day are authoritative (`lib/models/diary_entry.dart:62–64`). The input map already preserves entry presence separately from nullable mood.

## 2. Shared visible-window contract

Use a small shared calendar helper/window descriptor; a proposed path is `lib/core/heatmap_calendar.dart`. It should own date generation/key formatting and eligibility, without reading providers or changing stored models.

Accepted invariants:

1. **N is positive.** Preserve current call-site defaults: habit overview/mood 12, habit detail 20, activity 52. Handle invalid N consistently before generating layout or dividing by N.
2. **Capture today once per snapshot/build.** Producer, chart and its own summary consume the same normalized local calendar today/window. Optional referenceDate/window parameters can preserve existing public call signatures; independently calling DateTime.now in each layer permits a midnight mismatch.
3. **Monday alignment:** `monday = DateTime(today.year, today.month, today.day − (today.weekday − 1))`; `start = DateTime(monday.year, monday.month, monday.day − 7 × (N−1))`.
4. **Calendar construction for shifts:** generate date i with `DateTime(start.year, start.month, start.day + i)`, not elapsed Duration arithmetic. Carry month/year overflow through the constructor. Compare/date-key by calendar year/month/day; do not rely on two instants being equal.
5. **Grid and eligible interval differ intentionally:** there are N×7 stable Monday–Sunday grid positions. The eligible interval is start through today inclusive, with `7 × (N−1) + today.weekday` distinct calendar keys. Remaining positions in the last column are future placeholders, excluded from record lookup, summary counts and interactive record semantics.
6. **One iterator for summaries and rendering:** derive eligibleDates from the same window. Do not create a second rolling-range formula or summarize all incoming map values. Older/future input keys cannot affect any displayed-interval summary.
7. **Timestamp versus calendar affiliation:** for actual instants (todo completedAt, focus session endTime, time-entry startAt), convert to current device local time before deriving the calendar key. For habit completion keys and diary.date, retain their declared calendar affiliation; do not timezone-shift a user-selected diary date or reinterpret a habit date key as a UTC instant.
8. **Strict parsed date keys:** replace statistics `_parseDateKey` normalization (`672–679`) with a format/range/round-trip-valid parse. The current `DateTime(year, month, day)` accepts malformed calendar values by rolling them into another month. Invalid keys should be ignored at this presentation boundary, not rewritten into a new stored completion date.

When timestamp filtering is necessary, use a local constructor for the next calendar day's exclusive boundary. Avoid `23:59:59` truncation or a 24-hour addition. This audit does not require replacing unrelated screen report bounds.

## 3. Habit progress contract — preserve the existing metric

`activeForDate` is the existing inclusive start/end-date and weekday eligibility rule (`Habit:446–452`, `516–517`). The combined producer must average only habits active on that date; an empty active set stays level 0. An inactive habit must not enter the denominator.

Existing progress definitions to retain:

| Habit case | Ratio used by the heatmap |
| --- | --- |
| Positive daily target | `count / target`, clamped to 0..1 |
| Negative habit | zero recorded setbacks → 1; positive recorded count → 0 |
| Flexible positive habit | existing completed-day count / period target, clamped to 0..1 |
| Combined habits | arithmetic mean of each active habit's progressForDate |

The existing quantizer is `ratio <= 0 ? 0 : ceil(ratio × 5).clamp(1, 5)`. Retain a shared version of this calculation across both producers. Its bands are 0, (0,.2], (.2,.4], (.4,.6], (.6,.8], (.8,1]. **Level 5 is not proof of 100% completion**; for example a ratio above .8 can already quantize to 5. Do not infer an exact percentage as `level × 20` or count level-5 cells as fully completed without the underlying ratio.

Flex progress is currently a whole-period aggregate repeated across active dates in that period (`flexProgressForDate:553–562`, `completionCountInRange:663–673`); it is not a history of the ratio achieved as of each cell's date. Preserve that metric in this narrow change and describe it as period progress. Do not truncate its aggregation to the visible chart start or silently switch to daily count/cumulative-by-cell semantics. A policy to cap period data at today would likewise be a separate, explicit metric change.

Habit tooltip/legend should say **progress level**, optionally showing a separately supplied actual ratio/target description. A summary may count eligible visible dates with progress >0. Call that “days with progress”, not “check-ins”: a successful negative habit can have zero records and a full progress level. If a summary needs due-day counts, derive a separate active-habit/date predicate rather than assuming all zero cells were missed obligations.

## 4. Activity contract — preserve weighted score, not event count

The current producer (`statistics_screen.dart:630–667`) adds the following weights before clipping each day's score to 0..5:

| Source | Existing attribution and weight |
| --- | --- |
| Completed todo with completedAt | completedAt local calendar day, +2 |
| Habit completion record on an active date | recorded count, positive amounts only |
| Focus Pomodoro session | endTime local calendar day, +2 |
| Time entry | startAt local calendar day, +2 at >=60 minutes, otherwise +1 |
| Diary | its declared diary date, +1 even when mood is null |

Accepted narrow behavior is to preserve these weights and source-attribution rules, then clip the score. Do not substitute habit progress levels into this sum, divide it into percentages, split cross-midnight records into daily duration without a separate decision, or claim it counts unique events. The existing composite can include both a focus session and a corresponding time-entry record; no deduplication guarantee was established here. The current time-entry rule gives even a zero-duration record +1; changing that eligibility is an explicit data-policy choice, not required by the shared-window fix.

A negative habit with no recorded setback can yield high habit progress but zero activity contribution; a recorded setback can contribute activity while producing zero habit progress. This follows the separate meanings of the two charts.

Activity summary must use only eligibleDates: `activeDays = count(level > 0)`, `maxLevel = maximum(level)` (0 for an empty/all-zero result). Label tooltip and maximum as **activity level / weighted activity**, not number of completions. Any total-event or raw-score summary would require its own uncapped/raw data contract; summing clipped levels cannot provide an event count.

Reuse of HabitHeatmap should carry an explicit metric/presentation mode or equivalent typed renderer data so that habit and activity get the correct tooltips and legends. Shared geometry must not force a single metric meaning.

## 5. Mood contract — categorical states and honest counts

Keep all five enum values and their stored ordering unchanged: awesome, good, okay, bad, terrible. Use named mood labels/colors, with no conversion to the progress/activity 0–5 scale and no less/more amount legend.

Every eligible visible day has one of three meaningful data states:

- no entriesByDate key → **no diary entry**;
- DiaryEntry exists and mood is null → **diary recorded, mood not set**;
- DiaryEntry exists with mood → the corresponding named mood category.

Future grid slots are a separate ineligible state. “Mood not set” must not be treated as no diary, okay mood or a numeric zero. Neutral colors may be related, but their tooltip/semantics and a visible marker should distinguish the two missing-data cases.

If a chart-window summary is added, derive it from eligibleDates and the authoritative entriesByDate map: `entryDays` counts any present entry; `moodDays` counts present non-null mood; `unsetMoodDays = entryDays − moodDays`; `noEntryDays = eligibleDateCount − entryDays`. Category counts sum to moodDays. Do not count a null-mood diary in a mood category or exclude it from diary-recorded days. `DiaryProvider.entriesByDate` (`72–79`) already gives a read-only one-entry-per-key projection; use that same projection for both cells and counts.

DiaryScreen's existing month count/streak cards (`128–148`) are separate period metrics. They need not be changed, but must not be relabeled as summaries of the N-week heatmap.

## 6. Specific implementation paths

| Path | Narrow responsibility |
| --- | --- |
| proposed `lib/core/heatmap_calendar.dart` | Shared captured-today Monday window, calendar shifts, valid date keys and eligible-date iteration |
| `lib/providers/habit_provider.dart` | combinedHeatmap uses the shared eligible window; preserves active-only denominator and ratio quantizer |
| `lib/models/habit.dart` | heatmapData uses the shared window/quantizer; replace elapsed-day traversal in its direct flex periodBoundsForDate/completionCountInRange callees without changing period/count meaning |
| `lib/widgets/habit_heatmap.dart` | Shared-window geometry, future eligibility and today marker; progress versus weighted-activity tooltip/legend mode |
| `lib/screens/statistics_screen.dart` | Preserve activity weights with correct local-instant keys/valid completion keys; pass one window to card/chart; summary consumes exactly eligibleDates |
| `lib/widgets/mood_heatmap.dart` | Same geometry/window; categorical legend; distinct no-entry/null-mood semantics and any visible-window counts |
| `lib/screens/habit_screen.dart`, `lib/screens/habit_detail_screen.dart`, `lib/screens/diary_screen.dart` | Pass coherent snapshot/window where needed; retain 12/20/12 defaults and existing provider/literal data |

`lib/providers/diary_provider.dart`, `lib/models/diary_entry.dart`, `lib/models/pomodoro.dart` and `lib/models/time_entry.dart` were read to establish contracts. They do not require a production change for this narrow implementation. Do not modify stored completion counts, diary content/dates, mood enum indices, activity records or IDs to achieve the presentation alignment.

## 7. Later bounded acceptance evidence

Root owns later verification; none was performed here. Useful cases are Monday/Friday/Sunday with N=1/2 and existing defaults; year/month/leap boundaries; DST forward/back transitions with one key per civil day; same captured today across producer/chart/summary; off-grid old/future activity excluded from counts; positive partial/over-target, negative zero/setback and flex-period progress; weighted scores capped at 5; absent diary versus null mood versus every mood; and malformed completion keys not normalized into ghost activity.

## Source fingerprints and final freeze

| Main reviewed path | SHA-256 |
| --- | --- |
| `lib/providers/habit_provider.dart` | `9456f305c74e83d0c2196ed8c427eb249cbd8ca787fcc6b5fd21ff76537ed4be` |
| `lib/models/habit.dart` | `4655c9b302a43fd50b0b5ce083a880e7a42bef10c83fe7629f739aedd143f75f` |
| `lib/screens/statistics_screen.dart` | `0e17d8f2c5f1aa5145adc855fa139055135a92cc2a62f0710560521e031133e6` |
| `lib/widgets/habit_heatmap.dart` | `9a04ba3c55ca6c816d7dad764da9a395422dfd041415e8d245e776a0894fa10c` |
| `lib/widgets/mood_heatmap.dart` | `69ed6ba885388c36417d1e0cb7eedc801e9bcbae8e28c7c3be4aa34e452c293e` |

**Production reads are frozen/stopped at report completion.** Only this private report was changed; root retains all production ownership.
