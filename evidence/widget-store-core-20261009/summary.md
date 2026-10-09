# Native widget publication store foundation — 2026-10-09

## Implemented

- Strict ten-field/89-value document and native envelope retain typed counters, exact millisecond integers, opaque identity and clean tombstones.
- Native-computed tagged SHA-256 request digest preserves literals and exact expectations. Receipt replay precedes CAS, lease validation and token issuance.
- Initialize/resume/invalidate/advance/publish transitions enforce store/epoch/lease/document revisions. A reused applied presentation version cannot change the 22 brand/theme/navigation fields.
- Android SQLite uses a singleton complete envelope, a fixed operation lock, writer PERSIST/FULL checks and fresh-connection readback before applied acknowledgement. Unknown/corrupt data cannot authorize initialization. A custom non-destructive corruption handler preserves the store; localized collator initialization is disabled. Commit/readback uncertainty quarantines writes in the current process.
- A nonblocking acceptance helper holds the shared operation lock across revalidation and a synchronous UI acceptance callback.

## Evidence and limits

Four production files compiled with Kotlin 2.2.20 against Android 36. Existing publication document fixture: 10 tests passed. Source hashes were unchanged during verification. Two source-review findings were repaired and reviewed. This does not test transition or SQLite runtime, crash recovery, lock races, MethodChannel lifecycle or native display.

## Required continuation

Wire the platform bridge, Flutter validated workspace bootstrap/clear barrier/presentation controller and all publisher paths; switch Android and iOS readers to canonical storage; implement the iOS shared store. Verify the affected transitions, persistence and UI flows before deployment. Runtime smoothness and native launcher acceptance still require device evidence. The broader widget/global-language/Mine/settings objective remains active.
