# Today candidate visual review

Root directly viewed all eight PNGs from the isolated `e80678b` Today
candidate with AGY's first bounded layout patch. Stable copies are in
`evidence/screenshots/today-candidate-e80678b-20261011/`.

- `calendar/`: Chinese captures at 320, 390, 430 and 1440 px. Calendar and
  date-badge surfaces retain the softened fills/shadows. Date numerals, task
  cards and metric tiles are readable; no overflow stripe was visible in
  the captured viewport. Narrow almanac summaries use existing ellipsis.
- `locale/`: English captures at 320, 390, 1120 and 1440 px with 1.6x text
  scaling. Larger metric/ring/card content fits the captured widgets.
  Narrow almanac summaries truncate; the 320 px weekly score card becomes
  tall through wrapping. English count framing still has spacing/plural
  polish to finish (for example `Habits 0times` and `1 items`).

The English captures have transparent page backgrounds (displayed black by
the image viewer), so they are bounded layout evidence and do not verify
the production page background or full-theme appearance. Their test helper
loads an additional Latin font; they do not verify AGY's production offline
font patch. These are widget captures, not Android/iOS device acceptance.
The newer Today callback/context/controller follow-up is not included.
