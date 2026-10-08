# Executed Swift Cases

```text
PASS: count-up derives elapsed seconds from its start anchor
PASS: countdown rounds remaining milliseconds up to seconds
PASS: countdown is ended at the exact end anchor
PASS: countdown seconds are clamped to the configured total
PASS: paused timer anchors may both be zero
PASS: countdown idle requires the complete saved duration
PASS: unpublished session does not restore saved timer state
PASS: focus action intent depends on a fresh timer phase
PASS: future count-up start stays running and exposes its start and cap
PASS: count-up remains running when its 24-hour cap is reached
PASS: count-up reaches its cap from a nonzero millisecond start anchor
PASS: missing, malformed, negative, and unrepresentable inputs are unavailable
PASS: seconds and total stay safe for accessory plus-59 formatting
PASS: timeline sorts and deduplicates midnight with an equal timer end
PASS: timeline retains the exact seconds of midnight and timer-end refreshes
PASS: running countdown updates across UTC midnight and ends at its anchor
PASS: paused countdown keeps its saved seconds across UTC midnight
PASS: timeline uses real 23-hour and 25-hour daylight-saving days
PASS: timeline includes only deadlines at or before the 48-hour horizon
```
