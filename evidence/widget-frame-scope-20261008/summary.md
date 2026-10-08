# Widget feedback origin and frame delivery — 2026-10-08

## Implementation

A shared `WidgetActionScope` retains the originating account generation and an
optional caller-availability predicate through waits and frame callbacks.
Hydration, bound action validation and refresh now retain that origin for their
failure, stale-content and result messages. Typed quick-todo uses the same scope
without changing its guest or reminder-permission behavior.

The frame adapter calls `ensureVisualUpdate`, so feedback produced while idle
requests a frame. Feedback registered during post-frame processing requests the
next frame; invalidated callbacks become no-ops. Flutter lifecycle rules still
control background rendering.

## Verification

The sequential final regression run passed **140 Flutter cases** (exit 0), with
unchanged source hashes before and after. Eleven new widget cases execute the
production frame adapter, including idle/current-frame/post-frame registration,
current SnackBar delivery and stale-account/caller suppression. Existing runtime
coordinator and real TodoProvider/mocked SharedPreferences persistence cases
also pass. Other fixtures cover native resources/snapshots, notifications,
todo storage and desktop main-shell rendering.

Targeted analysis of main, the shared scope, coordinator and three affected
fixtures passed with **no issues found** (exit 0). Exact commands and source/log
hashes are recorded in `verification.json`. The read-only source audit predates execution;
its pending-runtime wording is superseded by recorded test results here.

## Remaining acceptance

The source-wiring fixture connects main to the shared production adapter; it does
not execute every main hydration/deep-link/refresh branch. Mocked preferences do
not prove native disk persistence. Real permission UI, Android/iOS widget
behavior, cold-start/frame timing and full bilingual/default-iOS visual routes
remain open. Profile/Mine still need to consume the existing account-session
lease for dialogs, picker waits and local profile writes.

No new build, deployment, push or release is included in this batch. The complete
user objective remains active.
