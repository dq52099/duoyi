# iOS widget snapshot validation — 2026-10-08

## Changes

- Reject Boolean, fractional, nonfinite, overflowing and unsupported UTC offsets.
- Require an actual Gregorian `YYYY-MM-DD`, a supported offset and a nonblank account nonce before trusting a published session. Preserve valid raw nonce strings.
- Classify mutation URLs using the first decoded literal path segment, matching Flutter dispatch even when trailing components exist. Freeze day, offset and account bindings; replace duplicate binding fields.
- Preserve published timers across midnight while rejecting stale daily actions. This does not update SwiftUI layouts.

## Executed evidence

- Old committed production source reproduced false→0 and 0.5→0 offset acceptance with fresh/published UTC sessions on Linux Foundation.
- Final production-extracted Swift snapshot core: **17 cases passed**.
- Final production-extracted Swift timer core through the refactored runner: **19 cases passed**.
- Flutter iOS resources, snapshot service and Android resources regression: **61 cases passed**.
- Changed Dart resource test analysis: **no issues found**.
- `verification.json` binds the results to production, fixture and runner hashes and the actual merged Swift programs. Repeat runs are not counted as additional cases.

## Limits and remaining work

Linux Foundation execution does not prove Xcode/WidgetKit/SwiftUI compilation, timeline integration, rendered UI or server mutation acceptance. No connected Android/iOS devices or macOS toolchain were available. SwiftUI focus phase/intent consumption, calendar grid, profile lease consumption, broader bilingual flows and real device performance/notification/widget acceptance remain open.

No web or Android deployment was performed for this Swift-only production change. The full user goal remains incomplete.
