# Today/Detail final boundaries acceptance

Date: 2026-10-11  
Candidate: `/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/today-candidate-e80678b`  
Manifest: `/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/today-detail-final-boundaries-candidate-manifest-20261011.json`

## Candidate integrity

Before testing, all eight manifest entries matched their expected SHA-256 values. The six production files and `today_mine_smoke_test.dart` remained unchanged through verification. The account-origin test was then adjusted for the lazy detail list fixture described below.

| File | Manifest SHA-256 | Final candidate SHA-256 |
|---|---|---|
| `lib/screens/today_screen.dart` | `7ca6f667c7945fdd5f74ccdab1a4aaf60abad352cdf9d0d88381e03b78d5c79b` | `7ca6f667c7945fdd5f74ccdab1a4aaf60abad352cdf9d0d88381e03b78d5c79b` |
| `lib/screens/todo_detail_screen.dart` | `9948289f7736e09c95f4d7e727b7eceef48343be09d6e3f226e204f0bf188c09` | `9948289f7736e09c95f4d7e727b7eceef48343be09d6e3f226e204f0bf188c09` |
| `lib/screens/today_detail_router.dart` | `768ffee674e0568208d3047ff109bd695dc0ab62bc74003d289656978e24f190` | `768ffee674e0568208d3047ff109bd695dc0ab62bc74003d289656978e24f190` |
| `lib/screens/todo_screen.dart` | `90a7c26e60898afa9a87c86f3e8623d4687253f862158c1b9db1e99628b3b1fb` | `90a7c26e60898afa9a87c86f3e8623d4687253f862158c1b9db1e99628b3b1fb` |
| `lib/core/todo_detail_ui_copy.dart` | `580c57ec1f2f02ff2031c8ff1fcd5d56b1c8cd3d212ecbb42cdfde339d1625a1` | `580c57ec1f2f02ff2031c8ff1fcd5d56b1c8cd3d212ecbb42cdfde339d1625a1` |
| `lib/providers/todo_provider.dart` | `76a0e0afaf06b1c39804a4db1033cad66cb0d2208e4d52e65b18cbb6de3d3055` | `76a0e0afaf06b1c39804a4db1033cad66cb0d2208e4d52e65b18cbb6de3d3055` |
| `test/screens/today_mine_smoke_test.dart` | `e50d9f564e2668707f8900a1ca53de87ae21eea87fa41cdc5853e4ab6bc0ceaa` | `e50d9f564e2668707f8900a1ca53de87ae21eea87fa41cdc5853e4ab6bc0ceaa` |
| `test/screens/todo_detail_account_origin_test.dart` | `0c867d4966dd6c6c7eb890f1fac71190e6c2b1c3eafe121e97e569a7bd51c91a` | `a78893feb82fedcdb0050d9dacb164a4f835a9c3606412cfe01aa15aad071611` |

The final account-origin test hash differs because the test initially tried to find a subtask checkbox before the detail `ListView` had built that offscreen row. It failed with `Bad state: No element` at the checkbox lookup. The test now scrolls the row into view, captures its callbacks, then returns to the title fields using their controller identities. This is a test fixture correction; no production file changed. The updated test is byte-identical in the candidate and main checkout.

## Test results

Commands ran serially from the candidate directory. Each command used `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011` and `/home/ubuntu/flutter/bin/flutter`.

| Suite | Command after any fixture correction | Result | Log |
|---|---|---:|---|
| Today/Mine smoke | `flutter test test/screens/today_mine_smoke_test.dart` | 25 passed | `today_mine_smoke_test.log` |
| Desktop widescreen shell | `flutter test test/screens/desktop_web_shell_widescreen_test.dart` | 11 passed | `desktop_web_shell_widescreen_test.log` |
| Detail account origin | `flutter test --no-pub test/screens/todo_detail_account_origin_test.dart` | 2 passed | `todo_detail_account_origin_test.log` |
| Detail save/stay | `flutter test --no-pub test/screens/todo_detail_save_stay_test.dart` | 10 passed | `todo_detail_save_stay_test.log` |
| Detail Markdown static | `flutter test --no-pub test/screens/todo_detail_markdown_static_test.dart` | 4 passed | `todo_detail_markdown_static_test.log` |
| Today detail router | `flutter test --no-pub test/screens/today_detail_router_test.dart` | 7 passed | `today_detail_router_test.log` |
| Today detail router static | `flutter test --no-pub test/screens/today_detail_router_static_test.dart` | 1 passed | `today_detail_router_static_test.log` |

Total: **60 tests passed** across the seven scoped suites. The account-origin suite first failed on the offscreen checkbox fixture; after the test-only correction it passed 2/2. The desktop suite was rerun after correcting the log directory; the captured run exited successfully with 11/11 passing.

## Focused analysis

Ran this focused analysis command from the candidate directory:

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter analyze --no-pub \
  lib/screens/today_screen.dart \
  lib/screens/todo_detail_screen.dart \
  lib/screens/today_detail_router.dart \
  lib/screens/todo_screen.dart \
  lib/core/todo_detail_ui_copy.dart \
  lib/providers/todo_provider.dart \
  test/screens/today_mine_smoke_test.dart \
  test/screens/desktop_web_shell_widescreen_test.dart \
  test/screens/todo_detail_account_origin_test.dart \
  test/screens/todo_detail_save_stay_test.dart \
  test/screens/todo_detail_markdown_static_test.dart \
  test/screens/today_detail_router_test.dart \
  test/screens/today_detail_router_static_test.dart
```

Result: **No issues found** (13 files, 127.5 seconds).

## Evidence and limits

Logs are in `evidence/widget-settings-polish-20261011/today-detail-final-boundaries-logs/`, including `focused_flutter_analyze.log`. Verification was limited to the listed Today/Detail suites and the 13-file analysis scope; this was not a full-project test or analysis run. The manifest pins eight files; the other five test files were run from the candidate checkout but are not individually hash-pinned by that manifest.
