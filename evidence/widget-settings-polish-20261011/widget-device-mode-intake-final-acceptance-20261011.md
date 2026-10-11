# Widget device display-mode intake acceptance — 2026-10-11

## Repair

Snapshot previously copied arbitrary `widget_display_mode` preference values into the frozen render frame. A wrong-type global value caused the real DisplayMode String getter to throw, preventing a safe cleared frame from replacing an old launcher image.

`DuoyiWidgetFrameCore.deviceDisplayValues` now copies only the global key and the current positive widget ID's key. Only exact String values `compact`, `standard`, and `detailed` are admitted. Snapshot uses this projection alongside the canonical publication document; preferences cannot supply business fields, account identity, publication state, locale, timer, or theme. Valid instance/global precedence and standard fallback remain unchanged.

## Actual evidence

- Kotlin 2.2.20 compilation exited **0**; JUnit 4.13.2 exited **0**, with **47 passing tests**. This reruns the existing 41 plus six new intake cases; earlier overlapping runs are not additional tests.
- The new cases reproduce the old raw typed-read exception and exercise the real Document → validated display projection → FrameCore → RenderFrame → FrozenPreferences → DisplayMode chain. They cover malformed types/strings, allowed modes, isolation from legacy business values, published/cleared/blocked/absent states, precedence, and valid mode-change rejection.
- All **11 compiled source/test hashes** matched before and after execution.
- Main-tree `android_widget_frame_static_test.dart` passed **6 checks**, including Snapshot helper wiring and removal of unchecked copying. Scoped analysis was clean. These six checks are already included in the separate 16-suite/80-test integration total.
- Independent source review accepted the bounded repair in `widget-publication-current-source-audit-20261011.md`.

The retained runner is `run-widget-device-mode-intake-jvm-20261011.py`. Exact compiler/JUnit commands, outputs, exits, dependency hashes, and source hashes are in `widget-device-mode-intake-jvm-acceptance-logs/`. This report records that completed execution; it does not rerun it.

## Accepted hashes

| File | SHA-256 |
| --- | --- |
| `DuoyiWidgetFrameCore.kt` | `509c73770b631d31740a884774d498669badda55e3f25d4c6da24eabf832af7c` |
| `DuoyiWidgetSnapshot.kt` | `98a73b8597906ca9c617cce5ef8963b285f724ae589e05ee159b68016c544351` |
| `DuoyiWidgetDeviceDisplayValuesTest.kt` | `cabf2a474789ab6bfe4b3f9261e76fab98cd863a585f0457abbd1d82f69638d1` |

## Limits

The pure JVM runner does not compile Snapshot, providers, or platform adapters. Snapshot integration is supported by source review and static wiring checks. Android launcher replacement, Binder, native store/transition behavior, real-device actions, and iOS rendering remain unverified. Neutral unpublished-state wording and standard preview accuracy remain pending frontend work. No APK, version bump, deployment, or release is produced by this acceptance.
