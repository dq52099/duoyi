# Shared picker localization — 2026-10-09

## Implemented

Date and time sheets update their existing mounted UI on Chinese/English locale changes. Semantic titleKey/subtitleKey parameters resolve at build time; explicit custom title/subtitle literals retain their exact text. Defaults, actions, month/weekday display, navigation tooltips, ignore-year controls, lunar labels and time presets use localized copy.

English lunar years retain cultural Ganzhi information through ASCII Romanized stem/branch pairs (for example Bing-Wu); Chinese keeps its original Ganzhi text. Both year-wheel labels and preview use the same helper. No date conversion or stored user value is rewritten.

## Executed verification

- 36 focused checks passed, including five mounted-sheet behavior tests: zh → en → zh with retained solar date/viewed month/lunar mode/ignore-year; live semantic headings and exact literal headings; minute-step rounding and time wheel controller identity/position; one-time confirmation, cancel-null and listener disposal.
- 878 integrated Flutter regressions across 68 files passed, including the verified widget display and day-boundary baseline.
- Focused Dart analysis passed. Frozen source/fixture hashes stayed unchanged during acceptance commands.
- [source-audit.md](source-audit.md), exact logs and [verification.json](verification.json) retain scope and current evidence. Earlier fixture compile/finder failures are retained; production was not changed to satisfy those erroneous assertions.

## Remaining work

Existing caller strings must migrate to semantic keys, and main routes/edit overlays still need live copy with drafts/tabs/scroll retained. Original lunar leap selection and range limitations are separate. Mine/Profile, all-route iOS visual acceptance and real device smoothness remain open.

This batch was committed locally for integration; it did not publish an APK or replace the website, and it does not establish full global localization.
