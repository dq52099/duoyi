# Widget publication descriptor fixtures — 2026-10-09

Fixture: `duoyi-worktrees/widget-publication-20261009/test/services/widget_publication_test.dart`.
It contains 14 unit tests for the ten-field v1 document and 89-value catalog,
copy/immutability and literal strings, strict malformed/unknown-schema decoding,
all 11 Int32 field ranges, both Int64 timer fields, revision/capture bounds,
year 1–9999 date validation, shared todo-count equality, and cleared/blocked
tombstone hygiene. The tombstone fixtures check all 67 business fields and
preservation of all 22 presentation fields.

These fixtures cover the generic DTO and its flat projection only. They do not
establish native owner binding, compare-and-swap, revision arbitration,
durability, acknowledgements, Android/iOS numeric conversion, or launcher
behavior. No SDK, formatter, test, build, or check was run; platform behavior
remains unverified.
