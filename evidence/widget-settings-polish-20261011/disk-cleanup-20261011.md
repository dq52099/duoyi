# Disk cleanup — 2026-10-11

User requested removal of unnecessary build storage before more development. All Flutter/Gradle work was paused and active compiler/daemon processes were checked before deletion.

## Removed

- 48 reconstructable Flutter/Android build and cache directories, completed Flutter temporary files, and Gradle 8.14 dependency transformations: 6.418 GiB. Dependency downloads, the Android SDK and Flutter installation remain.
- 17 clean old Git worktrees whose HEAD commits are ancestors of main: 19.420 GiB. Normal `git worktree remove` succeeded for every candidate, without force; all branch refs and commit history remain.

Total allocated storage removed: **25.838 GiB**. Free disk space increased from about **4.4 GiB to 31 GiB**; usage fell from **98% to 85%**. The exact deletion list and measurements are recorded in `.dart_tool/task-temp-20261011/disk-cleanup-plan-20261011.json` and `worktree-retirement-cleanup-20261011.json`.

## Preserved and checked

SHA-256 checks before and after both rounds matched for **1,110 source/configuration/test files** and **110 deployed Web/download files**. Main repository evidence/screenshots, active candidate sources/tests/manifests/logs, and five old worktrees with unique or uncommitted work remain. No deployment, service restart, Docker pruning, database deletion, or new release was performed.

Deleted generated outputs will be recreated by the next requested build or test. Detailed final checks: `.dart_tool/task-temp-20261011/disk-cleanup-final-20261011.json`.
