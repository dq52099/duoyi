# Widget action copy and locale delivery — 2026-10-08

## Implementation

The guarded quick-todo coordinator is generic over message type. Main passes
immutable `WidgetActionMessage` descriptors and renders them only at actual
post-frame delivery, after origin and mounted checks. App-owned focus, task,
habit, hydration, validation, refresh and quick-add messages follow the language
selected at delivery; user names remain literal parameters.

Quick-add captures sync facts and reminder hints without rereading providers
while rendering. Its pure resolver preserves the existing status precedence,
including falling through when retry text is blank. Nullable custom issue titles
preserve the difference between omitted and explicitly empty labels.

Unknown reminder issues use neutral wording. A scheduler batch can contain
successful and failed rules, or an issue for a different task, so raw issue text
cannot establish that every reminder failed. Native/service title, message and
issue text, and user-visible sync reasons remain complete literal fields.

## Verification

Final expanded regression: **357 cases passed**, terminal exit 0, with the
success marker and all 19 frozen dependency hashes unchanged. Targeted analysis
of 12 paths: **No issues found**, terminal exit 0 (72.8 seconds), with the same
unchanged hashes. Exact commands, times, log hashes and source hashes are recorded
in `verification.json`.
Six message fixtures cover all 28 notice variants in both languages, nine sync
states/precedence, user names, raw reasons, custom/empty titles and reminder hints.
Five widget fixtures execute the production generic coordinator, frame scope
and renderer with a real Flutter messenger adapter. Source assertions check
main's adapter ordering; full main/native deep-link execution is separate.

Two legacy cloud error assertions failed identically on pristine base `0320cd6`.
Source/history audit traces them to the later safe-error contract. Revised
fixtures preserve and strengthen pending/local-data/acknowledgment guards, check
safe fallback and diagnostic exclusion, and require a valid subsequent
acknowledgment before clearing pending state. The corrected three-case run passed;
its cases are also included in the final expanded run. No error-filtering
production code was changed. An earlier interrupted partial run is not accepted
as passed, even though Flutter returned zero after SIGINT.

## Remaining acceptance

Raw service/server reasons still require typed codes for reliable localization.
Already visible messages and broader route/dialog locale rebuilds remain separate
from delivery-time copy. Mine/profile avatar/email/password flows still need the
existing session lease. WidgetKit rendering/actions, native calendar presentation,
default iOS visual review, Android/iOS permission/widget behavior and real-device
startup/frame timing remain open.

No new build, deployment, push or release is included. The complete objective
remains active; these checks do not close global localization or device gates.
