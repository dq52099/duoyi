# Native widget display refinement — 2026-10-09

## Implemented

Anniversary widgets resolve the ordered union A1, A2, M1, M2, M3, retain legacy text, de-duplicate by decoded opaque identity and preserve paired text/navigation targets. Stale data displays one localized hint. Android density still controls one, two or three visible rows.

Calendar widgets pair event copy with its target and mark today using the widget palette. iOS renders a Monday-first real Gregorian month from the timeline entry date, localized month/weekdays and accessibility labels, with complete rows constrained by family, density and available height. Unsafe targets fall back to generic navigation. Strict percent decoding retains escaped punctuation, plus signs, legacy IDs and distinct Unicode normalization bytes.

## Executed verification

- 865 Flutter regressions across 65 files passed, including the merged Android day-boundary guards; the unmerged Profile draft fixture is excluded.
- Focused Dart analysis passed.
- 21 production-source pure Kotlin/JUnit display cases passed.
- Android Gradle tests passed: 21 display, 13 day-boundary and six native reminder cases.
- Swift production-extracted display (19 groups), snapshot (17 groups), and timer cores passed. These runs compile the extracted Foundation cores, not the WidgetKit target.
- Android arm64 debug APK compiled; SHA-256: `11e47f5fcda93dcd0fcc619115b4f3ac8a901317584ef53c45cc138e857f1827`.
- Frozen production and fixture hashes stayed unchanged throughout the acceptance commands. Exact commands, source hashes, logs and native XML reports are retained in this directory.

## Review and remaining acceptance

The final revision4 section in [source-audit.md](source-audit.md) closes the three reproduced Swift URI/identity findings. An initial wrong legacy-colon fixture expectation was corrected without altering production; its failed log is retained.

Integrated regression also exposed wrong static variable/old helper references and viewport-dependent fixture finders. Those assertions now use the actual calendar span wiring and scroll lazy content into view before checking retained state/layout. The matrix validator now ignores semicolon/slash prose in parenthetical evidence notes while still rejecting missing actual paths; both positive and negative checks pass. These changes preserve the tested behavior and do not change page layout.

Android immutable rendering frames, actual launcher/device behavior, iOS target compilation/layout, complete global localization and device performance remain open. No public artifact was replaced by this batch. The debug APK remains private for later integrated delivery; this evidence does not close the full product goal.
