# Account Boundary Copy — 2026-10-08

## Source changes

`AccountUiCopy.formatError` now translates the existing AuthProvider account-changed and account-switch-in-progress messages into the selected Chinese or English locale. A changed account asks the user to reopen the page; an in-progress change asks them to wait. It does not tell a valid new session to log in again.

## Verification

The existing account-copy regression file passes **10 cases**, including both ApiException and String inputs, Chinese and English source details, and Chinese → English → Chinese locale changes. Other credential, verification-code, disabled-account and technical-detail handling stays covered. Final file analysis is recorded in `verification.json`.

## Known incomplete profile behavior

Source review found that account A can open the avatar file chooser, switch to account B, and then receive the old file selection. The upload call currently captures the provider session only after the chooser and file read complete. Its HTTP completion guard cannot prevent submitting the old intent using B's credentials.

A future provider session-binding contract must be captured before the chooser/dialog await and consumed by the UI before sending requests or applying responses. Long-lived password/email dialogs and dirty profile drafts also need account binding. This copy change does **not** fix those flows.

This commit has not been rebuilt or deployed. The broader iOS default style, global localization, widget presentation, settings functionality and real-device smoothness goal remains open.
