# Actual old-source reproduction

Extracted from base commit `461b477c2c4cb7f65a2bdd0d2dc6157391aae743` and run with Swift 6.1.3 Linux Foundation; process exited 0. The first input is `NSNumber(value: false)`, whose description renders as 0.

```text
Timezone: Etc/UTC
Input=0 parsed=Optional(0) published=true fresh=true
Input=0.5 parsed=Optional(0) published=true fresh=true
GMT seconds=64800 accepted=true
GMT seconds=64801 accepted=false
GMT seconds=-64800 accepted=true
GMT seconds=-64801 accepted=false
```

The source audit was completed before final Swift execution; its pending runtime statement is historical. Final execution is recorded in verification.json. Apple/device acceptance remains pending.
