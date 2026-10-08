# iOS snapshot core audit — 2026-10-08

## Scope and result

Read-only audit of the working-tree `DuoyiWidgetSnapshot` patch, the new source-extracted Swift snapshot runner and fixture, and the shared timer-runner refactor. **No confirmed current snapshot-core blocker remains in the reviewed source.** Three defects in the prior source are closed by this patch: malformed NSNumber offsets could be treated as integer offsets; publication trust did not require valid day/offset metadata; mutation classification disagreed with Flutter for an action followed by an extra path segment.

This agent did not edit repository source or tests, run Swift/Flutter/Dart/Python verifiers, run builds or tests, or make network calls. Runtime verification is pending in this report; parent-agent execution evidence must be attached separately. Source review does not establish Apple SDK compilation, WidgetKit timeline behavior, rendered device UI, or server mutation acceptance.

Reviewed repository: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source`. Base HEAD: `461b477c2c4cb7f65a2bdd0d2dc6157391aae743`; these changes were uncommitted when reviewed.

| Reviewed file | SHA-256 |
| --- | --- |
| `ios/DuoyiWidgets/DuoyiWidgets.swift` | `afd5837be51e5d234836c66de54021fca3c4d35c14c85d29bda8a291093698ef` |
| `scripts/verify_ios_widget_snapshot_core.py` | `a12017ec031593921dc2486c04d0ee6d9c8a5427f0e24a17eed1af9a5cddc2fd` |
| `scripts/ios_widget_snapshot_core_cases.swift` | `d2606171dd8d300f3ddf33690c1a919490aa5dfffb621807b3439902e2b44941` |
| `scripts/verify_ios_widget_timer_core.py` | `bcba28f72988f20589afe2fc4fc37e0d7be2f2bd711f54c9fa0e9c0cd3e6d25a` |

## Offset parsing and publication trust

The former parser used NSNumber `.intValue`, which accepts Boolean false as zero and truncates fractional values such as 480.9 to 480. With an otherwise matching day and nonce, these malformed values could satisfy UTC or East-8 freshness. The former `hasPublishedSession` also accepted any nonblank day and nonce without checking that offset existed, so missing/malformed metadata could retain timer publication trust.

The current [offset parser](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:269) excludes CFBoolean, parses integer NSNumber strings before any Double conversion, and otherwise requires a finite Double, `Int(exactly:)`, and equality with the original NSNumber. This avoids truncation and loss of wide integer identity. String offsets retain the existing `Int(text)` compatibility; no trimming assignment was added. The parser checks multiplication by 60 with `multipliedReportingOverflow` before passing seconds to Foundation.

The supported offset domain is decided by `TimeZone(secondsFromGMT:)`, with checked arithmetic. This directly follows the Foundation implementation used by the target and avoids an arbitrary civil-zone ±14-hour cutoff. The fixture's ±1080-minute acceptance and ±1081-minute rejection need confirmation from the parent's Swift run; this audit did not independently execute Foundation and does not claim Apple-platform numeric boundary evidence.

The new [publication predicate](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:264) requires a valid Gregorian day, a parsed supported offset, and a nonce containing some non-whitespace text. Corrupt/missing day or offset therefore cannot restore a timer merely because a nonce exists.

## Canonical day compatibility and raw identity

The [day validator](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:292) requires exactly ten ASCII bytes in `YYYY-MM-DD` form, a positive year, bounded month/day components, and a Gregorian year/month/day round trip. UTC noon is used for this syntax/date validity check, avoiding a local DST transition or skipped local day as a reason to reject the metadata's calendar date. Normal leap-day errors and normalized impossible dates are rejected.

Ordinary current Flutter publication is compatible: [the publisher](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/home_widget_service.dart:446) writes the current Gregorian day with two-digit month/day and `timeZoneOffset.inMinutes`, and [publishes day last](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/home_widget_service.dart:663) after writing offset and checking that local day/offset have not changed.

There is one narrow extreme-system-date compatibility change. Flutter interpolates `${now.year}` without padding, and the prior Swift `%04d` format has a minimum width: a year at least 10000 could previously produce a matching five-digit-year day. The new ten-byte validator rejects it. Years below 1000 already failed ordinary daily freshness because the Dart/Swift year widths differed, though the old nonblank-day predicate could still trust a timer. This is not evidence of a regression for normal current dates; do not describe the new rule as accepting every theoretical Dart DateTime year. No additional date-age bound is justified by the current publication contract.

[The initializer](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:253) preserves raw day and nonce strings. Nonce whitespace is used only as a validity predicate; a valid padded nonce remains padded in outgoing bindings. A hex-only nonce restriction would be incompatible with [Flutter's reuse of an existing nonempty stored nonce](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/home_widget_service.dart:171), even though newly generated nonces use 32 hex characters.

## Daily freshness, timer trust, and injectable clocks

The injectable [freshness overload](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:315) rejects nonfinite dates, uses a Gregorian calendar with the supplied calendar's timezone, and compares both raw day and the timezone's offset at that date. A supplied Buddhist calendar does not silently change the publication calendar convention. The production wrapper still obtains a current Gregorian calendar and `.current` timezone; the action wrapper still uses `Date()`.

`hasPublishedSession` intentionally has no current-day comparison. A valid frozen prior-day publication remains published for a normal cross-midnight timer while `isFresh` becomes false and daily mutations are withheld. Same-day DST offset changes also invalidate daily freshness. Provider code [captures the dictionary once](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:677) and distinguishes fresh daily data from the publication trust used by the timer. The snapshot core neither rereads preferences nor rewrites day, nonce, or offset.

## Action classification and frozen bindings

The prior helper classified the entire trimmed path, whereas [Flutter dispatches `uri.pathSegments.first`](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:3989). Consequently, a supplied `duoyi://action/complete_todo/ignored?id=X` could previously be returned unbound by an empty or stale snapshot while Flutter would dispatch completion without `source=widget`. Normal current producers generate canonical paths; this finding does not establish that ordinary generated links used the malformed form.

The current [action helper](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/ios/DuoyiWidgets/DuoyiWidgets.swift:334) limits classification to the Duoyi action scheme/host, removes one leading literal slash, splits the percent-encoded path preserving empty segments, and decodes only its first literal segment. A trailing path component now still classifies as the receiver's mutation; an encoded slash remains inside one decoded segment and does not invent an action; a second leading slash preserves an empty first segment.

Completion, habit check-in, and focus start require fresh day/offset. Quick todo requires freshness whenever any `text` query item contains nonblank text. Using any nonblank duplicate is conservative: it may withhold a navigation form depending on which duplicate Flutter chooses, but it prevents classifying a possible typed mutation as unbound navigation. Navigation, refresh and empty quick entry pass through. The receiver's [quick todo branch](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4005) follows the same trimmed-nonblank text distinction for its selected value.

Mutation construction removes every old `source`, `widget_day`, `widget_offset`, and `widget_account` query item, then adds exactly one of each from the frozen snapshot. Item/action parameters remain intact. Changing the source dictionary after snapshot initialization cannot lend a newer account nonce to an older payload. [Flutter binding validation](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/home_widget_service.dart:194) checks raw day, nonce and offset against current runtime identity, and [bound dispatch](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4174) additionally checks account generation, mounted/auth availability, then removes `source` and dispatches. This review found no new identity borrowing path in the patched core.

## Runner and fixture source review

The [new runner](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/scripts/verify_ios_widget_snapshot_core.py:49) extracts the declarations between unique ordered production snapshot markers and merges them with the fixture. It does not maintain another implementation of snapshot parsing. It explicitly imports Foundation/CoreFoundation, retains a private run directory/file, prints core/fixture/merged hashes and case count, captures the interpreter result, and states the WidgetKit/SwiftUI/device/server limits of that result.

The [shared timer helper refactor](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/scripts/verify_ios_widget_timer_core.py:45) delegates the original timer extraction to a generic marker helper while retaining the timer marker constants and default private-directory prefix. Missing, misordered and duplicate markers are rejected, and Foundation/CoreFoundation imports must precede the selected marker. No unintended timer-runner semantic change was found in the source diff.

The snapshot fixture contains 17 named cases. Full source review covered normal UTC/East-8/half-hour offsets and string offsets; fixed-offset boundaries; Boolean/fraction/nonfinite/overflow rejection; missing and malformed day/offset/nonce; leap day and raw padded nonce; whitespace-only nonce rejection; midnight and DST staleness; injected non-Gregorian calendars; nonfinite dates; frozen bindings and duplicate removal; all mutation types; stale day/offset withholding; trailing/encoded path forms; navigation/refresh/empty entry; foreign scheme and nil/wrapper behavior. No incorrect fixture expectation was identified from source review. The fixture does not establish full Provider/timeline integration or Apple-platform behavior.

The updated Dart resource assertions track the production predicate, exact numeric parsing, injected freshness and first-segment routing. These are source-string checks; their existence is not runtime or compilation evidence. No verifier/test result is claimed by this audit.

## Evidence to attach before stronger conclusions

Attach the parent's snapshot runner output/status and printed core/fixture/merged hashes to establish portable Swift execution for the reviewed production core, including the supported offset boundaries. A successful portable runner still leaves Apple SDK WidgetKit/SwiftUI compilation, Provider/timeline integration, actual device interaction, and server mutation acceptance unverified. Runtime evidence recorded for earlier timer/auth commits must not be silently applied to this snapshot working-tree hash.
