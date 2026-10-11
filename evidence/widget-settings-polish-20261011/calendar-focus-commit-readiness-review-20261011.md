# Calendar and cached Focus commit readiness — 2026-10-11

Read-only source and evidence review. No source, test, or existing report was changed; no Flutter command, build, Git command, or AGY command ran in this pass. Current SHA-256 values for the nine Calendar paths below match `.dart_tool/task-temp-20261011/calendar-habit-search-candidate-4ce3d77-manifest.json`. The two Focus paths match the hashes in `cached-display-fh-final-acceptance-20261011.md` (`pomodoro_screen.dart`: `86c5ec8502c2d3ff7c89a0250c5c7a804ce0b71d5b7f676e356ee8e61907a718`; Focus mounted test: `120d3a9f83b5e2e19f9c07edba3b480a591e72d513059a9c0e1a462fd5ab6460`).

## Commit boundaries

**Calendar copy and retained day/week display: ready as one bounded candidate commit**, with exactly these paths:

- `lib/core/calendar_agenda_ui_copy.dart`
- `lib/widgets/calendar_month_grid.dart`
- `lib/widgets/calendar_day_agenda.dart`
- `lib/widgets/calendar_week_strip.dart`
- `test/core/calendar_agenda_ui_copy_test.dart`
- `test/widgets/calendar_cached_display_locale_test.dart`
- `test/widgets/calendar_day_timeline_static_test.dart`
- `test/widgets/calendar_drag_adjust_static_test.dart`
- `test/widgets/calendar_month_grid_static_test.dart`

**Pomodoro cached ranking repaint (F/H's H part): ready as a separate bounded candidate commit**, with exactly these paths:

- `lib/screens/pomodoro_screen.dart`
- `test/screens/focus_cached_ranking_locale_test.dart`

The Calendar commit contains F's day/week row display change; do not add those two widgets again to the Pomodoro commit. Both commits rely on the previously accepted `CalendarEventDisplayText` metadata resolver and Focus model/provider reason provenance respectively. This review does not classify those prerequisites or any Habit, Search, Todo, or whole-screen Focus localization path for these commits.

## Source findings

- Calendar day and week rows resolve generated titles and subtitles at build time. The day row uses the resolved subtitle for its height estimate, presence check, and text; the compact title also uses the resolver. The week row combines localized time and resolved subtitle but keeps its comparison on raw event titles. The mounted test records event order and `toJson()` snapshots across zh→en→zh and keeps an authored Chinese event literal.
- The new Calendar copy helper reads `I18n.current` when each label is built. Calendar screen locale listeners already trigger the relevant rebuilds. Month weekday order stays Monday first; the English count badge gets slightly narrower padding. The single-period Chinese course label becomes `第1节` instead of the prior `第1-1节`, an intentional copy change covered by the helper test.
- Day agenda filtering/account inputs (`activeTypes`, `projectKey`, `workspaceId`), event selection, Todo lookup, drag eligibility, clamping, and provider update calls remain on their existing paths. The drag change localizes feedback strings while passing through the original reminder issue and error text. Diary draft/authored title remains `entry.title`; the helper supplies only the empty-entry prompt.
- Both Pomodoro ranking sections listen for locale changes and put an immutable locale value into selector equality/hash. Entry signatures resolve `flagReasonFor(locale)`, so cached generated reasons can repaint without a provider refresh. The mounted test checks both sections, social headings/subtitles, literal remote reason retention, unchanged scores/object identity, and unchanged refresh count. Other hardcoded Focus page copy remains outside this bounded change; this is not full Focus localization.

## Evidence and limits

`calendar-latest-copy-acceptance-20261011.md` records **44 passing Calendar tests** and clean focused analysis on the detached candidate based on `4ce3d77`; the current nine path hashes match that candidate. The shared-tree mounted Calendar test did **not** run: compilation stopped before tests loaded because the unrelated `lib/core/todo_board_ui_copy.dart` still references undefined `TodoDueFilter` and `TodoCompletionFilter`. Do not label the detached run a main-tree pass. The later Calendar candidate updates the old timeline static assertion that expected `_buildCompactContent(context, e)`; it passed in the 44-test run.

`cached-display-fh-final-acceptance-20261011.md` records one passing mounted Focus test and clean scoped analysis on its detached candidate. Its older Calendar timeline static failure was the stale assertion above, now updated and passed in the later Calendar candidate. Neither report establishes a full shared-tree build, broad integration, or release readiness. No new execution was performed for this review.

## Temporary copy cleanup note

The detached verification copies `.dart_tool/task-temp-20261011/calendar-habit-search-candidate-4ce3d77` (about 176 MB) and `.dart_tool/task-temp-20261011/calendar-candidate-e80678b` (about 298 MB) are potential disk cleanup targets after confirming no active task needs them and preserving their manifests/logs. This review did not delete either directory or touch main source, evidence, or published artifacts.
