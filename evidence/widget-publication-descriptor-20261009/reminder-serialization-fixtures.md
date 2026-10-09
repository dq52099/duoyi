# ReminderDeliveryCopy serialization fixtures — 2026-10-09

Expanded `test/services/reminder_delivery_copy_test.dart` while preserving every existing renderer, raw-title, locale, and semantic-fingerprint fixture.

Added independent v1 schema fixtures for all five subjects: all four Todo rules; the complete four-rule by five-kind Goal matrix; both Habit semantic-push variants; every Anniversary kind; and Countdown. They assert the exact seven fields and order, fresh output maps, JSON round-trip, raw title code units, the existing six-fact fingerprint formula, and equivalent zh/en rendering under default, re0, and liquidGlass brand strings.

Additional fixtures cover empty/space-padded, CR/LF, actual-newline versus literal `\\n`, template-like, quoted, emoji, and composed/decomposed Unicode titles; signed Anniversary and Countdown day values including both exact JSON integer boundaries; `RangeError` and decoder rejection beyond either boundary; each field independently missing, null, or mistyped; unknown versions and strict enum spellings; extra and non-String keys; non-Map/fingerprint inputs; every subject's fixed-field invariants; reordered map keys; and locale notifier stability during serialization and decoding.

Expected descriptors are built from the independent contract field names and string values. Constructor enums are mapped explicitly in test helpers; production getters are not used to produce the expected schema. The existing production source was read only within the authorized boundary. No SDK, formatter, tests, Git, build, network, commit, deployment, or live Mine/Calendar/Todo production operations were run.
