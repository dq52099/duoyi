# Search retained-locale acceptance — 2026-10-11

## Accepted implementation

The mounted Search screen listens for locale changes and removes that listener on disposal. Switching zh → en → zh repaints app-owned labels and generated diary titles while keeping the query, cached hits, authored titles, dates, result order, and highlighted search text. The existing search provider is not queried again for a locale-only repaint.

Opening a Todo hit captures `AccountLocalDataCleaner.accountDataGeneration` before constructing the lazy route. The existing Todo detail boundary receives that captured generation rather than looking up a later account's generation in the route builder.

## Verification

The current main-tree integration run passed `search_retained_locale_test.dart` (**1 mounted test**) and `search_screen_static_test.dart` (**1 source-contract test**). Both are included in the recorded **16 suites / 80 tests**; they are not additional tests. Main-tree scoped analysis was clean, and production hashes remained unchanged.

The mounted fixture checks retained query/hits, generated versus authored diary titles, dates, highlights, provider-read count, navigation/back, and safe locale changes after disposal. The Todo opening-account check is static source evidence, not a mounted account-switch test. Candidate-only Search results were subsequently repeated successfully in main.

Evidence: `main-calendar-search-focus-integration-20261011.md` and its `10-search_retained_locale_test.log`, `11-search_screen_static_test.log`, scoped analyzer log, and pre/post hashes. Accepted Search source SHA-256: `2e75864a367ed8cb8f8fbe037c008513729fe7d44bbd73ee0be35d3ee0486c77`.

This slice does not accept the separate failing Habit regression, full global localization, or a new build/deployment.
