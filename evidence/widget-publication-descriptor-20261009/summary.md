# Complete widget publication descriptor — 2026-10-09

## Implemented

WidgetPublication represents one immutable ten-field v1 document with all 89 producer values. Identity metadata is projected only from the document; instance modes and launcher options remain separate. Unknown/missing/extra fields, unsupported versions/states/locales, wrong primitive types and invalid Gregorian dates are rejected. Published dates use exactly ten characters and years 1–9999.

All eleven Int32 fields have explicit bounds, including habit progress 0–100 and the published-only activity sentinel -1. Two timer millis fields and all revisions/capture millis stay within the nonnegative exact JSON integer interval. The two Todo count fields must agree. Cleared and blocked documents contain empty/zero/false business values for all 67 fields; clearedValuesFrom preserves the complete 22-field presentation while copying defensively. Locale revision explicitly represents locale, brand and theme together.

## Executed verification

ReminderDeliveryCopy also gains strict v1 seven-field semantic serialization for all five subjects. It rejects unknown or inconsistent facts, bounds signed day distances to exact JSON integers and preserves literal titles, rendering and fingerprints. These are descriptors only; pending physical registration updates are still separate work.

- 46 focused DTO, snapshot, cold-start and requirement-matrix checks passed.
- 1007 integrated Flutter regressions across 84 files passed; targeted analysis passed with unchanged current source/fixture hashes.
- Fourteen widget DTO fixtures cover all integer ranges and every business-field tombstone tamper, exact literal round trips, immutable maps, date and schema validation, and authoritative flat metadata. Sixteen reminder fixtures cover unchanged rendering/fingerprints and the new semantic serialization. Original producer/consumer checks remain intact.
- Commands, raw logs, current hashes and independent schema/fixture notes are retained.

## Integration boundary

This commit adds the complete validated descriptor; it does not yet replace the live multi-key publisher or authorize native writes. A valid descriptor is not an ownership or durability receipt. Native store/envelope/CAS, writer lease and durable auth transition barriers, canonical Android/iOS readers, latest presentation coordination and real platform acceptance remain required. No APK/public artifact is published by this batch. The full objective remains incomplete.
