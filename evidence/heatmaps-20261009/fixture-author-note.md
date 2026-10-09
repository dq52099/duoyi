# Heatmap regression fixture review — 2026-10-09

Fixture-only follow-up for the heatmap calendar and extracted activity card.

## Files covered

- `test/core/heatmap_calendar_test.dart` covers Monday alignment, Sunday and
  year/leap-day boundaries, civil-date traversal, visible-range membership,
  clamped levels, strict date-key parsing, progress bands, visible-day summary
  behavior, and habit heatmap levels for positive, negative, and weekly-flex
  habits. It also checks that inactive habits do not dilute a combined daily
  progress level.
- `test/widgets/heatmap_interaction_test.dart` covers progress/activity labels,
  selection, navigation, semantics, keyboard movement, future-day exclusion,
  solar picker bounds and cancellation, zh/en state and scroll retention, and a
  dark 320 logical-pixel 52-week activity card.
- `test/widgets/mood_heatmap_test.dart` replaces the old low/high legend text
  expectations with named mood labels and adds distinct no-entry/unset-mood
  semantics, colors, and selected-date callback fixtures.
- `test/screens/statistics_comparison_static_test.dart` checks the statistics
  screen's extracted `ActivityHeatmapCard` import/use and its localized copy.

The existing note was absent when inspected, so this file was created. No
Flutter tests, SDK commands, builds, formatting, or other checks were run.
