# Diary and note locale acceptance — 2026-10-11

## Accepted implementation

- Mood and weather labels expose explicit-locale rendering and follow the live locale through their existing getters. Enum order, emoji, and stored indices stay stable.
- Empty diary/note headings share `DiaryNoteUiCopy`. Authored first lines remain literal, including text identical to a generated Chinese heading. Model JSON contains no new presentation fields.
- Calendar diary metadata carries a fallback date independently of an optional mood. The display resolver translates an existing empty diary snapshot even without mood. Raw calendar titles and JSON remain unchanged; a JSON round trip gains no inferred provenance.
- Ephemeral search hits carry typed generated-title provenance and render lazily. Content/tag matching, per-kind limits, source IDs, and navigation dates remain unchanged.
- Notes/diary CSV uses explicit Chinese presentation to preserve its historical schema across locales. Markdown headings use the locale captured for that export. The existing Chinese AI review prompt and summary also use explicit Chinese labels; history is not rewritten.

## Verification

All commands used `/home/ubuntu/flutter/bin/flutter`, `--no-pub`, and `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011`.

| Batch | Result | Log under task temp |
| --- | --- | --- |
| Four model/export/prompt test files | 18 passed, exit 0 | `domain-model-locale-regression.log` |
| Calendar/search/insights/provider/widget compatibility, six files | 59 passed, exit 0 | `domain-cached-title-compatible-regression.log` |
| Analysis of nine production and six test files | No issues, exit 0, 86.7 seconds | `domain-model-locale-analysis.log` |

There are **77 passing checks in these ten distinct test files**. Sol's read-only review found no blocking defect within this bounded diff. `git diff --check` passed for the owned source/test paths.

## Remaining integration

Calendar compact/day/week rows still read raw titles and need the display resolver. The search screen needs a locale repaint listener. These are AGY-owned frontend follow-ups; this acceptance does not claim those surfaces update live. Pending frontend account-boundary and layout blockers remain recorded in `parallel-integration-20261011.md`.

No APK build, signing, deployment, push, or device acceptance was performed for this change.
