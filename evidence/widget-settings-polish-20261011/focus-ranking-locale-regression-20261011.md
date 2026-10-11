# Focus ranking locale regression — 2026-10-11

## Result

The focused model and provider regression files passed: **12 tests, exit code 0**. Log: `.dart_tool/task-temp-20261011/focus-ranking-locale-regression.log`.

Analysis of the model, provider, and two regression files passed: **4 items, exit code 0**, no issues found. Log: `.dart_tool/task-temp-20261011/focus-ranking-locale-analysis.log`.

## Covered contracts

- Cached local multi-reason and weekly-cap explanations follow the selected locale while credited/raw scores, session counts, ranks, reason masks, and input JSON remain stable.
- All six generated reason codes render in their defined order. Ranking headings and subtitles follow locale for friend and global scopes; explicit-locale rendering leaves the selected locale unchanged.
- A literal reason string identical to app-authored Chinese copy remains literal when no generated-reason provenance is set.
- A mocked provider response localizes the fallback for an empty remote risk summary. A nonempty server summary, including one identical to that Chinese fallback after trimming, remains literal in English; remote names and payload data remain unchanged.
