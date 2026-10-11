# Pin receipt retention — decision and implementation

Date: 2026-10-11 UTC. The original audit and proposal below are historical. Implementation is now accepted for JVM, Flutter and Android compilation; see [final scoped acceptance](widget-pin-retention-final-acceptance-20261011.md). Real launcher/device acceptance remains pending.

## Final protection contract

The implementation uses a 120-second monotonic handoff reservation before launcher submission. Actual waits register independent engine-owned tokens; these tokens do **not** expire at the Dart timeout and protect issued RPCs through awaited acknowledgement. Exact token release or engine detach/destroy/restart ends them; Activity recreation does not. Idle handoff expiry also triggers cleanup. The unattended budget is 64, incoming retained, plus protected/legacy/unknown data. This final lifecycle supersedes the proposal below that described protection expiring with custom wait timeouts.

## Confirmed lifecycle gap

`WidgetScreen._AddWidgetButtonState._request` passes the original local request ID to both `waitForPinResult` and `clearPinResult`. The request-isolation fix therefore matches its real consumer. However, early returns after request submission, polling, or widget refresh skip clearing when the page is no longer mounted (`widget_screen.dart`, currently lines 1077, 1091, and 1094). Two-minute timeout intentionally stops polling without cancelling the launcher request. A later successful receiver callback has no remaining consumer.

The former Android slot held at most one receipt. The new six-key namespaces retain one receipt per unconsumed ID, so repeated abandoned/late requests can grow storage permanently. They do not overwrite other IDs, but retention must be bounded before delivery.

## Selected direction for the next batch

The independent Sol audit recommends protecting active waiters and limiting only unattended receipts:

1. In the business manager, acknowledge a matching receipt after polling obtains it and before returning. Keep the existing UI clear idempotent. Acknowledgement alone does not cover a page closed before polling begins or a callback after timeout.
2. Establish native request protection before calling the launcher; cover the default two-minute wait after acceptance. When the manager actually starts waiting, register its real timeout, including custom timeouts. End protection when waiting ends. Timeout ends protection without cancelling the launcher or pending provider.
3. Apply an explicit resource budget of **64 unattended receipts**, plus protected active receipts and at most one legacy slot. Overflow removes only unprotected older records and preserves the incoming receipt. Protection expiry must also trigger cleanup so an idle app does not retain unbounded unattended records. ID-scoped writes/removals remain under the shared lock.

Protection uses a monotonic clock, with renewal/generation checks so an older delayed cleanup cannot remove a renewed active result. Process recreation and callback-before-wait ordering require an explicit implementation decision and tests; do not assume a stored deadline survives reboot or that a UI waiter survives process death.

This resource budget is not a launcher concurrency limit. A strict fixed total cap would additionally require request-time capacity reservation and pre-submission rejection when all slots are protected; that changes the external call behavior and is outside this selected minimal direction.

Do not reuse the four-minute pending-provider TTL as receipt expiry, or treat `confirmedAt` alone as proof that no caller still waits. These govern different lifetimes. Preserve successful late callbacks and `confirmed_unverified`.

## Required acceptance

- Manager acknowledgement occurs before returning a received result; timeout does not acknowledge or cancel.
- Accepted-but-unpolled requests and late callbacks are eventually within the unattended budget.
- Overflow preserves active A/B, their styles, the incoming receipt, legacy compatibility, and unrelated keys.
- Custom timeouts, renewal, old timer callbacks, expiry boundaries, clock rollback, and adapter/process reconstruction follow the selected protection contract.
- Cleanup does not modify provider TTL, callback side effects, account binding, or widget data.

This work belongs to business/native lifecycle code and does not require changing AGY-owned page layout. Account-switch feedback and busy-state observations remain separate UI risks without proven cross-account writes. Device launcher and real persistence acceptance remain open.
