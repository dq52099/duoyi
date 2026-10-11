# Workspace and focus penalty locale regression — 2026-10-11

## Result

The focused workspace and Pomodoro regression files passed: **18 tests, exit code 0**. Log: `.dart_tool/task-temp-20261011/workspace-penalty-locale-regression.log`.

Analysis of the two model files and their two regression files passed: **4 items, exit code 0**, no issues found. Log: `.dart_tool/task-temp-20261011/workspace-penalty-locale-analysis.log`.

## Covered contracts

- Workspace role labels and all six known activity action labels render in Chinese and English. Explicit-locale methods leave the selected locale unchanged.
- Unknown activity action codes, actor names, and detail remain literal. Role permissions, wire keys, and serialized workspace JSON stay stable across locales.
- All focus penalty reasons have bilingual labels while enum order and stable reason keys remain unchanged. Explicit-locale rendering does not mutate the selected locale.
- Penalty JSON retains its existing field order, reason keys, and Chinese `reasonLabel` values across locale changes.
