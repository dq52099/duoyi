# Three heatmap refinement — 2026-10-09

## Delivered

- Habit, activity and mood share a Monday-aligned calendar, restrained flat cells, actual month boundaries, consistent weekday rows, horizontal scrolling and today/selection markers. The 52-week chart starts at the recent end once; locale changes preserve selection and scroll.
- Tap, keyboard arrows/Home/End and 48px previous/next/date-picker/Today controls inspect dates. Future slots are neither counted nor interactive. Diary date inspection offers an explicit open/write action using existing diary routes.
- Habit copy describes normalized progress levels; flexible habits retain whole-period progress. Activity remains the existing weighted score clipped to0–5; its summary matches precisely the displayed start..today dates. Neither is an event-count or exact-percent label.
- Mood keeps the five existing theme-aware categorical palettes and named bilingual labels. No diary and diary-without-mood have distinct labels/colors. Legends, dates and controls wrap at narrow widths and enlarged text.
- Civil-day traversal fixes DST skips/duplicates in the grid, producers and direct flex-progress callees. Instant activity sources convert to device-local dates; declared diary and completion dates preserve calendar affiliation. Strict completion-key parsing rejects ghost dates. Presentation keys use padded years while legacy habit count lookup stays intact.

## Verification

- 135 focused checks across21 files passed.
- 1121 integrated regressions across104 files passed; 116 targeted analysis items were clean.
- 14 calendar/producer checks passed under America/New_York, including DST-sensitive civil dates and actual UTC instant attribution.
- Nine readable synthetic snapshots cover all three charts: Chinese light390px, English dark390px, English dark320px at2x text. Root inspected all nine; paths and hashes are retained. These are Flutter harness captures, not device screenshots.
- Earlier failures remain visible in raw logs. Repairs include narrow mood-legend flex, offscreen picker/row/trend navigation in fixtures, correct calendar-range expectation, current semantics API/lifetime, and whitespace/obsolete const assumptions in existing static fixtures. The earlier clean source reproduced two const-matcher failures before this batch; no behavior assertion was dropped.

## Remaining scope

No public APK, web deployment or remote push was performed. Android/iOS launcher, real-device performance and accessibility acceptance remain unverified. Full native publication-store wiring, pending reminder locale refresh and other unmerged route work belong to the continuing project objective; this batch does not mark that objective complete.
